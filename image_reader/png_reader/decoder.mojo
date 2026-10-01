from image_reader import BinaryReader, ImageBuffer
from image_reader.png_reader.filter import unfilter_scanlines
from image_reader.deflate import Inflater
from std.memory import unsafe_memcpy

struct PngDecoder:
    var reader: BinaryReader
    var width: Int
    var height: Int
    var bit_depth: Int
    var color_type: Int
    var channels: Int
    var bpp: Int
    var precision: Int
    var interlace_method: Int
    var compression_method: Int
    var filter_method: Int

    var palette: List[UInt8]
    var idat_data: List[UInt8]

    def __init__(out self: Self, var bytes: List[UInt8], precision: Int = 8):
        self.reader = BinaryReader(bytes^)
        self.width = 0
        self.height = 0
        self.bit_depth = 0
        self.color_type = 0
        self.channels = 0
        self.bpp = 0
        self.precision = precision
        self.interlace_method = 0
        self.compression_method = 0
        self.filter_method = 0
        self.palette = List[UInt8]()
        self.idat_data = List[UInt8]()

    def verify_signature(mut self) raises:
        """Verifies standard PNG magic bytes at the beginning of the stream."""
        if self.reader.length < 8:
            raise Error("File size is too small to contain valid PNG header")

        # PNG Signature: 0x89 'P' 'N' 'G' \r \n \x1a \n
        if self.reader.u32_be() != 0x89504E47 or self.reader.u32_be() != 0x0D0A1A0A:
            raise Error("Invalid PNG signature magic bytes")

    def parse(mut self) raises:
        """Parses standard PNG chunks sequentially via BinaryReader."""

        self.verify_signature()

        while not self.reader.is_eof():
            var length = self.reader.u32_be()
            var chunk_type = self.reader.u32_be()
            var chunk_data_pos = self.reader.tell()

            # 0x49484452 -> "IHDR"
            if chunk_type == 0x49484452:
                self.width = self.reader.u32_be()
                self.height = self.reader.u32_be()
                self.bit_depth = self.reader.u8()
                self.color_type = self.reader.u8()

                # Compression, filter, and interlace methods
                self.compression_method = self.reader.u8()
                self.filter_method = self.reader.u8()
                self.interlace_method = Int(self.reader.u8())

                if self.interlace_method != 0 and self.interlace_method != 1:
                    raise Error("Unsupported PNG interlace method")

                # Calculate channel layout
                if self.color_type == 0:    self.channels = 1 # Grayscale
                elif self.color_type == 2:  self.channels = 3 # RGB
                elif self.color_type == 3:  self.channels = 1 # Palette Indexed
                elif self.color_type == 4:  self.channels = 2 # Grayscale + Alpha
                elif self.color_type == 6:  self.channels = 4 # RGBA

                var bytes_per_channel = 1 if self.bit_depth <= 8 else 2
                self.bpp = self.channels * bytes_per_channel

            # 0x504C5445 -> "PLTE"
            elif chunk_type == 0x504C5445:
                self.palette.reserve(length)
                for _ in range(length):
                    self.palette.append(self.reader.u8_uint())

            # 0x49444154 -> "IDAT"
            elif chunk_type == 0x49444154:
                var old_len = len(self.idat_data)
                self.idat_data.resize(unsafe_uninit_length=old_len + length)

                var src_ptr = self.reader.bytes.unsafe_ptr().unsafe_offset(chunk_data_pos)
                var dst_ptr = self.idat_data.unsafe_ptr().unsafe_offset(old_len)
                unsafe_memcpy(dest=dst_ptr, src=src_ptr, count=length)

            # 0x49454E44 -> "IEND"
            elif chunk_type == 0x49454E44:
                self.reader.seek(chunk_data_pos + length + 4)
                break

            # Skip unhandled chunk data and 4-byte CRC
            self.reader.seek(chunk_data_pos + length + 4)

    def decode_image(mut self) raises -> ImageBuffer:
        """Main entry point to parse PNG and return standard ImageBuffer."""

        if len(self.idat_data) == 0:
            raise Error("No IDAT chunks found in PNG stream")

        # Adam7 pass grid parameters
        var START_X: List[Int] = [0, 4, 0, 2, 0, 1, 0]
        var START_Y: List[Int] = [0, 0, 4, 0, 2, 0, 1]
        var STEP_X: List[Int] = [8, 8, 4, 4, 2, 2, 1]
        var STEP_Y: List[Int] = [8, 8, 8, 4, 4, 2, 2]

        # 1. Calculate exact expected uncompressed length
        var expected_raw_size = 0
        if self.interlace_method == 0:
            expected_raw_size = self.height * (1 + (self.width * self.bpp))
        else:
            for p in range(7):
                var pw = 0 if self.width <= START_X[p] else (self.width - START_X[p] + STEP_X[p] - 1) // STEP_X[p]
                var ph = 0 if self.height <= START_Y[p] else (self.height - START_Y[p] + STEP_Y[p] - 1) // STEP_Y[p]
                if pw > 0 and ph > 0:
                    expected_raw_size += ph * (1 + pw * self.bpp)

        # 2. Decompress zlib stream
        var idat_data = self.idat_data^
        self.idat_data = List[UInt8]()

        var inflater = Inflater()
        var decompressed = inflater.decompress_zlib(
            idat_data^,
            expected_raw_size
        )

        # 3. Unfilter scanlines and assemble raw byte array
        var unfiltered: List[UInt8]

        if self.interlace_method == 0:
            unfiltered = unfilter_scanlines(decompressed, self.width, self.height, self.bpp)
        else:
            unfiltered = List[UInt8](unsafe_uninit_length=self.height * self.width * self.bpp)
            var full_dst_p = unfiltered.unsafe_ptr()
            var decomp_p = decompressed.unsafe_ptr()
            var decomp_offset = 0

            for p in range(7):
                var start_x = START_X[p]
                var start_y = START_Y[p]
                var step_x = STEP_X[p]
                var step_y = STEP_Y[p]

                var pass_w = 0 if self.width <= start_x else (self.width - start_x + step_x - 1) // step_x
                var pass_h = 0 if self.height <= start_y else (self.height - start_y + step_y - 1) // step_y

                if pass_w == 0 or pass_h == 0:
                    continue

                var pass_raw_bytes = pass_h * (1 + pass_w * self.bpp)

                # Extract raw data for current pass
                var pass_compressed = List[UInt8](unsafe_uninit_length=pass_raw_bytes)
                unsafe_memcpy(
                    dest=pass_compressed.unsafe_ptr(),
                    src=decomp_p.unsafe_offset(decomp_offset),
                    count=pass_raw_bytes
                )
                decomp_offset += pass_raw_bytes

                # Unfilter sub-image for current pass
                var pass_unfiltered = unfilter_scanlines(pass_compressed, pass_w, pass_h, self.bpp)
                var pass_src_p = pass_unfiltered.unsafe_ptr()

                # Interleave pass pixels into full destination image
                for r in range(pass_h):
                    var out_y = start_y + r * step_y
                    for c in range(pass_w):
                        var out_x = start_x + c * step_x

                        var src_off = (r * pass_w + c) * self.bpp
                        var dst_off = (out_y * self.width + out_x) * self.bpp

                        unsafe_memcpy(
                            dest=full_dst_p.unsafe_offset(dst_off),
                            src=pass_src_p.unsafe_offset(src_off),
                            count=self.bpp
                        )

        # 4. Construct output ImageBuffer (palette / 16-bit / precision scaling)
        var out_channels = 3 if self.color_type == 3 else self.channels

        var img_buffer = ImageBuffer(
            width=self.width,
            height=self.height,
            channels=out_channels,
            bit_depth=self.precision
        )

        var is_16bit = self.precision > 8
        var bit_shift_scale = UInt16(self.precision - 8) if is_16bit else UInt16(0)
        var dest_idx = 0

        if is_16bit:
            img_buffer.data_u16.resize(unsafe_uninit_length=self.width * self.height * img_buffer.channels)
        else:
            img_buffer.data_u8.resize(unsafe_uninit_length=self.width * self.height * img_buffer.channels)

        if self.color_type == 3:
            if is_16bit:
                for src_idx in range(len(unfiltered)):
                    var pal_idx = Int(unfiltered[src_idx]) * 3
                    var r = UInt16(self.palette[pal_idx]) << bit_shift_scale
                    var g = UInt16(self.palette[pal_idx + 1]) << bit_shift_scale
                    var b = UInt16(self.palette[pal_idx + 2]) << bit_shift_scale
                    img_buffer.data_u16.unsafe_set(dest_idx, r)
                    img_buffer.data_u16.unsafe_set(dest_idx + 1, g)
                    img_buffer.data_u16.unsafe_set(dest_idx + 2, b)
                    dest_idx += 3
            else:
                for src_idx in range(len(unfiltered)):
                    var pal_idx = Int(unfiltered[src_idx]) * 3
                    img_buffer.data_u8.unsafe_set(dest_idx, self.palette[pal_idx])
                    img_buffer.data_u8.unsafe_set(dest_idx + 1, self.palette[pal_idx + 1])
                    img_buffer.data_u8.unsafe_set(dest_idx + 2, self.palette[pal_idx + 2])
                    dest_idx += 3

        else:
            if self.bit_depth > 8:
                var num_samples = len(unfiltered) // 2
                if is_16bit:
                    for i in range(num_samples):
                        var hi = UInt16(unfiltered[i * 2])
                        var lo = UInt16(unfiltered[i * 2 + 1])
                        var val16 = (hi << 8) | lo
                        img_buffer.data_u16.unsafe_set(i, val16)
                else:
                    for i in range(num_samples):
                        img_buffer.data_u8.unsafe_set(dest_idx, unfiltered[i * 2])
                        dest_idx += 1
            else:
                if is_16bit:
                    for i in range(len(unfiltered)):
                        var val16 = UInt16(unfiltered.unsafe_get(i)) << bit_shift_scale
                        img_buffer.data_u16.unsafe_set(i, val16)
                else:
                    img_buffer.data_u8 = unfiltered^

        return img_buffer^