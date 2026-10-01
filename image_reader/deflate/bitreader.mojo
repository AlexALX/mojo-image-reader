from std.memory import Pointer

struct BitReader:
    """Fast LSB bit reader over contiguous memory using 64-bit bit buffer."""
    var bytes: List[UInt8]
    var ptr: Pointer[UInt8, MutUntrackedOrigin]
    var start_ptr: Pointer[UInt8, MutUntrackedOrigin]
    var end_ptr: Pointer[UInt8, MutUntrackedOrigin]
    var bit_buf: UInt64
    var bit_count: UInt64

    @always_inline
    def __init__(out self, var bytes: List[UInt8], length: Int):
        self.bytes = bytes^
        var ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(self.bytes.unsafe_ptr()))

        self.start_ptr = ptr
        self.ptr = ptr
        self.end_ptr = ptr.unsafe_offset(length)
        self.bit_buf = 0
        self.bit_count = 0

    @always_inline
    def refill(mut self):
        """Fills the bit buffer with raw bytes up to 56 bits using fast unaligned loads."""
        var p = self.ptr
        var bytes_left = Int(self.end_ptr) - Int(p)

        # Fast path: load 8 raw bytes in a single UInt64 read if space allows
        if bytes_left >= 8:
            if self.bit_count <= 32:
                # Explicit 64-bit load from byte pointer address
                var u64_ptr = Pointer[UInt64, MutUntrackedOrigin](unsafe_from_address=Int(p))
                var raw_u64 = u64_ptr.unsafe_load()

                self.bit_buf |= (raw_u64 << self.bit_count)
                var bytes_added = Int((64 - self.bit_count) >> 3)
                self.bit_count += UInt64(bytes_added << 3)
                self.ptr = p.unsafe_offset(bytes_added)
            return

        # Slow fallback path near end of stream
        var buf = self.bit_buf
        var count = self.bit_count

        while count <= 56 and Int(p) < Int(self.end_ptr):
            var byte_val = UInt64(p.unsafe_load())
            p = p.unsafe_offset(1)
            buf |= (byte_val << count)
            count += 8

        self.bit_buf = buf
        self.bit_count = count
        self.ptr = p

    @always_inline
    def peek_bits(self, bits: UInt64) -> Int:
        """Inspects the lowest 'bits' from the bit buffer without advancing."""
        var mask = (1 << bits) - 1
        return Int(self.bit_buf & mask)

    @always_inline
    def drop_bits(mut self, bits: UInt64):
        """Consumes 'bits' from the internal bit buffer."""
        self.bit_buf >>= bits
        self.bit_count -= bits

    @always_inline
    def read_bits(mut self, bits: UInt64) raises -> Int:
        """Refills and reads requested number of bits from stream."""
        if bits == 0:
            return 0
        self.refill()
        if self.bit_count < bits:
            raise Error("Unexpected EOF in DEFLATE bitstream")
        var val = self.peek_bits(bits)
        self.drop_bits(bits)
        return val

    @always_inline
    def align_to_byte(mut self):
        """Discards unaligned bits up to the next byte boundary."""
        var skip = self.bit_count & 7
        if skip > 0:
            self.drop_bits(skip)

    @always_inline
    def read_byte_aligned(mut self) raises -> UInt8:
        """Reads a single byte directly on byte boundary."""
        self.align_to_byte()
        if self.bit_count >= 8:
            var val = UInt8(self.bit_buf & 0xFF)
            self.drop_bits(8)
            return val

        var p = self.ptr
        if Int(p) >= Int(self.end_ptr):
            raise Error("Unexpected EOF in raw block stream")
        var val = p.unsafe_load()
        self.ptr = p.unsafe_offset(1)
        return val