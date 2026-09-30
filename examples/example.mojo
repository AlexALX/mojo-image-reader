from image_reader import ImageReader
from std.pathlib import Path

def main() raises:
    # Initialize the reader with desired output precision (e.g., 8 or 12 bits)
    var reader = ImageReader(precision = 8)
    var opt_buffer = reader.readfile("samples/jpg/2.jpg")

    if opt_buffer:
        var buffer = opt_buffer.take()
        print("Decoded width:", buffer.width)
        print("Decoded height:", buffer.height)
        print("Decoded channels:", buffer.channels)
        print("Is 16-bit:", buffer.is_16bit)

        if buffer.is_16bit:
            var rgb = buffer.take_rgb_16bit()
            print("Data Length: ", len(rgb))
        else:
            var rgb = buffer.take_rgb()
            print("Data Length: ", len(rgb))
    else:
        print("Decoding failed.")