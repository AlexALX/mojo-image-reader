from image_reader.binaryreader import BinaryReader

struct BitMaskInfo:
    var mask: Int
    var shift: Int
    var max_val: Int

    def __init__(out self, mask: Int = 0):
        self.mask = mask
        self.shift = 0
        self.max_val = 0
        if mask != 0:
            var m = mask
            while (m & 1) == 0:
                m >>= 1
                self.shift += 1
            self.max_val = m

    @always_inline
    def extract_u8(self, pixel_val: Int) -> UInt8:
        if self.mask == 0 or self.max_val == 0:
            return UInt8(0)
        var val = (pixel_val & self.mask) >> self.shift
        if self.max_val == 255:
            return UInt8(val)
        return UInt8((val * 255) // self.max_val)

struct BmpParser:
    var reader: BinaryReader
    var width: Int
    var height: Int
    var is_top_down: Bool
    var bits_per_pixel: Int
    var compression: Int
    var pixel_offset: Int
    var palette: List[UInt8]
    var row_bytes: Int
    var padding: Int
    var has_alpha: Bool
    var is_grayscale: Bool
    var r_mask_info: BitMaskInfo
    var g_mask_info: BitMaskInfo
    var b_mask_info: BitMaskInfo
    var a_mask_info: BitMaskInfo
    var precision: Int

    def __init__(out self, var bytes: List[UInt8], precision: Int) raises:
        self.reader = BinaryReader(bytes^)
        self.precision = precision
        self.width = 0
        self.height = 0
        self.is_top_down = False
        self.bits_per_pixel = 0
        self.compression = 0
        self.pixel_offset = 0
        self.palette = List[UInt8]()
        self.row_bytes = 0
        self.padding = 0
        self.has_alpha = False
        self.is_grayscale = False
        self.r_mask_info = BitMaskInfo()
        self.g_mask_info = BitMaskInfo()
        self.b_mask_info = BitMaskInfo()
        self.a_mask_info = BitMaskInfo()

    def parse_headers(mut self) raises:
        # Check 'BM' signature
        var sig1 = self.reader.u8_uint()
        var sig2 = self.reader.u8_uint()
        if sig1 != UInt8(0x42) or sig2 != UInt8(0x4D):
            raise Error("Invalid BMP signature")

        _ = self.reader.u32_le() # File size
        _ = self.reader.u16_le() # Reserved1
        _ = self.reader.u16_le() # Reserved2
        self.pixel_offset = self.reader.u32_le()

        # Parse Info Header
        var header_size = self.reader.u32_le()
        var palette_entry_size = 4

        var r_mask: Int = 0
        var g_mask: Int = 0
        var b_mask: Int = 0
        var a_mask: Int = 0
        var colors_used: Int = 0

        if header_size == 12: # BITMAPCOREHEADER
            self.width = self.reader.u16_le()
            self.height = self.reader.u16_le()
            _ = self.reader.u16_le() # Planes
            self.bits_per_pixel = self.reader.u16_le()
            self.compression = 0
            palette_entry_size = 3
        else:
            self.width = self.reader.u32_le()
            var raw_height = self.reader.u32_le()

            # Handle top-down orientation for negative height values
            if raw_height > 2147483647:
                self.height = 4294967296 - raw_height
                self.is_top_down = True
            else:
                self.height = raw_height
                self.is_top_down = False

            _ = self.reader.u16_le() # Planes
            self.bits_per_pixel = self.reader.u16_le()
            self.compression = self.reader.u32_le()

            if self.is_top_down and (self.compression == 1 or self.compression == 2):
                raise Error("Top-down BMP cannot be RLE compressed")

            _ = self.reader.u32_le() # Image size
            _ = self.reader.u32_le() # X pixels per meter
            _ = self.reader.u32_le() # Y pixels per meter
            colors_used = self.reader.u32_le() # Colors used
            _ = self.reader.u32_le() # Colors important

            if self.bits_per_pixel > 8:
                # Read bitfield masks from V2/V3 headers if available
                if header_size >= 52:
                    r_mask = self.reader.u32_le()
                    g_mask = self.reader.u32_le()
                    b_mask = self.reader.u32_le()
                if header_size >= 56:
                    a_mask = self.reader.u32_le()

        # Read BI_BITFIELDS / BI_ALPHABITFIELDS if defined outside header
        if (self.compression == 3 or self.compression == 6) and header_size == 40:
            r_mask = self.reader.u32_le()
            g_mask = self.reader.u32_le()
            b_mask = self.reader.u32_le()
            if self.compression == 6:
                a_mask = self.reader.u32_le()

        # Fallback default masks for 16-bit and 32-bit images
        if r_mask == 0 and g_mask == 0 and b_mask == 0:
            if self.bits_per_pixel == 16:
                r_mask = 0x7C00
                g_mask = 0x03E0
                b_mask = 0x001F
            elif self.bits_per_pixel == 32:
                r_mask = 0x00FF0000
                g_mask = 0x0000FF00
                b_mask = 0x000000FF
                a_mask = 0xFF000000

        self.r_mask_info = BitMaskInfo(r_mask)
        self.g_mask_info = BitMaskInfo(g_mask)
        self.b_mask_info = BitMaskInfo(b_mask)
        self.a_mask_info = BitMaskInfo(a_mask)

        if a_mask != 0:
            self.has_alpha = True

        # Calculate row alignment padding
        self.row_bytes = (self.width * self.bits_per_pixel + 7) // 8
        var row_stride = ((self.bits_per_pixel * self.width + 31) // 32) * 4
        self.padding = row_stride - self.row_bytes

        self.reader.seek(14 + header_size)

        # Read Palette for indexed color modes
        if self.bits_per_pixel <= 8:
            var max_colors = 1 << self.bits_per_pixel
            var color_count = colors_used if (0 < colors_used and colors_used <= max_colors) else max_colors
            self.palette.reserve(color_count * 3)

            self.is_grayscale = True
            for _ in range(color_count):
                var b: UInt8 = self.reader.u8_uint()
                var g: UInt8 = self.reader.u8_uint()
                var r: UInt8 = self.reader.u8_uint()
                if palette_entry_size == 4:
                    _ = self.reader.u8_uint()

                self.palette.append(r)
                self.palette.append(g)
                self.palette.append(b)

                # Detect if palette is Grayscale and check for transparency
                if self.is_grayscale and (r != g or g != b):
                    self.is_grayscale = False