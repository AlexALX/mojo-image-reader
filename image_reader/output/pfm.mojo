from image_reader.buffer import ImageBuffer
from std.memory import bitcast

struct PFMCodec:
    """Handles saving ImageBuffer (8-bit or 12/16-bit) into a 32-bit Float PFM (PF) format
    according to the Netpbm pfm(5) specification."""

    @staticmethod
    def save(var buffer: ImageBuffer, filename: String, precision: Int) raises:
        """Saves an ImageBuffer as a 32-bit Float PFM file (Top-to-Bottom order, Little-Endian)."""
        var width = buffer.width
        var height = buffer.height

        var f = open(filename, "w")

        # PFM header according to pfm(5):
        # 1. Identifier line ('PF' for color)
        # 2. Dimensions line (width and height separated by blank)
        # 3. Scale Factor / Endianness line (negative value means little-endian raster)
        var header = (
            "PF\n"
            + String(width)
            + " "
            + String(height)
            + "\n-1.0000\n"
        )
        f.write(header)

        var max_val_f32 = Float32((1 << precision) - 1)

        var total_samples = width * height * 3
        var total_bytes = total_samples * 4

        var byte_stream = List[UInt8]()
        byte_stream.reserve(total_bytes)

        # Raster data: standard Western reading order (left to right and top to bottom)
        if precision <= 8:
            var src_ptr = buffer.data_u8.unsafe_ptr()
            for y in range(height):
                var row_start = y * width * 3
                for x in range(width * 3):
                    var val_u8 = src_ptr.unsafe_offset(row_start + x).unsafe_load()

                    var norm = Float32(val_u8) / max_val_f32
                    var val_f32: Float32
                    if norm <= 0.04045:
                        val_f32 = norm / 12.92
                    else:
                        val_f32 = pow((norm + 0.055) / 1.055, Float32(2.4))

                    # Each sample is a 32-bit floating point number (4 consecutive bytes)
                    var raw_bytes = bitcast[DType.uint8, 4](val_f32)

                    byte_stream.append(raw_bytes[0])
                    byte_stream.append(raw_bytes[1])
                    byte_stream.append(raw_bytes[2])
                    byte_stream.append(raw_bytes[3])
        else:
            var src_ptr = buffer.data_u16.unsafe_ptr()
            for y in range(height):
                var row_start = y * width * 3
                for x in range(width * 3):
                    var val_u16 = src_ptr.unsafe_offset(row_start + x).unsafe_load()

                    var norm = Float32(val_u16) / max_val_f32
                    var val_f32: Float32
                    if norm <= 0.04045:
                        val_f32 = norm / 12.92
                    else:
                        val_f32 = pow((norm + 0.055) / 1.055, Float32(2.4))

                    # Each sample is a 32-bit floating point number (4 consecutive bytes)
                    var raw_bytes = bitcast[DType.uint8, 4](val_f32)

                    byte_stream.append(raw_bytes[0])
                    byte_stream.append(raw_bytes[1])
                    byte_stream.append(raw_bytes[2])
                    byte_stream.append(raw_bytes[3])

        f.write_bytes(byte_stream)
        f.close()

        print("Successfully converted and saved 32-bit PFM image to", filename)