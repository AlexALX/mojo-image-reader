from image_reader.bmp_reader.parser import BmpParser
from image_reader.bmp_reader.decoder import BmpDecoder
from image_reader import ImageBuffer, ImageReaderTrait

struct BmpReader(ImageReaderTrait):
	var precision: Int

	def __init__(out self, precision: Int = 8):
		self.precision = precision

	def read(mut self, var bytes: List[UInt8]) raises -> Optional[ImageBuffer]:
		var parser = BmpParser(bytes^, self.precision)

		var result = parser.parse_headers()

		var decoder = BmpDecoder(parser^)
		var buffer: ImageBuffer
		if self.precision>8:
			buffer = decoder.decode_image[True]()
		else:
			buffer = decoder.decode_image[False]()

		return Optional(buffer^)