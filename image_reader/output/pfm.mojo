from image_reader.buffer import ImageBuffer
from std.memory import bitcast

struct PFMCodec:
    """Handles saving ImageBuffer (8-bit or 12/16-bit) into a 32-bit Float PFM (PF) format."""

    @staticmethod
    def save(var buffer: ImageBuffer, filename: String, precision: Int) raises:
        """Saves an ImageBuffer as a 32-bit Float PFM file (Bottom-to-Top) by normalizing integer data."""
        var width = buffer.width
        var height = buffer.height

        var f = open(filename, "w")

		# Write standard PFM header
        var header = (
            "PF\n"
            + String(width)
            + " "
            + String(height)
            + "\n-1.000000\n"
        )
        f.write(header)

        var max_val_f32 = Float32((1 << precision) - 1)

        var total_samples = width * height * 3
        var total_bytes = total_samples * 4

        var byte_stream = List[UInt8]()
        byte_stream.reserve(total_bytes)

        var dst_ptr = byte_stream.unsafe_ptr()
        var dst_idx = 0

        var src_ptr  = buffer.data_u16.unsafe_ptr()

        for y in range(height - 1, -1, -1):
            var row_start = y * width * 3
            for x in range(width * 3):
                var val_u16 = src_ptr.unsafe_offset(row_start + x).unsafe_load()
                var val_f32 = Float32(val_u16) / max_val_f32

                var raw_bytes = bitcast[DType.uint8, 4](val_f32)

                dst_ptr.unsafe_offset(dst_idx).unsafe_store(raw_bytes[0])
                dst_ptr.unsafe_offset(dst_idx + 1).unsafe_store(raw_bytes[1])
                dst_ptr.unsafe_offset(dst_idx + 2).unsafe_store(raw_bytes[2])
                dst_ptr.unsafe_offset(dst_idx + 3).unsafe_store(raw_bytes[3])
                dst_idx += 4

        f.write_bytes(byte_stream)
        f.close()

        print("Successfully converted and saved 32-bit PFM image to", filename)