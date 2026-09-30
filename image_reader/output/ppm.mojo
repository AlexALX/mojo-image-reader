from image_reader.buffer import ImageBuffer

struct PPMCodec:
    """Handles saving ImageBuffer into a PPM/PGM/PAM file format."""

    @staticmethod
    def save(var buffer: ImageBuffer, filename: String, precision: Int, format: String, grayscale: Bool) raises:
        """Saves an ImageBuffer supporting both 8-bit and 12/16-bit color depths."""
        var max_val = (1 << precision) - 1

        var f = open(filename, "w")

        if format=="pam":
            var tupl_type = "RGB"
            if buffer.channels==1:
                tupl_type = "GRAYSCALE"
            elif buffer.channels==2:
                tupl_type = "GRAYSCALE_ALPHA"
            elif buffer.channels==4:
                tupl_type = "RGB_ALPHA"

            f.write("P7\n" +
                "WIDTH " + String(buffer.width) + "\n" +
                "HEIGHT " + String(buffer.height) + "\n" +
                "DEPTH " + String(buffer.channels) + "\n" +
                "MAXVAL " + String(max_val) + "\n" +
                "TUPLTYPE " + tupl_type + "\n" +
                "ENDHDR\n"
            )
        else:
            # Write standard PPM header (P5 or P6)
            var header_format = "P5" if format=="pgm" else "P6"
            f.write(
                header_format + "\n" +
                String(buffer.width) + " " + String(buffer.height) + "\n" +
                String(max_val) + "\n"
            )

        if precision <= 8:
            if format=="pam":

                if grayscale:
                    if buffer.has_alpha:
                        f.write_bytes(buffer.take_grayscale[with_alpha = True]())
                    else:
                        f.write_bytes(buffer.take_grayscale())
                else:
                    if buffer.has_alpha:
                        f.write_bytes(buffer.take_rgb[with_alpha = True]())
                    else:
                        f.write_bytes(buffer.take_rgb())

            elif format=="pgm":
                f.write_bytes(buffer.take_grayscale())
            else:
                # Write 8-bit raw pixel data directly
                if grayscale:
                    f.write_bytes(buffer.take_rgb[as_grayscale = True]())
                else:
                    f.write_bytes(buffer.take_rgb())
        else:
            # Pack 16-bit values into Big-Endian byte stream
            var data: List[UInt16]
            if format=="pam":

                if grayscale:
                    if buffer.has_alpha:
                        data = buffer.take_grayscale_16bit[with_alpha = True]()
                    else:
                        data = buffer.take_grayscale_16bit()
                else:
                    if buffer.has_alpha:
                        data = buffer.take_rgb_16bit[with_alpha = True]()
                    else:
                        data = buffer.take_rgb_16bit()

            elif format=="pgm":
                data = buffer.take_grayscale_16bit()
            else:
                if grayscale:
                    data = buffer.take_rgb_16bit[as_grayscale = True]()
                else:
                    data = buffer.take_rgb_16bit()

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
        print("Successfully saved image to", filename)