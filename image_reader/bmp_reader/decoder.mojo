from image_reader.buffer import ImageBuffer
from image_reader.bmp_reader.parser import BmpParser

struct BmpDecoder:
    var parser: BmpParser
    var bit_shift_scale: UInt16

    def __init__(out self, var parser: BmpParser):
        self.parser = parser^
        self.bit_shift_scale = 0

    @always_inline
    def _decode_rle[is_16bit: Bool](
        self, x: Int, y: Int, channels: Int,
        r: UInt8, g: UInt8, b: UInt8,
        mut buffer: ImageBuffer,
    ):
        if x < self.parser.width and y >= 0 and y < self.parser.height:
            var po = (y * self.parser.width * channels) + (x * channels)
            if is_16bit:
                var r_scaled = UInt16(r) << self.bit_shift_scale
                var g_scaled = UInt16(g) << self.bit_shift_scale
                var b_scaled = UInt16(b) << self.bit_shift_scale
                if channels == 1:
                    buffer.data_u16.unsafe_set(po, r_scaled)
                elif channels == 3:
                    buffer.data_u16.unsafe_set(po, r_scaled)
                    buffer.data_u16.unsafe_set(po + 1, g_scaled)
                    buffer.data_u16.unsafe_set(po + 2, b_scaled)
            else:
                if channels == 1:
                    buffer.data_u8.unsafe_set(po, r)
                elif channels == 3:
                    buffer.data_u8.unsafe_set(po, r)
                    buffer.data_u8.unsafe_set(po + 1, g)
                    buffer.data_u8.unsafe_set(po + 2, b)

    @always_inline
    def _save_pixel[is_16bit: Bool](self, mut buffer: ImageBuffer, offset: Int, pixel: UInt8):
        if is_16bit:
            var scaled = UInt16(pixel) << self.bit_shift_scale
            buffer.data_u16.unsafe_set(offset, scaled)
        else:
            buffer.data_u8.unsafe_set(offset, pixel)

    def decode_image[is_16bit: Bool = False](mut self) raises -> ImageBuffer:
        # Seek directly to pixel data offset
        self.parser.reader.seek(self.parser.pixel_offset)

        var width = self.parser.width
        var height = self.parser.height
        var precision = self.parser.precision

        # Select target channel depth
        var channels: Int
        if self.parser.is_grayscale and self.parser.has_alpha:
            channels = 2
        elif self.parser.is_grayscale and not self.parser.has_alpha:
            channels = 1
        elif not self.parser.is_grayscale and self.parser.has_alpha:
            channels = 4
        else:
            channels = 3

        var buffer = ImageBuffer(width, height, channels, self.parser.precision)
        self.bit_shift_scale = UInt16(precision - 8)

        var bpp = self.parser.bits_per_pixel
        var comp = self.parser.compression

        # RLE8 and RLE4
        if (bpp == 8 and comp == 1) or (bpp == 4 and comp == 2):
            var x = 0
            var y = 0 if self.parser.is_top_down else (height - 1)
            var finished = False

            while not finished:
                var count = self.parser.reader.u8()
                var command = self.parser.reader.u8()

                if count == 0:
                    if command == 0:
                        # End of Line
                        x = 0
                        if self.parser.is_top_down: y += 1
                        else: y -= 1
                    elif command == 1:
                        # End of File
                        finished = True
                    elif command == 2:
                        # Delta shift
                        var dx = self.parser.reader.u8()
                        var dy = self.parser.reader.u8()
                        x += dx
                        if self.parser.is_top_down: y += dy
                        else: y -= dy
                    else:
                        # Absolute mode
                        var num_pixels = command
                        var bytes_read = 0
                        var current_absolute_byte = 0

                        for i in range(num_pixels):
                            var index: Int
                            if comp == 1:
                                # RLE8 Absolute Mode
                                index = self.parser.reader.u8()
                                bytes_read += 1
                            else:
                                # RLE4 Absolute Mode
                                if (i & 1) == 0:
                                    current_absolute_byte = self.parser.reader.u8()
                                    bytes_read += 1
                                    index = (current_absolute_byte >> 4) & 0x0F
                                else:
                                    index = current_absolute_byte & 0x0F

                            var pal_idx = index * 3
                            var r = self.parser.palette[pal_idx]
                            var g = self.parser.palette[pal_idx + 1]
                            var b = self.parser.palette[pal_idx + 2]

                            self._decode_rle[is_16bit](
                                x, y, channels,
                                r, g, b,
                                buffer
                            )
                            x += 1

                        # Word alignment check for Absolute Mode stream
                        if (bytes_read & 1) != 0:
                            _ = self.parser.reader.u8()
                else:
                    # Encoded Mode
                    if comp == 1:
                        # RLE8 Encoded Mode
                        var pal_idx = command * 3
                        var r = self.parser.palette[pal_idx]
                        var g = self.parser.palette[pal_idx + 1]
                        var b = self.parser.palette[pal_idx + 2]

                        for _ in range(count):
                            self._decode_rle[is_16bit](
                                x, y, channels,
                                r, g, b,
                                buffer
                            )
                            x += 1
                    else:
                        # RLE4 Encoded Mode
                        for i in range(count):
                            var index: Int
                            if (i & 1) == 0:
                                index = (command >> 4) & 0x0F
                            else:
                                index = command & 0x0F

                            var pal_idx = index * 3
                            var r = self.parser.palette[pal_idx]
                            var g = self.parser.palette[pal_idx + 1]
                            var b = self.parser.palette[pal_idx + 2]

                            self._decode_rle[is_16bit](
                                x, y, channels,
                                r, g, b,
                                buffer
                            )
                            x += 1

            if is_16bit:
                buffer.data_u16.resize(unsafe_uninit_length=width * height * channels)
            else:
                buffer.data_u8.resize(unsafe_uninit_length=width * height * channels)
            return buffer^

        # Main row decoding loop
        for y in range(height):
            var draw_y = y if self.parser.is_top_down else (height - 1 - y)
            var row_offset = draw_y * width * channels
            var pixel_offset = 0

            var current_byte: UInt8 = 0

            for x in range(width):
                var r: UInt8
                var g: UInt8
                var b: UInt8
                var a: UInt8 = 255

                if bpp == 24:
                    b = self.parser.reader.u8_uint()
                    g = self.parser.reader.u8_uint()
                    r = self.parser.reader.u8_uint()

                elif bpp == 32:
                    if comp == 0:
                        b = self.parser.reader.u8_uint()
                        g = self.parser.reader.u8_uint()
                        r = self.parser.reader.u8_uint()
                        _ = self.parser.reader.u8_uint()
                    else:
                        var val = self.parser.reader.u32_le()
                        r = self.parser.r_mask_info.extract_u8(val)
                        g = self.parser.g_mask_info.extract_u8(val)
                        b = self.parser.b_mask_info.extract_u8(val)
                        if self.parser.has_alpha:
                            a = self.parser.a_mask_info.extract_u8(val)

                elif bpp == 16:
                    var val = self.parser.reader.u16_le()
                    r = self.parser.r_mask_info.extract_u8(val)
                    g = self.parser.g_mask_info.extract_u8(val)
                    b = self.parser.b_mask_info.extract_u8(val)
                    if self.parser.has_alpha:
                        a = self.parser.a_mask_info.extract_u8(val)

                elif bpp == 8:
                    var index = self.parser.reader.u8()
                    var pal_idx = index * 3
                    r = self.parser.palette[pal_idx]
                    g = self.parser.palette[pal_idx + 1]
                    b = self.parser.palette[pal_idx + 2]

                elif bpp == 4:
                    if (x & 1) == 0:
                        current_byte = self.parser.reader.u8_uint()
                        var index = Int((current_byte >> 4) & UInt8(0x0F))
                        var pal_idx = index * 3
                        r = self.parser.palette[pal_idx]
                        g = self.parser.palette[pal_idx + 1]
                        b = self.parser.palette[pal_idx + 2]
                    else:
                        var index = Int(current_byte & UInt8(0x0F))
                        var pal_idx = index * 3
                        r = self.parser.palette[pal_idx]
                        g = self.parser.palette[pal_idx + 1]
                        b = self.parser.palette[pal_idx + 2]

                elif bpp == 1:
                    var bit_shift = 7 - (x & 7)
                    if (x & 7) == 0:
                        current_byte = self.parser.reader.u8_uint()
                    var index = Int(current_byte) >> bit_shift & 1
                    var pal_idx = index * 3
                    r = self.parser.palette[pal_idx]
                    g = self.parser.palette[pal_idx + 1]
                    b = self.parser.palette[pal_idx + 2]

                else:
                    raise Error("Unsupported BMP bit depth or compression")

                # Write pixel bytes based on image configuration
                var po = row_offset + pixel_offset
                if channels == 1:
                    self._save_pixel[is_16bit](buffer, po, r)
                    pixel_offset += 1
                elif channels == 2:
                    self._save_pixel[is_16bit](buffer, po, r)
                    self._save_pixel[is_16bit](buffer, po + 1, a)
                    pixel_offset += 2
                elif channels == 3:
                    self._save_pixel[is_16bit](buffer, po, r)
                    self._save_pixel[is_16bit](buffer, po + 1, g)
                    self._save_pixel[is_16bit](buffer, po + 2, b)
                    pixel_offset += 3
                elif channels == 4:
                    self._save_pixel[is_16bit](buffer, po, r)
                    self._save_pixel[is_16bit](buffer, po + 1, g)
                    self._save_pixel[is_16bit](buffer, po + 2, b)
                    self._save_pixel[is_16bit](buffer, po + 3, a)
                    pixel_offset += 4

            # Skip row padding bytes
            if comp != 1 and comp != 2 and self.parser.padding > 0:
                self.parser.reader.skip(self.parser.padding)

        if is_16bit:
            buffer.data_u16.resize(unsafe_uninit_length=width * height * channels)
        else:
            buffer.data_u8.resize(unsafe_uninit_length=width * height * channels)
        return buffer^