from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader

struct HuffmanTable:
    var table_class: Int           # Table class: 0 = DC, 1 = AC
    var id: Int                    # Table identifier (0-3)
    var counts: List[Int]          # Number of codes for each bit length (1-16)
    var symbols: List[Int]         # Raw symbol values array
    var max_bits: Int              # Maximum code bit length encountered
    var lookup: Dict[Int, Int]     # Primary lookup table: key = (bits << 16) + code, value = symbol + 1

    def __init__(out self: Self, table_class: Int, id: Int):
        self.table_class = table_class
        self.id = id
        self.counts = List[Int]()
        for _ in range(16):
            self.counts.append(0)
        self.symbols = List[Int]()
        self.max_bits = 0
        self.lookup = Dict[Int, Int]()

    def build_huffman(mut self):
        """
        Builds Huffman prefix codes, primary lookup entries,
        and fast lookahead, caches mirroring.
        """
        var code = 0
        var index = 0
        var max_bits_val = 0

        # Iterate through all 16 possible bit lengths
        for bits in range(1, 17):
            var count = self.counts[bits - 1]

            if count > 0:
                max_bits_val = bits

            for _ in range(count):
                if index >= len(self.symbols):
                    break

                var symbol = self.symbols[index]

                # Populate primary lookup map: key = (bits << 16) + code
                var lookup_key = (bits << 16) + code
                self.lookup[lookup_key] = symbol + 1

                code += 1
                index += 1

            # Shift code left for the next bit length tier
            code <<= 1

        self.max_bits = max_bits_val

    def huffman_read(self, mut bitreader: BitReader) raises -> Int:
        """
        Reads a single Huffman-encoded symbol from the bit stream.
        """
        var code = 0

        for bits in range(1, self.max_bits + 1):
            if bitreader.bit_count == 0:
                var byte = bitreader.read_byte()
                if byte<0:
                    return byte
                bitreader.bit_buffer = byte
                bitreader.bit_count = 8

            bitreader.bit_count -= 1

            # Extract the next single bit from the buffer
            var bit = (bitreader.bit_buffer >> bitreader.bit_count) & 1
            code = (code << 1) | bit

            # Check lookup table for a matching code
            var key = (bits << 16) + code
            if key in self.lookup:
                var val = self.lookup[key]
                return val - 1

        # Return error code if no valid prefix matches
        return -100