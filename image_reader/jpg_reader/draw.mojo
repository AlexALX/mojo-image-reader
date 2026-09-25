from image_reader.jpg_reader.parser import JpegComponent, JpegParser
from image_reader.buffer import ImageBuffer

struct ImageDrawer:
    @staticmethod
    def copy_block_to_plane(
        ref block: List[Float64],
        component_id: Int,
        mcu_idx: Int,
        block_num: Int,
        ref components: List[JpegComponent],
        mcus_per_row: Int,
        mut planes_y: List[Float64],
        mut planes_cb: List[Float64],
        mut planes_cr: List[Float64]
    ):
        """
        Copies an 8x8 block into the correct position of the component plane.
        """

        ref comp = components[component_id]
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

        var block_index = 0
        for by in range(8):
            var py = final_y + by
            if py >= comp_h:
                break
            var row_offset = py * comp_w
            for bx in range(8):
                var px = final_x + bx
                if px >= comp_w:
                    block_index += 1
                    continue

                var val = block[block_index]

                if component_id == 1:
                    planes_y[row_offset + px] = val
                elif component_id == 2:
                    planes_cb[row_offset + px] = val
                else:
                    planes_cr[row_offset + px] = val

                block_index += 1

    @staticmethod
    def assemble_to_buffer(
        ref parser: JpegParser,
        planes_y: List[Float64],
        planes_cb: List[Float64],
        planes_cr: List[Float64]
    ) raises -> ImageBuffer:
        """
        Assembles the final image from Y, Cb, Cr planes, handling chroma subsampling,
        applies correct YCbCr to RGB color conversion, and output as ImageBuffer.
        """
        var width = parser.width
        var height = parser.height
        ref components = parser.components

        # Retrieve Cb (index 2) and Cr (index 3) metadata
        # Assuming 1-based indexing structure for components
        ref cb_comp = components[2]
        ref cr_comp = components[3]

        var cb_w = cb_comp.width
        var cb_h = cb_comp.height
        var cr_w = cr_comp.width
        var cr_h = cr_comp.height

        var level_shift = Float64(parser.level_shift)

        var max_val = (1 << parser.output_precision) - 1
        var diff = parser.precision_diff
        var output_precision = parser.output_precision

        var buffer = ImageBuffer(width, height, 3, output_precision)

        if buffer.is_16bit:
            ImageDrawer.process_image[True](
                buffer, width, height,
                planes_y, planes_cb, planes_cr,
                cb_w, cb_h, cr_w, cr_h,
                level_shift, diff, max_val
            )
        else:
            ImageDrawer.process_image[False](
                buffer, width, height,
                planes_y, planes_cb, planes_cr,
                cb_w, cb_h, cr_w, cr_h,
                level_shift, diff, max_val
            )

        return buffer^

    @staticmethod
    @always_inline
    def process_image[is_16bit: Bool](
        mut buffer: ImageBuffer,
        width: Int,
        height: Int,
        planes_y: List[Float64],
        planes_cb: List[Float64],
        planes_cr: List[Float64],
        cb_w: Int, cb_h: Int,
        cr_w: Int, cr_h: Int,
        level_shift: Float64,
        diff: Int,
        max_val: Int
    ):
        # Loop through every pixel on the target image grid
        for y in range(height):
            var cb_y = (y * cb_h) / height
            var cr_y = (y * cr_h) / height
            var cb_row_offset = cb_y * cb_w
            var cr_row_offset = cr_y * cr_w

            for x in range(width):
                var y_idx = y * width + x

                # Fetch Luma value directly (already clamped/level-shifted during IDCT)
                var y_val = planes_y[y_idx]

                # Map pixel coordinates to chroma planes considering subsampling scale
                var cb_x = (x * cb_w) / width
                var cr_x = (x * cr_w) / width

                var cb_idx = cb_row_offset + cb_x
                var cr_idx = cr_row_offset + cr_x

                var cb_val = (planes_cb[cb_idx] - level_shift)
                var cr_val = (planes_cr[cr_idx] - level_shift)

                # Standard JPEG YCbCr to RGB conversion formulas
                var r = y_val + 1.402 * cr_val
                var g = y_val - 0.344136 * cb_val - 0.714136 * cr_val
                var b = y_val + 1.772 * cb_val

                var scaled_r: Int
                var scaled_g: Int
                var scaled_b: Int

                if diff > 0:
                    scaled_r = Int(r) << diff
                    scaled_g = Int(g) << diff
                    scaled_b = Int(b) << diff
                elif diff < 0:
                    scaled_r = Int(r) >> (-diff)
                    scaled_g = Int(g) >> (-diff)
                    scaled_b = Int(b) >> (-diff)
                else:
                    scaled_r = Int(r)
                    scaled_g = Int(g)
                    scaled_b = Int(b)

                var final_r = min(max_val, max(0, Int(scaled_r)))
                var final_g = min(max_val, max(0, Int(scaled_g)))
                var final_b = min(max_val, max(0, Int(scaled_b)))

                if is_16bit:
                    buffer.data_u16.append(UInt16(final_r))
                    buffer.data_u16.append(UInt16(final_g))
                    buffer.data_u16.append(UInt16(final_b))
                else:
                    buffer.data_u8.append(UInt8(final_r))
                    buffer.data_u8.append(UInt8(final_g))
                    buffer.data_u8.append(UInt8(final_b))