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
        var input_precision = parser.precision

        var buffer = ImageBuffer(width, height, 1 if is_grayscale else 3, output_precision)

        if input_precision <= 8:
            ImageDrawer._dispatch_processing[True](
                buffer, width, height, is_grayscale,
                planes_y, planes_cb, planes_cr,
                cb_w, cb_h, cr_w, cr_h,
                level_shift, diff, max_val
            )
        else:
            ImageDrawer._dispatch_processing[False](
                buffer, width, height, is_grayscale,
                planes_y, planes_cb, planes_cr,
                cb_w, cb_h, cr_w, cr_h,
                level_shift, diff, max_val
            )

        return buffer^

    @staticmethod
    @always_inline
    def _dispatch_processing[is_fast: Bool](
        mut buffer: ImageBuffer,
        width: Int,
        height: Int,
        is_grayscale: Bool,
        planes_y: List[Float32],
        planes_cb: List[Float32],
        planes_cr: List[Float32],
        cb_w: Int, cb_h: Int,
        cr_w: Int, cr_h: Int,
        level_shift: Float32,
        diff: Int,
        max_val: Int
    ):
        """
        Helper dispatcher for passing is_16bit and is_grayscale into compile-time.
        """
        if buffer.is_16bit:
            if is_grayscale:
                ImageDrawer.process_image[True, True, is_fast](
                    buffer, width, height, planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h, level_shift, diff, max_val
                )
            else:
                ImageDrawer.process_image[True, False, is_fast](
                    buffer, width, height, planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h, level_shift, diff, max_val
                )
        else:
            if is_grayscale:
                ImageDrawer.process_image[False, True, is_fast](
                    buffer, width, height, planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h, level_shift, diff, max_val
                )
            else:
                ImageDrawer.process_image[False, False, is_fast](
                    buffer, width, height, planes_y, planes_cb, planes_cr,
                    cb_w, cb_h, cr_w, cr_h, level_shift, diff, max_val
                )

    @staticmethod
    @always_inline
    def process_image[is_16bit: Bool, is_grayscale: Bool, is_fast: Bool](
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

        # for regular 8-bit precision, we can use a fast path with nearest neighbor sampling
        var cb_x_map = List[Int]()
        var cr_x_map = List[Int]()

        # Lightweight lookup structures for bilinear interpolation coefficients to eliminate 12-bit noise/artifacts
        var cb_y0_map = List[Int]()
        var cb_y1_map = List[Int]()
        var cb_fy_map = List[Float32]()
        var cb_fy_inv_map = List[Float32]()

        var cr_y0_map = List[Int]()
        var cr_y1_map = List[Int]()
        var cr_fy_map = List[Float32]()
        var cr_fy_inv_map = List[Float32]()

        var cb_x0_map = List[Int]()
        var cb_x1_map = List[Int]()
        var cb_fx_map = List[Float32]()
        var cb_fx_inv_map = List[Float32]()

        var cr_x0_map = List[Int]()
        var cr_x1_map = List[Int]()
        var cr_fx_map = List[Float32]()
        var cr_fx_inv_map = List[Float32]()

        if is_fast:
            cb_x_map.resize(length=width, fill=0)
            cr_x_map.resize(length=width, fill=0)
        else:
            cb_y0_map.resize(length=height, fill=0)
            cb_y1_map.resize(length=height, fill=0)
            cb_fy_map.resize(length=height, fill=0.0)
            cb_fy_inv_map.resize(length=height, fill=0.0)

            cr_y0_map.resize(length=height, fill=0)
            cr_y1_map.resize(length=height, fill=0)
            cr_fy_map.resize(length=height, fill=0.0)
            cr_fy_inv_map.resize(length=height, fill=0.0)

            cb_x0_map.resize(length=width, fill=0)
            cb_x1_map.resize(length=width, fill=0)
            cb_fx_map.resize(length=width, fill=0.0)
            cb_fx_inv_map.resize(length=width, fill=0.0)

            cr_x0_map.resize(length=width, fill=0)
            cr_x1_map.resize(length=width, fill=0)
            cr_fx_map.resize(length=width, fill=0.0)
            cr_fx_inv_map.resize(length=width, fill=0.0)

        if not is_grayscale:

            for y in range(height):
                var cb_y = min(max((y * cb_h + height / 2) / height, 0), cb_h - 1)
                var cr_y = min(max((y * cr_h + height / 2) / height, 0), cr_h - 1)
                cb_row_offsets.unsafe_set(y, cb_y * cb_w)
                cr_row_offsets.unsafe_set(y, cr_y * cr_w)

            if is_fast:
                # --- 8-BIT FAST PATH (nearest neighbor) ---
                for x in range(width):
                    cb_x_map.unsafe_set(x, min(max((x * cb_w + width / 2) / width, 0), cb_w - 1))
                    cr_x_map.unsafe_set(x, min(max((x * cr_w + width / 2) / width, 0), cr_w - 1))
            else:
                # --- 12-BIT SLOW/ACCURATE PATH (bilinear interpolation) ---
                var inv_h_cb = Float32(cb_h) / Float32(height)
                var inv_h_cr = Float32(cr_h) / Float32(height)
                var inv_w_cb = Float32(cb_w) / Float32(width)
                var inv_w_cr = Float32(cr_w) / Float32(width)

                for y in range(height):
                    var cb_y_f = Float32(y) * inv_h_cb
                    var cb_y0 = max(0, min(Int(cb_y_f), cb_h - 1))
                    var cb_y1 = min(cb_y0 + 1, cb_h - 1)
                    var fy = max(Float32(0.0), cb_y_f - Float32(cb_y0))
                    cb_y0_map.unsafe_set(y, cb_y0 * cb_w)
                    cb_y1_map.unsafe_set(y, cb_y1 * cb_w)
                    cb_fy_map.unsafe_set(y, fy)
                    cb_fy_inv_map.unsafe_set(y, 1.0 - fy)

                    var cr_y_f = Float32(y) * inv_h_cr
                    var cr_y0 = max(0, min(Int(cr_y_f), cr_h - 1))
                    var cr_y1 = min(cr_y0 + 1, cr_h - 1)
                    var fy_cr = max(Float32(0.0), cr_y_f - Float32(cr_y0))
                    cr_y0_map.unsafe_set(y, cr_y0 * cr_w)
                    cr_y1_map.unsafe_set(y, cr_y1 * cr_w)
                    cr_fy_map.unsafe_set(y, fy_cr)
                    cr_fy_inv_map.unsafe_set(y, 1.0 - fy_cr)

                for x in range(width):
                    var cb_x_f = Float32(x) * inv_w_cb
                    var cb_x0 = max(0, min(Int(cb_x_f), cb_w - 1))
                    var cb_x1 = min(cb_x0 + 1, cb_w - 1)
                    var fx = max(Float32(0.0), cb_x_f - Float32(cb_x0))
                    cb_x0_map.unsafe_set(x, cb_x0)
                    cb_x1_map.unsafe_set(x, cb_x1)
                    cb_fx_map.unsafe_set(x, fx)
                    cb_fx_inv_map.unsafe_set(x, 1.0 - fx)

                    var cr_x_f = Float32(x) * inv_w_cr
                    var cr_x0 = max(0, min(Int(cr_x_f), cr_w - 1))
                    var cr_x1 = min(cr_x0 + 1, cr_w - 1)
                    var fx_cr = max(Float32(0.0), cr_x_f - Float32(cr_x0))
                    cr_x0_map.unsafe_set(x, cr_x0)
                    cr_x1_map.unsafe_set(x, cr_x1)
                    cr_fx_map.unsafe_set(x, fx_cr)
                    cr_fx_inv_map.unsafe_set(x, 1.0 - fx_cr)

        # --- OPTIMIZATION: Precompute scaling multiplier for Float32 vectors ---
        var max_val_f = Float32(max_val)
        var diff_mult = Float32(1.0)
        if diff > 0:
            diff_mult = Float32(1 << diff)
        elif diff < 0:
            diff_mult = 1.0 / Float32(1 << -diff)

        var vec_x_end = width - (width % simd_w)

        for y in range(height):
            var cb_row_offset: Int = 0
            var cr_row_offset: Int = 0
            var y_row_base: Int = 0

            var cb_y0_off: Int = 0
            var cb_y1_off: Int = 0
            var cb_fy: Float32 = 0.0
            var cb_fy_inv: Float32 = 0.0

            var cr_y0_off: Int = 0
            var cr_y1_off: Int = 0
            var cr_fy: Float32 = 0.0
            var cr_fy_inv: Float32 = 0.0

            if not is_grayscale:
                cb_row_offset = cb_row_offsets.unsafe_get(y)
                cr_row_offset = cr_row_offsets.unsafe_get(y)
                y_row_base = y * width

                if not is_fast:
                    cb_y0_off = cb_y0_map.unsafe_get(y)
                    cb_y1_off = cb_y1_map.unsafe_get(y)
                    cb_fy = cb_fy_map.unsafe_get(y)
                    cb_fy_inv = cb_fy_inv_map.unsafe_get(y)

                    cr_y0_off = cr_y0_map.unsafe_get(y)
                    cr_y1_off = cr_y1_map.unsafe_get(y)
                    cr_fy = cr_fy_map.unsafe_get(y)
                    cr_fy_inv = cr_fy_inv_map.unsafe_get(y)

            for x in range(0, vec_x_end, simd_w):
                var y_idx = y_row_base + x
                var y_vec = planes_y_ptr.unsafe_offset(y_idx).unsafe_load[width=simd_w]()

                var r_vec: SIMD[DType.float32, simd_w]
                var g_vec: SIMD[DType.float32, simd_w]
                var b_vec: SIMD[DType.float32, simd_w]

                if is_grayscale:
                    r_vec = y_vec
                    if diff != 0:
                        r_vec *= diff_mult
                    r_vec = r_vec.clamp(0.0, max_val_f)

                    if is_16bit:
                        ptr_u16.unsafe_offset(pixel_offset).unsafe_store(r_vec.cast[DType.uint16]())
                    else:
                        ptr_u8.unsafe_offset(pixel_offset).unsafe_store(r_vec.cast[DType.uint8]())

                    pixel_offset += simd_w
                else:
                    var cb_vec = SIMD[DType.float32, simd_w]()
                    var cr_vec = SIMD[DType.float32, simd_w]()

                    if is_fast:
                        comptime for i in range(simd_w):
                            var px = x + i
                            var cx = cb_x_map.unsafe_get(px)
                            var rx = cr_x_map.unsafe_get(px)
                            cb_vec[i] = planes_cb_ptr.unsafe_load(cb_row_offset + cx) - level_shift
                            cr_vec[i] = planes_cr_ptr.unsafe_load(cr_row_offset + rx) - level_shift
                    else:
                        comptime for i in range(simd_w):
                            var px = x + i
                            var cx0 = cb_x0_map.unsafe_get(px)
                            var cx1 = cb_x1_map.unsafe_get(px)
                            var fx = cb_fx_map.unsafe_get(px)
                            var fx_inv = cb_fx_inv_map.unsafe_get(px)

                            var cb_v00 = planes_cb_ptr.unsafe_load(cb_y0_off + cx0)
                            var cb_v01 = planes_cb_ptr.unsafe_load(cb_y0_off + cx1)
                            var cb_v10 = planes_cb_ptr.unsafe_load(cb_y1_off + cx0)
                            var cb_v11 = planes_cb_ptr.unsafe_load(cb_y1_off + cx1)
                            cb_vec[i] = ((cb_v00 * fx_inv + cb_v01 * fx) * cb_fy_inv + (cb_v10 * fx_inv + cb_v11 * fx) * cb_fy) - level_shift

                            var rx0 = cr_x0_map.unsafe_get(px)
                            var rx1 = cr_x1_map.unsafe_get(px)
                            var fx_c = cr_fx_map.unsafe_get(px)
                            var fx_c_inv = cr_fx_inv_map.unsafe_get(px)

                            var cr_v00 = planes_cr_ptr.unsafe_load(cr_y0_off + rx0)
                            var cr_v01 = planes_cr_ptr.unsafe_load(cr_y0_off + rx1)
                            var cr_v10 = planes_cr_ptr.unsafe_load(cr_y1_off + rx0)
                            var cr_v11 = planes_cr_ptr.unsafe_load(cr_y1_off + rx1)
                            cr_vec[i] = ((cr_v00 * fx_c_inv + cr_v01 * fx_c) * cr_fy_inv + (cr_v10 * fx_c_inv + cr_v11 * fx_c) * cr_fy) - level_shift

                    r_vec = y_vec + 1.402 * cr_vec
                    g_vec = y_vec - 0.344136 * cb_vec - 0.714136 * cr_vec
                    b_vec = y_vec + 1.772 * cb_vec

                    if diff != 0:
                        r_vec *= diff_mult
                        g_vec *= diff_mult
                        b_vec *= diff_mult

                    r_vec = r_vec.clamp(0.0, max_val_f)
                    g_vec = g_vec.clamp(0.0, max_val_f)
                    b_vec = b_vec.clamp(0.0, max_val_f)

                    if is_16bit:
                        var r_u16 = r_vec.cast[DType.uint16]()
                        var g_u16 = g_vec.cast[DType.uint16]()
                        var b_u16 = b_vec.cast[DType.uint16]()
                        comptime for i in range(simd_w):
                            var po = pixel_offset + i * 3
                            ptr_u16.unsafe_offset(po).unsafe_store(r_u16[i])
                            ptr_u16.unsafe_offset(po+1).unsafe_store(g_u16[i])
                            ptr_u16.unsafe_offset(po+2).unsafe_store(b_u16[i])
                    else:
                        var r_u8 = r_vec.cast[DType.uint8]()
                        var g_u8 = g_vec.cast[DType.uint8]()
                        var b_u8 = b_vec.cast[DType.uint8]()
                        comptime for i in range(simd_w):
                            var po = pixel_offset + i * 3
                            ptr_u8.unsafe_offset(po).unsafe_store(r_u8[i])
                            ptr_u8.unsafe_offset(po+1).unsafe_store(g_u8[i])
                            ptr_u8.unsafe_offset(po+2).unsafe_store(b_u8[i])

                    pixel_offset += simd_w * 3

            # --- SCALAR TAIL LOOP ---
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
                        ptr_u16.unsafe_offset(pixel_offset).unsafe_store(UInt16(r))
                    else:
                        ptr_u8.unsafe_offset(pixel_offset).unsafe_store(UInt8(r))
                    pixel_offset += 1
                else:
                    var cb_val: Float32
                    var cr_val: Float32

                    if is_fast:
                        var cx = cb_x_map.unsafe_get(x)
                        var rx = cr_x_map.unsafe_get(x)
                        cb_val = planes_cb_ptr.unsafe_load(cb_row_offset + cx) - level_shift
                        cr_val = planes_cr_ptr.unsafe_load(cr_row_offset + rx) - level_shift
                    else:
                        var cx0 = cb_x0_map.unsafe_get(x)
                        var cx1 = cb_x1_map.unsafe_get(x)
                        var fx = cb_fx_map.unsafe_get(x)
                        var fx_inv = cb_fx_inv_map.unsafe_get(x)
                        var cb_v00 = planes_cb_ptr.unsafe_load(cb_y0_off + cx0)
                        var cb_v01 = planes_cb_ptr.unsafe_load(cb_y0_off + cx1)
                        var cb_v10 = planes_cb_ptr.unsafe_load(cb_y1_off + cx0)
                        var cb_v11 = planes_cb_ptr.unsafe_load(cb_y1_off + cx1)
                        cb_val = ((cb_v00 * fx_inv + cb_v01 * fx) * cb_fy_inv + (cb_v10 * fx_inv + cb_v11 * fx) * cb_fy) - level_shift

                        var rx0 = cr_x0_map.unsafe_get(x)
                        var rx1 = cr_x1_map.unsafe_get(x)
                        var fx_c = cr_fx_map.unsafe_get(x)
                        var fx_c_inv = cr_fx_inv_map.unsafe_get(x)
                        var cr_v00 = planes_cr_ptr.unsafe_load(cr_y0_off + rx0)
                        var cr_v01 = planes_cr_ptr.unsafe_load(cr_y0_off + rx1)
                        var cr_v10 = planes_cr_ptr.unsafe_load(cr_y1_off + rx0)
                        var cr_v11 = planes_cr_ptr.unsafe_load(cr_y1_off + rx1)
                        cr_val = ((cr_v00 * fx_c_inv + cr_v01 * fx_c) * cr_fy_inv + (cr_v10 * fx_c_inv + cr_v11 * fx_c) * cr_fy) - level_shift

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
            buffer.data_u16.resize(unsafe_uninit_length=width * height * buffer.channels)
        else:
            buffer.data_u8.resize(unsafe_uninit_length=width * height * buffer.channels)