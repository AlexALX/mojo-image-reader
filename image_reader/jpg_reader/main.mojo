from image_reader.jpg_reader.parser import JpegParser
from image_reader.jpg_reader.decoder import JpgDecoder
from image_reader.buffer import ImageBuffer

struct JpegReader:
	var precision: Int

	def __init__(out self, precision: Int = 8):
		self.precision = precision

	def read(mut self, var bytes: List[UInt8]) -> Optional[ImageBuffer]:
		try:
			var parser = JpegParser(bytes^, self.precision)

			var result = parser.jpg_parse()

			if result:
				var decoder = JpgDecoder(parser^)
				var buffer = decoder.decode_image()

				return Optional(buffer^)
		except e:
			print("Error during JPEG parsing: ", e)
			return None

		return None