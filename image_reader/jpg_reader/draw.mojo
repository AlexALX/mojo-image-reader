from image_reader.jpg_reader.parser import JpegComponent, JpegParser
from image_reader.buffer import ImageBuffer

struct ImageDrawer:
    @staticmethod
    @always_inline
    def copy_block_to_plane(
        ref block: List[Float32],
        mcu_idx: Int,
        block_num: Int,
        ref comp: JpegComponent,
        mcus_per_row: Int,
        mut plane: List[Float32]
    ):
        """
        Copies an 8x8 block into the correct position of the component plane (optimized).
        """
        var comp_w = comp.width
        var comp_h = comp.height
        var h_factor = comp.h
        var v_factor = comp.v

        var mcu_x = mcu_idx % mcus_per_row
        var mcu_y = mcu_idx // mcus_per_row

        var block_x_in_mcu = block_num % h_factor
        var block_y_in_mcu = block_num // h_factor

        var final_x = (mcu_x * h_factor + block_x_in_mcu) * 8
        var final_y = (mcu_y * v_factor + block_y_in_mcu) * 8

        var block_ptr = block.unsafe_ptr()
        var plane_ptr = plane.unsafe_ptr()
        var block_index = 0
        for by in range(8):
            var py = final_y + by
            if py >= comp_h:
                break
            var row_offset = py * comp_w

            if final_x + 8 <= comp_w:
                var row_vec = block_ptr.unsafe_offset(block_index).unsafe_load[width=8]()
                plane_ptr.unsafe_offset(row_offset + final_x).unsafe_store(row_vec)
            else:
                for bx in range(8):
                    var px = final_x + bx
                    if px < comp_w:
                        var val = block_ptr.unsafe_load(block_index + bx)
                        plane_ptr.unsafe_store(row_offset + px, val)

            block_index += 8

    @staticmethod
    def assemble_to_buffer(
        ref parser: JpegParser,
        planes_y: List[Float32],
        planes_cb: List[Float32],
        planes_cr: List[Float32]
    ) raises -> ImageBuffer:
        """
        Assembles the final image from Y, Cb, Cr planes, handling chroma subsampling,
        applies correct YCbCr to RGB color conversion, and output as ImageBuffer.
        """
        var width = parser.width
        var height = parser.height
        ref components = parser.components

        var is_grayscale = parser.component_count == 1

        var cb_w = 0
        var cb_h = 0
        var cr_w = 0
        var cr_h = 0

        if not is_grayscale:
            # Retrieve Cb (index 2) and Cr (index 3) metadata
            # Assuming 1-based indexing structure for components
            ref cb_comp = components[2]
            ref cr_comp = components[3]

            cb_w = cb_comp.width
            cb_h = cb_comp.height
            cr_w = cr_comp.width
            cr_h = cr_comp.height

        var level_shift = Float32(parser.level_shift)

        var max_val = (1 << parser.output_precision) - 1
        var diff = parser.precision_diff
        var output_precision = parser.output_precision

        var buffer = ImageBuffer(width, height, 3, output_precision)

        if buffer.is_16bit:
            if is_grayscale:
                ImageDrawer.process_image[True, True](
                    buffer, width, height,
                    planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h,
                    level_shift, diff, max_val
                )
            else:
                ImageDrawer.process_image[True, False](
                    buffer, width, height,
                    planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h,
                    level_shift, diff, max_val
                )
        else:
            if is_grayscale:
                ImageDrawer.process_image[False, True](
                    buffer, width, height,
                    planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h,
                    level_shift, diff, max_val
                )
            else:
                ImageDrawer.process_image[False, False](
                    buffer, width, height,
                    planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h,
                    level_shift, diff, max_val
                )

        return buffer^

    @staticmethod
    @always_inline
    def process_image[is_16bit: Bool, is_grayscale: Bool](
        mut buffer: ImageBuffer,
        width: Int,
        height: Int,
        planes_y: List[Float32],
        planes_cb: List[Float32],
        planes_cr: List[Float32],
        cb_w: Int, cb_h: Int,
        cr_w: Int, cr_h: Int,
        level_shift: Float32,
        diff: Int,
        max_val: Int
    ):

        comptime simd_w = 8
        var planes_y_ptr = planes_y.unsafe_ptr()
        var planes_cb_ptr = planes_cb.unsafe_ptr()
        var planes_cr_ptr = planes_cr.unsafe_ptr()
        var ptr_u8 = buffer.data_u8.unsafe_ptr()
        var ptr_u16 = buffer.data_u16.unsafe_ptr()

        var pixel_offset = 0

        var cb_row_offsets = List[Int](length=height, fill=0)
        var cr_row_offsets = List[Int](length=height, fill=0)
        var cb_x_map = List[Int](length=width, fill=0)
        var cr_x_map = List[Int](length=width, fill=0)

        if not is_grayscale:
            for y in range(height):
                var cb_y = (y * cb_h) / height
                var cr_y = (y * cr_h) / height
                cb_row_offsets[y] = cb_y * cb_w
                cr_row_offsets[y] = cr_y * cr_w

            for x in range(width):
                cb_x_map[x] = (x * cb_w) / width
                cr_x_map[x] = (x * cr_w) / width

        # --- OPTIMIZATION: Precompute scaling multiplier for Float32 vectors ---
        var max_val_f = Float32(max_val)
        var diff_mult = Float32(1.0)
        if diff > 0:
            diff_mult = Float32(1 << diff)
        elif diff < 0:
            diff_mult = 1.0 / Float32(1 << -diff)

        # Calculate the boundary for SIMD execution
        var vec_x_end = width - (width % simd_w)

        # Loop through every pixel on the target image grid
        for y in range(height):
            var cb_row_offset = cb_row_offsets[y]
            var cr_row_offset = cr_row_offsets[y]
            var y_row_base = y * width

            for x in range(0, vec_x_end, simd_w):
                var y_idx = y_row_base + x

                # Load 8 Luma values directly into a SIMD vector
                var y_vec = planes_y_ptr.unsafe_offset(y_idx).unsafe_load[width=simd_w]()

                var r_vec: SIMD[DType.float32, simd_w]
                var g_vec: SIMD[DType.float32, simd_w]
                var b_vec: SIMD[DType.float32, simd_w]

                if is_grayscale:
                    r_vec = y_vec

                    if diff != 0:
                        r_vec *= diff_mult

                    r_vec = r_vec.clamp(0.0, max_val_f)

                    # Cast and store to the interleaved buffer
                    if is_16bit:
                        var r_u16 = r_vec.cast[DType.uint16]()
                        for i in range(simd_w):
                            var po = pixel_offset + i * 3
                            ptr_u16.unsafe_offset(po).unsafe_store(r_u16[i])
                            ptr_u16.unsafe_offset(po+1).unsafe_store(r_u16[i])
                            ptr_u16.unsafe_offset(po+2).unsafe_store(r_u16[i])
                    else:
                        var r_u8 = r_vec.cast[DType.uint8]()
                        for i in range(simd_w):
                            var po = pixel_offset + i * 3
                            ptr_u8.unsafe_offset(po).unsafe_store(r_u8[i])
                            ptr_u8.unsafe_offset(po+1).unsafe_store(r_u8[i])
                            ptr_u8.unsafe_offset(po+2).unsafe_store(r_u8[i])
                else:
                    var cb_vec = SIMD[DType.float32, simd_w]()
                    var cr_vec = SIMD[DType.float32, simd_w]()

                    # Pack Cb/Cr vectors due to the variable subsampling map
                    for i in range(simd_w):
                        var cb_idx = cb_row_offset + cb_x_map[x + i]
                        var cr_idx = cr_row_offset + cr_x_map[x + i]
                        cb_vec[i] = planes_cb_ptr.unsafe_load(cb_idx) - level_shift
                        cr_vec[i] = planes_cr_ptr.unsafe_load(cr_idx) - level_shift

                    # Vectorized YCbCr to RGB math
                    r_vec = y_vec + 1.402 * cr_vec
                    g_vec = y_vec - 0.344136 * cb_vec - 0.714136 * cr_vec
                    b_vec = y_vec + 1.772 * cb_vec

                    # Apply bit shift equivalents via vector multiplication
                    if diff != 0:
                        r_vec *= diff_mult
                        g_vec *= diff_mult
                        b_vec *= diff_mult

                    # Vectorized clamp
                    r_vec = r_vec.clamp(0.0, max_val_f)
                    g_vec = g_vec.clamp(0.0, max_val_f)
                    b_vec = b_vec.clamp(0.0, max_val_f)

                    # Cast and store to the interleaved buffer
                    if is_16bit:
                        var r_u16 = r_vec.cast[DType.uint16]()
                        var g_u16 = g_vec.cast[DType.uint16]()
                        var b_u16 = b_vec.cast[DType.uint16]()
                        for i in range(simd_w):
                            var po = pixel_offset + i * 3
                            ptr_u16.unsafe_offset(po).unsafe_store(r_u16[i])
                            ptr_u16.unsafe_offset(po+1).unsafe_store(g_u16[i])
                            ptr_u16.unsafe_offset(po+2).unsafe_store(b_u16[i])
                    else:
                        var r_u8 = r_vec.cast[DType.uint8]()
                        var g_u8 = g_vec.cast[DType.uint8]()
                        var b_u8 = b_vec.cast[DType.uint8]()
                        for i in range(simd_w):
                            var po = pixel_offset + i * 3
                            ptr_u8.unsafe_offset(po).unsafe_store(r_u8[i])
                            ptr_u8.unsafe_offset(po+1).unsafe_store(g_u8[i])
                            ptr_u8.unsafe_offset(po+2).unsafe_store(b_u8[i])

                pixel_offset += simd_w * 3

            # --- SCALAR TAIL LOOP: Handles remaining pixels if width is not a multiple of 8 ---
            for x in range(vec_x_end, width):
                var y_idx = y_row_base + x
                var y_val = planes_y_ptr.unsafe_load(y_idx)

                var r: Float32
                var g: Float32
                var b: Float32

                if is_grayscale:
                    r = y_val

                    if diff != 0:
                        r *= diff_mult

                    r = max[Float32](0.0, min(max_val_f, r))

                    if is_16bit:
                        var r_val = UInt16(r)
                        ptr_u16.unsafe_offset(pixel_offset).unsafe_store(r_val)
                        ptr_u16.unsafe_offset(pixel_offset+1).unsafe_store(r_val)
                        ptr_u16.unsafe_offset(pixel_offset+2).unsafe_store(r_val)
                    else:
                        var r_val = UInt8(r)
                        ptr_u8.unsafe_offset(pixel_offset).unsafe_store(r_val)
                        ptr_u8.unsafe_offset(pixel_offset+1).unsafe_store(r_val)
                        ptr_u8.unsafe_offset(pixel_offset+2).unsafe_store(r_val)
                else:
                    var cb_idx = cb_row_offset + cb_x_map[x]
                    var cr_idx = cr_row_offset + cr_x_map[x]
                    var cb_val = planes_cb_ptr.unsafe_load(cb_idx) - level_shift
                    var cr_val = planes_cr_ptr.unsafe_load(cr_idx) - level_shift

                    r = y_val + 1.402 * cr_val
                    g = y_val - 0.344136 * cb_val - 0.714136 * cr_val
                    b = y_val + 1.772 * cb_val

                    if diff != 0:
                        r *= diff_mult
                        g *= diff_mult
                        b *= diff_mult

                    r = max[Float32](0.0, min(max_val_f, r))
                    g = max[Float32](0.0, min(max_val_f, g))
                    b = max[Float32](0.0, min(max_val_f, b))

                    if is_16bit:
                        ptr_u16.unsafe_offset(pixel_offset).unsafe_store(UInt16(r))
                        ptr_u16.unsafe_offset(pixel_offset+1).unsafe_store(UInt16(g))
                        ptr_u16.unsafe_offset(pixel_offset+2).unsafe_store(UInt16(b))
                    else:
                        ptr_u8.unsafe_offset(pixel_offset).unsafe_store(UInt8(r))
                        ptr_u8.unsafe_offset(pixel_offset+1).unsafe_store(UInt8(g))
                        ptr_u8.unsafe_offset(pixel_offset+2).unsafe_store(UInt8(b))

                pixel_offset += 3

        if is_16bit:
            buffer.data_u16.resize(unsafe_uninit_length=width * height * 3)
        else:
            buffer.data_u8.resize(unsafe_uninit_length=width * height * 3)