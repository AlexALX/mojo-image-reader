from image_reader.binaryreader import BinaryReader
from std.memory import unsafe_memcpy

struct GifParser:
    var reader: BinaryReader
    var global_width: Int
    var global_height: Int
    var global_palette: List[UInt8]
    var background_index: UInt8
    var loop_count: Int
    var precision: Int

    def __init__(out self, var bytes: List[UInt8], precision: Int) raises:
        self.reader = BinaryReader(bytes^)
        self.global_width = 0
        self.global_height = 0
        self.global_palette = List[UInt8]()
        self.background_index = 0
        self.loop_count = 0
        self.precision = precision

    def parse_header(mut self) raises:
        var sig1 = self.reader.u8()
        var sig2 = self.reader.u8()
        var sig3 = self.reader.u8()
        if sig1 != 0x47 or sig2 != 0x49 or sig3 != 0x46: # "GIF"
            raise Error("Invalid GIF signature")

        self.reader.skip(3) # "89a" or "87a"

        self.global_width = self.reader.u16_le()
        self.global_height = self.reader.u16_le()

        var packed = self.reader.u8()
        self.background_index = self.reader.u8_uint()
        _ = self.reader.u8() # Aspect ratio

        var has_gct = (packed & 0x80) != 0
        var gct_size = 1 << ((packed & 0x07) + 1)

        if has_gct:
            self.global_palette.reserve(gct_size * 3)
            for _ in range(gct_size):
                self.global_palette.append(self.reader.u8_uint())
                self.global_palette.append(self.reader.u8_uint())
                self.global_palette.append(self.reader.u8_uint())

    def read_sub_blocks(mut self) -> List[UInt8]:
        var data = List[UInt8](capacity=8192)
        while True:
            var size = self.reader.u8()
            if size == 0:
                break

            var old_len = len(data)
            data.resize(unsafe_uninit_length=old_len + size)

            unsafe_memcpy(dest=data.unsafe_ptr().unsafe_offset(old_len), src=self.reader.ptr, count=size)
            self.reader.skip(size)
        return data^