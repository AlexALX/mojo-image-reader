from image_reader.buffer import ImageBuffer

struct GifFrame:
    """Represents a single frame in a GIF animation."""
    var buffer: ImageBuffer
    var delay_ms: Int
    var disposal_method: Int

    def __init__(out self, var buffer: ImageBuffer, delay_ms: Int, disposal_method: Int):
        self.buffer = buffer^
        self.delay_ms = delay_ms
        self.disposal_method = disposal_method