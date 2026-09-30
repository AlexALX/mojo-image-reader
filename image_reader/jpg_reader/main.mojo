from image_reader.jpg_reader.parser import JpegParser
from image_reader.jpg_reader.decoder import JpgDecoder
from image_reader import ImageBuffer, ImageReaderTrait

struct JpegReader(ImageReaderTrait):
	var precision: Int

	def __init__(out self, precision: Int = 8):
		self.precision = precision

	def read(mut self, var bytes: List[UInt8]) raises -> Optional[ImageBuffer]:
		var parser = JpegParser(bytes^, self.precision)

		var result = parser.jpg_parse()

		if result:
			var decoder = JpgDecoder(parser^)
			var buffer = decoder.decode_image()

			return Optional(buffer^)

		return None