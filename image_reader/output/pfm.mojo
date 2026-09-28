from image_reader.buffer import ImageBuffer
from std.memory import bitcast

struct PFMCodec:
    """Handles saving ImageBuffer (8-bit or 12/16-bit) into a 32-bit Float PFM (PF) format
    according to the Netpbm pfm(5) specification."""

    @staticmethod
    def save(var buffer: ImageBuffer, filename: String, precision: Int, grayscale: Bool) raises:
        """Saves an ImageBuffer as a 32-bit Float PFM file (Top-to-Bottom order, Little-Endian)."""
        var width = buffer.width
        var height = buffer.height

        var f = open(filename, "w")

        # PFM header according to pfm(5):
        # 1. Identifier line ('PF' for color)
        # 2. Dimensions line (width and height separated by blank)
        # 3. Scale Factor / Endianness line (negative value means little-endian raster)
        var format = "Pf" if grayscale else "PF"

        var header = (
            format + "\n"
            + String(width)
            + " "
            + String(height)
            + "\n-1.0000\n"
        )
        f.write(header)

        var max_val_f32 = Float32((1 << precision) - 1)
        var total_bytes = width * height * 3 * 4

        var byte_stream = List[UInt8]()
        byte_stream.reserve(total_bytes)

        # Helper lambda/inline function to process and append a normalized float value
        @__parameter
        def append_float_pixel(val_raw: Float32):
            var norm = val_raw / max_val_f32
            var val_f32: Float32
            if norm <= 0.04045:
                val_f32 = norm / 12.92
            else:
                val_f32 = pow((norm + 0.055) / 1.055, Float32(2.4))

            var raw_bytes = bitcast[DType.uint8, 4](val_f32)
            byte_stream.append(raw_bytes[0])
            byte_stream.append(raw_bytes[1])
            byte_stream.append(raw_bytes[2])
            byte_stream.append(raw_bytes[3])

        var stride = width * buffer.channels

        # Raster data iteration loop
        if precision <= 8:
            var data: List[UInt8]
            if grayscale:
                data = buffer.get_grayscale()
            else:
                data = buffer.get_rgb()

            var src_ptr = data.unsafe_ptr()

            for y in range(height):
                var row_start = y * stride
                for x in range(stride):
                    var val = Float32(src_ptr.unsafe_offset(row_start + x).unsafe_load())
                    append_float_pixel(val)
        else:
            var data: List[UInt16]
            if grayscale:
                data = buffer.get_grayscale_16bit()
            else:
                data = buffer.get_rgb_16bit()

            var src_ptr = data.unsafe_ptr()
            for y in range(height):
                var row_start = y * stride
                for x in range(stride):
                    var val = Float32(src_ptr.unsafe_offset(row_start + x).unsafe_load())
                    append_float_pixel(val)

        f.write_bytes(byte_stream)
        f.close()

        print("Successfully converted and saved 32-bit PFM image to", filename)