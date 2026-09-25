from image_reader.buffer import ImageBuffer

struct PPMCodec:
    """Handles saving ImageBuffer into a PPM file format."""

    @staticmethod
    def save(var buffer: ImageBuffer, filename: String, precision: Int) raises:
        """Saves an ImageBuffer supporting both 8-bit and 12/16-bit color depths."""
        var max_val = (1 << precision) - 1

        var f = open(filename, "w")
        # Write standard PPM header (P6)
        f.write("P6\n" + String(buffer.width) + " " + String(buffer.height) + "\n" + String(max_val) + "\n")

        if precision <= 8:
            # Write 8-bit raw pixel data directly
            f.write_bytes(buffer.data_u8)
        else:
            # Pack 16-bit values into Big-Endian byte stream
            var total_len = len(buffer.data_u16)
            var byte_stream = List[UInt8]()
            byte_stream.reserve(total_len * 2)

            for i in range(total_len):
                var val = buffer.data_u16[i]
                byte_stream.append(UInt8((val >> 8) & 0xFF))
                byte_stream.append(UInt8(val & 0xFF))

            f.write_bytes(byte_stream)

        f.close()
        print("Successfully saved color image to", filename)