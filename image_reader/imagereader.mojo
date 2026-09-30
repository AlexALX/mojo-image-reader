from image_reader import ImageBuffer
from image_reader.jpg_reader import JpegReader
from image_reader.bmp_reader import BmpReader
from std.pathlib import Path

trait ImageReaderTrait:
    def read(mut self, var bytes: List[UInt8]) raises -> Optional[ImageBuffer]:
        ...

struct ImageReader(ImageReaderTrait):
    var precision: Int
    var format: String

    def __init__(out self, precision: Int = 8):
        self.precision = precision
        self.format = ""

    def readfile(mut self, filepath: String) raises -> Optional[ImageBuffer]:
        var path = Path(filepath)

        if not path.exists():
            raise Error("Error: File not found - ", filepath)

        return self.read(path.read_bytes())

    def read(mut self, var bytes: List[UInt8]) raises -> Optional[ImageBuffer]:
        self.format = self.detect_format(bytes)
        var opt_buffer: Optional[ImageBuffer]
        if self.format=="jpg":
            var reader = JpegReader(self.precision)
            opt_buffer = reader.read(bytes^)
        elif self.format=="bmp":
            var reader = BmpReader(self.precision)
            opt_buffer = reader.read(bytes^)
        else:
            raise Error("Unsupported format")

        return opt_buffer^

    def detect_format(self, ref bytes: List[UInt8]) -> String:
        if bytes[0] == 0xFF and bytes[1] == 0xD8:
            return "jpg"
        if bytes[0] == 0x42 and bytes[1] == 0x4D:
            return "bmp"

        return ""