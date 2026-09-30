struct ImageBuffer:
    var data_u8: List[UInt8]
    var data_u16: List[UInt16]
    var is_16bit: Bool
    var grayscale: Bool
    var has_alpha: Bool
    var width: Int
    var height: Int
    var channels: Int
    var bit_depth: Int

    def __init__(out self, width: Int, height: Int, channels: Int = 3, bit_depth: Int = 8):
        self.width = width
        self.height = height
        self.channels = channels
        self.bit_depth = bit_depth
        self.is_16bit = (bit_depth > 8)
        self.grayscale = (channels == 1 or channels == 2)
        self.has_alpha = (channels == 4 or channels == 2)

        self.data_u8 = List[UInt8]()
        self.data_u16 = List[UInt16]()

        if self.is_16bit:
            self.data_u16.reserve(width * height * channels)
        else:
            self.data_u8.reserve(width * height * channels)

    @always_inline
    def _process_rgb[type: DType, with_alpha: Bool = False, as_grayscale: Bool = False](
        self,
        ref src_data: List[Scalar[type]]
    ) -> List[Scalar[type]]:
        var channels_out = 4 if with_alpha else 3

        var max_alpha = Scalar[type]((1 << self.bit_depth) - 1)
        var max_alpha_int = Int32(max_alpha)

        var byte_stream = List[Scalar[type]](unsafe_uninit_length=self.width * self.height * channels_out)
        var src_stride = self.channels
        var dest_idx = 0

        var has_alpha_now = self.has_alpha and not with_alpha
        var a_channel_idx = self.channels-1

        for src_idx in range(0, len(src_data), src_stride):
            var r: Scalar[type]
            var g: Scalar[type]
            var b: Scalar[type]

            if self.grayscale:
                var value = src_data.unsafe_get(src_idx)

                if has_alpha_now:
                    var a_idx = src_idx + a_channel_idx
                    var alpha = Int32(src_data.unsafe_get(a_idx))
                    value = ((Int32(value) * alpha) // max_alpha_int).cast[type]()

                r = g = b = value
            else:
                r = src_data.unsafe_get(src_idx)
                g = src_data.unsafe_get(src_idx + 1)
                b = src_data.unsafe_get(src_idx + 2)

                var alpha: Int32 = 0
                if has_alpha_now:
                    var a_idx = src_idx + a_channel_idx
                    alpha = Int32(src_data.unsafe_get(a_idx))

                if as_grayscale:
                    var gray_value = (Int32(r) * 218 + Int32(g) * 732 + Int32(b) * 74) >> 10

                    if has_alpha_now:
                        gray_value = (gray_value * alpha) // max_alpha_int

                    r = g = b = gray_value.cast[type]()
                else:
                    if has_alpha_now:
                        r = ((Int32(r) * alpha) // max_alpha_int).cast[type]()
                        g = ((Int32(g) * alpha) // max_alpha_int).cast[type]()
                        b = ((Int32(b) * alpha) // max_alpha_int).cast[type]()

            byte_stream.unsafe_set(dest_idx, r)
            byte_stream.unsafe_set(dest_idx + 1, g)
            byte_stream.unsafe_set(dest_idx + 2, b)
            dest_idx += 3

            if with_alpha:
                if self.has_alpha:
                    var a_idx = src_idx + a_channel_idx
                    byte_stream.unsafe_set(dest_idx, src_data.unsafe_get(a_idx))
                else:
                    byte_stream.unsafe_set(dest_idx, max_alpha)
                dest_idx += 1

        return byte_stream^

    def _process_grayscale[type: DType, with_alpha: Bool = False, take: Bool = False](
        self,
        ref src_data: List[Scalar[type]]
    ) -> List[Scalar[type]]:
        var channels_out = 2 if with_alpha else 1

        var max_alpha = Scalar[type]((1 << self.bit_depth) - 1)
        var max_alpha_int = Int32(max_alpha)

        var byte_stream = List[Scalar[type]](unsafe_uninit_length=self.width * self.height * channels_out)
        var src_stride = self.channels
        var dest_idx = 0

        var has_alpha_now = self.has_alpha and not with_alpha
        var a_channel_idx = self.channels-1

        for src_idx in range(0, len(src_data), src_stride):
            var gray_value: Scalar[type]

            if self.grayscale:
                gray_value = src_data.unsafe_get(src_idx)

                if has_alpha_now:
                    var a_idx = src_idx + a_channel_idx
                    var alpha = Int32(src_data.unsafe_get(a_idx))
                    gray_value = ((Int32(gray_value) * alpha) // max_alpha_int).cast[type]()
            else:
                var r = Int32(src_data.unsafe_get(src_idx))
                var g = Int32(src_data.unsafe_get(src_idx + 1))
                var b = Int32(src_data.unsafe_get(src_idx + 2))
                var value = (r * 218 + g * 732 + b * 74) >> 10

                if has_alpha_now:
                    var a_idx = src_idx + a_channel_idx
                    var alpha = Int32(src_data.unsafe_get(a_idx))
                    gray_value = ((value * alpha) // max_alpha_int).cast[type]()
                else:
                    gray_value = value.cast[type]()

            byte_stream.unsafe_set(dest_idx, gray_value)
            dest_idx += 1

            if with_alpha:
                if self.has_alpha:
                    var a_idx = src_idx + a_channel_idx
                    byte_stream.unsafe_set(dest_idx, src_data.unsafe_get(a_idx))
                else:
                    byte_stream.unsafe_set(dest_idx, max_alpha)
                dest_idx += 1

        return byte_stream^

    def get_rgb[with_alpha: Bool = False, as_grayscale: Bool = False](self) -> List[UInt8]:
        var channels_out = 4 if with_alpha else 3
        if not self.grayscale and self.channels == channels_out and not as_grayscale:
            return self.data_u8.copy()

        return self._process_rgb[DType.uint8, with_alpha, as_grayscale](self.data_u8)

    def take_rgb[with_alpha: Bool = False, as_grayscale: Bool = False](mut self) -> List[UInt8]:
        var channels_out = 4 if with_alpha else 3
        if not self.grayscale and self.channels == channels_out and not as_grayscale:
            var result = List[UInt8]()
            swap(self.data_u8, result)
            return result^

        var src = self.data_u8^
        self.data_u8 = List[UInt8]()
        return self._process_rgb[DType.uint8, with_alpha, as_grayscale](src)

    def get_rgb_16bit[with_alpha: Bool = False, as_grayscale: Bool = False](self) -> List[UInt16]:
        var channels_out = 4 if with_alpha else 3
        if not self.grayscale and self.channels == channels_out and not as_grayscale:
            return self.data_u16.copy()

        return self._process_rgb[DType.uint16, with_alpha, as_grayscale](self.data_u16)

    def take_rgb_16bit[with_alpha: Bool = False, as_grayscale: Bool = False](mut self) -> List[UInt16]:
        var channels_out = 4 if with_alpha else 3
        if not self.grayscale and self.channels == channels_out and not as_grayscale:
            var result = List[UInt16]()
            swap(self.data_u16, result)
            return result^

        var src = self.data_u16^
        self.data_u16 = List[UInt16]()
        return self._process_rgb[DType.uint16, with_alpha, as_grayscale](src)

    def get_grayscale[with_alpha: Bool = False](self) -> List[UInt8]:
        var channels_out = 2 if with_alpha else 1
        if self.grayscale and self.channels == channels_out:
            return self.data_u8.copy()

        return self._process_grayscale[DType.uint8, with_alpha](self.data_u8)

    def take_grayscale[with_alpha: Bool = False](mut self) -> List[UInt8]:
        var channels_out = 2 if with_alpha else 1
        if self.grayscale and self.channels == channels_out:
            var result = List[UInt8]()
            swap(self.data_u8, result)
            return result^

        var src = self.data_u8^
        self.data_u8 = List[UInt8]()
        return self._process_grayscale[DType.uint8, with_alpha](src)

    def get_grayscale_16bit[with_alpha: Bool = False](self) -> List[UInt16]:
        var channels_out = 2 if with_alpha else 1
        if self.grayscale and self.channels == channels_out:
            return self.data_u16.copy()

        return self._process_grayscale[DType.uint16, with_alpha](self.data_u16)

    def take_grayscale_16bit[with_alpha: Bool = False](mut self) -> List[UInt16]:
        var channels_out = 2 if with_alpha else 1
        if self.grayscale and self.channels == channels_out:
            var result = List[UInt16]()
            swap(self.data_u16, result)
            return result^

        var src = self.data_u16^
        self.data_u16 = List[UInt16]()
        return self._process_grayscale[DType.uint16, with_alpha](src)
