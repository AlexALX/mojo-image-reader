from image_reader.png_reader.decoder import PngDecoder
from image_reader import ImageBuffer, ImageReaderTrait

struct PngReader(ImageReaderTrait):
	var precision: Int

	def __init__(out self, precision: Int = 8):
		self.precision = precision

	def read(mut self, var bytes: List[UInt8]) raises -> Optional[ImageBuffer]:
		var parser = PngDecoder(bytes^, self.precision)
		parser.parse()

		var buffer = parser.decode_image()
		return Optional(buffer^)