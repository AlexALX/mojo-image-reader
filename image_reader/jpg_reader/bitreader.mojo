from image_reader.binaryreader import BinaryReader

struct BitReader:
    var reader: BinaryReader
    var bit_buffer: Int
    var bit_count: Int
    var restart_marker: Int
    var early_marker: Int

    def __init__(out self, var reader: BinaryReader):
        self.reader = reader^

        self.bit_buffer = 0
        self.bit_count = 0
        self.restart_marker = 0
        self.early_marker = 0

    @always_inline
    def init(mut self):
        self.bit_buffer = 0
        self.bit_count = 0
        self.restart_marker = 0
        self.early_marker = 0

    @always_inline
    @staticmethod
    def extend(value: Int, size: Int) -> Int:
        """
        Extends the sign bit for JPEG entropy values.
        """
        if size == 0:
            return 0
        var limit = 1 << (size - 1)
        if value >= limit:
            return value
        return value - ((1 << size) - 1)

    def read_byte(mut self) raises -> Int:
        var byte = self.reader.u8()
        if byte != 0xFF:
            return byte

        var next_byte = self.reader.u8()

        # Byte stuffing (FF 00 -> FF)
        if next_byte == 0x00:
            return 0xFF

        # Restart markers (FF D0 - FF D7)
        if next_byte >= 0xD0 and next_byte <= 0xD7:
            self.restart_marker = next_byte
            return -2

        # End of entropy stream / markers
        self.early_marker = (0xFF00 | next_byte)
        return -1

    def bits(mut self, bits_count: Int) raises -> Int:
        if bits_count == 0:
            return 0

        var buffer = self.bit_buffer
        var count = self.bit_count

        while count < bits_count:
            var b = self.read_byte()
            if b < 0:
                self.bit_count = 0
                self.bit_buffer = buffer
                return b
            buffer = (buffer << 8) | b
            count += 8

        count = count - bits_count
        var value = (buffer >> count) & ((1 << bits_count) - 1)

        self.bit_count = count
        self.bit_buffer = buffer

        return value

    def bit(mut self) raises -> Int:
        if self.bit_count == 0:
            var b = self.read_byte()
            if b < 0:
                return b
            self.bit_buffer = b
            self.bit_count = 8

        self.bit_count -= 1
        return (self.bit_buffer >> self.bit_count) & 1

    @always_inline
    def align(mut self):
        self.bit_buffer = 0
        self.bit_count = 0