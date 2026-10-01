from image_reader import ImageBuffer, ImageReaderTrait
from image_reader.gif_reader import GifParser, GifDecoder, GifFrame

struct GifReader(ImageReaderTrait):
	var precision: Int
	var frame: Int

	def __init__(out self, precision: Int = 8, frame: Int = 0):
		self.precision = precision
		self.frame = frame

	def read(mut self, var bytes: List[UInt8]) raises -> Optional[ImageBuffer]:
		var parser = GifParser(bytes^, self.precision)

		var result = parser.parse_header()

		var decoder = GifDecoder(parser^)
		var frames: List[GifFrame]

		if self.frame==0:
			frames = decoder.decode_frames[True]()
		else:
			frames = decoder.decode_frames[False]()

		if len(frames)<self.frame:
			raise Error("Invalid frame, frames in this file: ", len(frames), "\nFrame index start from zero.")

		var frame = frames.pop(self.frame)
		var buffer = frame.buffer^
		frame.buffer = ImageBuffer(0,0,0)

		return Optional(buffer^)