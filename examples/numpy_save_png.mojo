from image_reader.jpg_reader import JpegReader
from image_reader.output.numpy_bridge import NumPyBridge
from std.pathlib import Path
from std.python import Python

def main() raises:
    var input_file = "samples/jpg/2.jpg"
    var output_file = "output_test.png"

    print("Reading JPEG file:", input_file)
    var path = Path(input_file)
    if not path.exists():
        print("Error: File not found:", input_file)
        return

    var bytes = path.read_bytes()
    var reader = JpegReader()
    var opt_buffer = reader.read(bytes^)

    if opt_buffer:
        print("JPEG decoded successfully! Converting to NumPy & saving as PNG...")
        var buffer = opt_buffer.take()

        var np_arr = NumPyBridge.to_ndarray(buffer)

        var Image = Python.import_module("PIL.Image")
        var img = Image.fromarray(np_arr)
        img.save(output_file, "PNG")

        print("Done! Saved to:", output_file)
    else:
        print("Failed to decode JPEG.")