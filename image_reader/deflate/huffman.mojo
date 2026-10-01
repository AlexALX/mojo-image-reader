from image_reader.deflate.bitreader import BitReader

# Constants for DEFLATE fast lookup tables
comptime FAST_BITS: Int = 9
comptime FAST_BITS64: UInt64 = 9
comptime FAST_SIZE: Int = 1 << FAST_BITS
comptime FAST_MASK: Int = FAST_SIZE - 1

struct HuffmanTable:
    """Canonical Huffman decoder table with 9-bit primary fast LUT."""
    var fast_lut: List[UInt32]
    var max_code: List[Int]
    var min_code: List[Int]
    var val_ptr: List[Int]
    var symbols: List[Int]

    def __init__(out self):
        self.fast_lut = List[UInt32]()
        self.fast_lut.resize(FAST_SIZE, 0)
        self.max_code = List[Int]()
        self.max_code.resize(16, -1)
        self.min_code = List[Int]()
        self.min_code.resize(16, 0)
        self.val_ptr = List[Int]()
        self.val_ptr.resize(16, 0)
        self.symbols = List[Int]()

    def build(mut self, code_lengths: List[Int], num_symbols: Int) raises:
        """Builds fast lookup table and canonical trees from array of code lengths."""
        # 1. Count frequencies of each bit length
        var count = List[Int]()
        count.resize(16, 0)
        for i in range(num_symbols):
            var l = code_lengths[i]
            if l > 0:
                if l > 15:
                    raise Error("Invalid code length > 15 in Huffman tree")
                count[l] += 1

        # 2. Compute canonical base code for each bit length
        var next_code = List[Int]()
        next_code.resize(16, 0)
        var code = 0
        for bits in range(1, 16):
            code = (code + count[bits - 1]) << 1
            next_code[bits] = code

        # 3. Calculate canonical code ranges and value pointers
        var ptr = 0
        for bits in range(1, 16):
            if count[bits] > 0:
                self.min_code[bits] = next_code[bits]
                self.max_code[bits] = next_code[bits] + count[bits] - 1
                self.val_ptr[bits] = ptr
                ptr += count[bits]
            else:
                self.min_code[bits] = 0x7FFFFFFF
                self.max_code[bits] = -1
                self.val_ptr[bits] = 0

        # 4. Populate symbols array and primary 9-bit Fast LUT
        self.symbols.resize(ptr, 0)
        for sym in range(num_symbols):
            var l = code_lengths[sym]
            if l > 0:
                var c = next_code[l]
                next_code[l] += 1

                var pos = self.val_ptr[l] + (c - self.min_code[l])
                self.symbols[pos] = sym

                # Build fast LUT for codes <= FAST_BITS (9 bits)
                if l <= FAST_BITS:
                    # Reverse bits for LSB-first bitstream matching
                    var rev = 0
                    var tmp = c
                    for _ in range(l):
                        rev = (rev << 1) | (tmp & 1)
                        tmp >>= 1

                    # Pack LUT entry: (symbol << 4) | code_length
                    var entry = (UInt32(sym) << 4) | UInt32(l)
                    var fill_count = 1 << (FAST_BITS - l)
                    for i in range(fill_count):
                        var idx = rev | (i << l)
                        self.fast_lut[idx] = entry

    @always_inline
    def decode_symbol(self, mut reader: BitReader) raises -> Int:
        """Decodes next symbol using 1-cycle O(1) Fast LUT or canonical walk."""
        reader.refill()
        var peek = reader.peek_bits(FAST_BITS64)
        var entry = self.fast_lut[peek]

        if entry != 0:
            var code_len = UInt64(entry & 0x0F)
            var sym = Int(entry >> 4)
            reader.drop_bits(code_len)
            return sym

        # Fallback path for Huffman codes > 9 bits
        var code = 0
        for len in range(1, 16):
            code = (code << 1) | reader.read_bits(1)
            if code <= self.max_code[len]:
                var idx = self.val_ptr[len] + (code - self.min_code[len])
                return self.symbols[idx]

        raise Error("Invalid Huffman code in stream")