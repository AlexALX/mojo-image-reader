from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader

struct HuffmanTable:
    var table_class: Int           # Table class: 0 = DC, 1 = AC
    var id: Int                    # Table identifier (0-3)
    var counts: List[Int]          # Number of codes for each bit length (1-16)
    var symbols: List[Int]         # Raw symbol values array
    var max_bits: Int              # Maximum code bit length encountered

    # Fast flat lookup table: index = 10-bit prefix, value = (symbol << 4) | length
    var fast_lookup: List[Int]

    # OPTIMIZATION: Flat lists replace Dict for fast fallback linear search
    var fallback_keys: List[Int]
    var fallback_vals: List[Int]

    def __init__(out self: Self, table_class: Int, id: Int):
        self.table_class = table_class
        self.id = id
        self.counts = List[Int](length=16, fill=0)
        self.symbols = List[Int]()
        self.max_bits = 0
        self.fast_lookup = List[Int](length=1024, fill=0)

        # Pre-allocate to avoid reallocations. A JPEG Huffman table has max 256 symbols.
        self.fallback_keys = List[Int](capacity=256)
        self.fallback_vals = List[Int](capacity=256)

    def build_huffman(mut self):
        """
        Builds Huffman prefix codes and populates a 10-bit flat fast lookup table
        along with a flat list fallback for longer codes.
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

                if bits <= 10:
                    # Populate fast lookup table by replicating entries for all trailing bit variations
                    var shift = 10 - bits
                    var base_code = code << shift
                    var num_entries = 1 << shift
                    var packed_val = (symbol << 4) | bits

                    if base_code + num_entries <= 1024:
                        for i in range(num_entries):
                            self.fast_lookup.unsafe_set(base_code + i, packed_val)

                # Fallback for rare long codes or insufficient bits
                var lookup_key = (bits << 16) + code
                self.fallback_keys.unsafe_set(index, lookup_key)
                self.fallback_vals.unsafe_set(index, symbol)

                code += 1
                index += 1

            # Shift code left for the next bit length tier
            code <<= 1

        self.fallback_keys.resize(unsafe_uninit_length=index)
        self.fallback_vals.resize(unsafe_uninit_length=index)

        self.max_bits = max_bits_val

    @always_inline
    def huffman_read(self, mut bitreader: BitReader) raises -> Int:
        """
        Reads a Huffman-encoded symbol in O(1) using the fast lookup table.
        Uses a highly cache-friendly linear search for slow paths.
        """

        var found_marker = 0

        # Ensure we have at least 10 bits in the bit_buffer
        while bitreader.bit_count < 10:

            if bitreader.restart_marker:
                return -2

            if bitreader.early_marker:
                return -1

            var byte = bitreader.read_byte()
            if byte < 0:
                found_marker = byte
                break

            bitreader.bit_buffer = (bitreader.bit_buffer << 8) | byte
            bitreader.bit_count += 8

        # If we have at least 10 bits, do a fast O(1) array lookup
        if bitreader.bit_count >= 10:
            var peek_idx = (bitreader.bit_buffer >> (bitreader.bit_count - 10)) & 0x3FF
            var entry = self.fast_lookup.unsafe_get(peek_idx)

            if entry != 0:
                var length = entry & 0x0F
                var symbol = entry >> 4
                bitreader.bit_count -= length
                return symbol

        # Fallback slow path for codes longer than 10 bits or edge cases
        var code = 0
        for bits in range(1, self.max_bits + 1):
            if bitreader.bit_count == 0:
                if found_marker:
                    return found_marker

                if bitreader.restart_marker:
                    return -2

                if bitreader.early_marker:
                    return -1

                var byte = bitreader.read_byte()
                if byte < 0:
                    return byte
                bitreader.bit_buffer = byte
                bitreader.bit_count = 8

            bitreader.bit_count -= 1
            var bit = (bitreader.bit_buffer >> bitreader.bit_count) & 1
            code = (code << 1) | bit

            var key = (bits << 16) + code

            # OPTIMIZATION: Linear search over contiguous memory replaces Dict hash lookup
            var count = len(self.fallback_keys)
            for i in range(count):
                if self.fallback_keys.unsafe_get(i) == key:
                    return self.fallback_vals.unsafe_get(i)

        raise Error("Invalid Huffman Code")