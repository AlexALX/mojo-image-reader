from image_reader import ImageBuffer
from image_reader.jpg_reader import JpegReader
from image_reader.bmp_reader import BmpReader
from image_reader.png_reader import PngReader
from image_reader.gif_reader import GifReader
from std.pathlib import Path

trait ImageReaderTrait:
    def read(mut self, var bytes: List[UInt8]) raises -> Optional[ImageBuffer]:
        ...

struct ImageReader(ImageReaderTrait):
    var precision: Int
    var format: String
    var frame: Int

    def __init__(out self, precision: Int = 8, frame: Int = 0):
        self.precision = precision
        self.format = ""
        self.frame = frame

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
        elif self.format=="png":
            var reader = PngReader(self.precision)
            opt_buffer = reader.read(bytes^)
        elif self.format=="gif":
            var reader = GifReader(self.precision, self.frame)
            opt_buffer = reader.read(bytes^)
        else:
            raise Error("Unsupported format")

        return opt_buffer^

    def detect_format(self, ref bytes: List[UInt8]) -> String:
        if bytes[0] == 0xFF and bytes[1] == 0xD8:
            return "jpg"
        elif bytes[0] == 0x42 and bytes[1] == 0x4D:
            return "bmp"
        elif bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47:
            return "png"
        elif bytes[0] == 0x47 and bytes[1] == 0x49 and bytes[2] == 0x46:
            if bytes[3] == 0x38 and (bytes[4] == 0x37 or bytes[4] == 0x39) and bytes[5] == 0x61:
                return "gif"

        return ""