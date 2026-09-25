struct ImageBuffer:
    var data_u8: List[UInt8]
    var data_u16: List[UInt16]
    var is_16bit: Bool
    var width: Int
    var height: Int
    var channels: Int

    def __init__(out self, width: Int, height: Int, channels: Int = 3, bit_depth: Int = 8):
        self.width = width
        self.height = height
        self.channels = channels
        self.is_16bit = (bit_depth > 8)

        self.data_u8 = List[UInt8]()
        self.data_u16 = List[UInt16]()

        if self.is_16bit:
            self.data_u16.reserve(width * height * channels)
        else:
            self.data_u8.reserve(width * height * channels)