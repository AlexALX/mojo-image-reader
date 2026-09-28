from image_reader.buffer import ImageBuffer

struct PPMCodec:
    """Handles saving ImageBuffer into a PPM file format."""

    @staticmethod
    def save(var buffer: ImageBuffer, filename: String, precision: Int, grayscale: Bool) raises:
        """Saves an ImageBuffer supporting both 8-bit and 12/16-bit color depths."""
        var max_val = (1 << precision) - 1

        var f = open(filename, "w")
        # Write standard PPM header (P5 or P6)
        var format = "P5" if grayscale else "P6"
        f.write(format + "\n" + String(buffer.width) + " " + String(buffer.height) + "\n" + String(max_val) + "\n")

        if precision <= 8:
            if grayscale:
                f.write_bytes(buffer.get_grayscale())
            else:
                # Write 8-bit raw pixel data directly
                f.write_bytes(buffer.get_rgb())
        else:
            # Pack 16-bit values into Big-Endian byte stream
            var data: List[UInt16]
            if grayscale:
                data = buffer.get_grayscale_16bit()
            else:
                data = buffer.get_rgb_16bit()

            var total_len = len(data)

            var byte_stream = List[UInt8](unsafe_uninit_length=total_len * 2)

            var idx = 0
            for i in range(total_len):
                var val = data.unsafe_get(i)
                byte_stream.unsafe_set(idx, UInt8((val >> 8) & 0xFF))
                byte_stream.unsafe_set(idx+1, UInt8(val & 0xFF))
                idx += 2

            f.write_bytes(byte_stream)

        f.close()
        print("Successfully saved color image to", filename)