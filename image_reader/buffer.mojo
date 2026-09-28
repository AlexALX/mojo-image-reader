struct ImageBuffer:
    var data_u8: List[UInt8]
    var data_u16: List[UInt16]
    var is_16bit: Bool
    var grayscale: Bool
    var has_alpha: Bool
    var width: Int
    var height: Int
    var channels: Int

    def __init__(out self, width: Int, height: Int, channels: Int = 3, bit_depth: Int = 8):
        self.width = width
        self.height = height
        self.channels = channels
        self.is_16bit = (bit_depth > 8)
        self.grayscale = (channels == 1)
        self.has_alpha = (channels == 4)

        self.data_u8 = List[UInt8]()
        self.data_u16 = List[UInt16]()

        if self.is_16bit:
            self.data_u16.reserve(width * height * channels)
        else:
            self.data_u8.reserve(width * height * channels)

    def get_rgb(mut self) -> List[UInt8]:
        if self.grayscale:
            var byte_stream = List[UInt8](unsafe_uninit_length=self.width * self.height * 3)
            var idx = 0
            for i in range(len(self.data_u8)):
                var val = self.data_u8.unsafe_get(i)
                for _ in range(3):
                    byte_stream.unsafe_set(idx, val)
                    idx += 1

            return byte_stream^

        var res = self.data_u8^
        self.data_u8 = List[UInt8]()

        return res^

    def get_rgb_16bit(mut self) -> List[UInt16]:
        if self.grayscale:
            var byte_stream = List[UInt16](unsafe_uninit_length=self.width * self.height * 3)
            var idx = 0
            for i in range(len(self.data_u16)):
                var val = self.data_u16.unsafe_get(i)
                for _ in range(3):
                    byte_stream.unsafe_set(idx, val)
                    idx += 1

            return byte_stream^

        var res = self.data_u16^
        self.data_u16 = List[UInt16]()

        return res^

    def get_grayscale(mut self) -> List[UInt8]:
        if self.grayscale:
            var res = self.data_u8^
            self.data_u8 = List[UInt8]()
            return res^

        var total_pixels = self.width * self.height
        var gray_stream = List[UInt8](unsafe_uninit_length=total_pixels)
        var src_idx = 0

        for i in range(total_pixels):
            var r = Int(self.data_u8.unsafe_get(src_idx))
            var g = Int(self.data_u8.unsafe_get(src_idx + 1))
            var b = Int(self.data_u8.unsafe_get(src_idx + 2))

            # Rec. 709
            var gray = UInt8((r * 218 + g * 732 + b * 74) >> 10)
            gray_stream.unsafe_set(i, gray)

            src_idx += self.channels

        return gray_stream^

    def get_grayscale_16bit(mut self) -> List[UInt16]:
            if self.grayscale:
                var res = self.data_u16^
                self.data_u16 = List[UInt16]()
                return res^

            var total_pixels = self.width * self.height
            var gray_stream = List[UInt16](unsafe_uninit_length=total_pixels)
            var src_idx = 0

            for i in range(total_pixels):
                var r = Int(self.data_u16.unsafe_get(src_idx))
                var g = Int(self.data_u16.unsafe_get(src_idx + 1))
                var b = Int(self.data_u16.unsafe_get(src_idx + 2))

                # Rec. 709
                var gray = UInt16((r * 218 + g * 732 + b * 74) >> 10)
                gray_stream.unsafe_set(i, gray)

                src_idx += self.channels

            return gray_stream^