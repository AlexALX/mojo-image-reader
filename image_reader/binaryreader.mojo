from std.memory import Pointer

struct BinaryReader:
    # Explicitly typed fields using the built-in MutUntrackedOrigin token
    var ptr: Pointer[UInt8, MutUntrackedOrigin]
    var start_ptr: Pointer[UInt8, MutUntrackedOrigin]
    var length: Int
    var bytes: List[UInt8]

    @always_inline
    def __init__(out self: Self, var bytes: List[UInt8]):
        """Initializes the reader directly from a byte array address bypassing lifetime tracking safely."""
        var raw_address = Int(bytes.unsafe_ptr())
        self.start_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=raw_address)
        self.ptr = self.start_ptr
        self.length = len(bytes)
        self.bytes = bytes^

    @always_inline
    def tell(self) -> Int:
        """Returns the current absolute byte offset inside the stream."""
        return Int(self.ptr - self.start_ptr)

    @always_inline
    def is_eof(self) -> Bool:
        """Checks if the pointer has reached or exceeded the buffer memory boundary."""
        return self.tell() >= self.length

    @always_inline
    def seek(mut self, offset: Int):
        """Sets the current absolute position in the stream."""
        if offset >= 0 and offset <= self.length:
            self.ptr = self.start_ptr.unsafe_offset(offset)

    @always_inline
    def skip(mut self, offset: Int):
        """Advances the internal stream pointer forward by a specified byte offset."""
        self.ptr = self.ptr.unsafe_offset(offset)

    @always_inline
    def u8_uint(mut self) -> UInt8:
        """Reads a single 8-bit unsigned byte as UInt8 and advances the internal stream pointer."""
        if self.is_eof():
            return 0
        var val = self.ptr[]
        self.ptr = self.ptr.unsafe_offset(1)
        return val

    @always_inline
    def u8(mut self) -> Int:
        """Reads a single 8-bit unsigned byte as Int and advances the internal stream pointer. Returns -1 on EOF."""
        if self.is_eof():
            return -1
        var val = Int(self.ptr[])
        self.ptr = self.ptr.unsafe_offset(1)
        return val

    @always_inline
    def u16_le(mut self) -> Int:
        """Reads two bytes sequentially as a little-endian 16-bit unsigned integer."""
        var lo = self.u8()
        var hi = self.u8()
        return lo | (hi << 8)

    @always_inline
    def u32_le(mut self) -> Int:
        """Reads four bytes sequentially as a little-endian 32-bit unsigned integer."""
        var b0 = self.u8()
        var b1 = self.u8()
        var b2 = self.u8()
        var b3 = self.u8()
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)

    @always_inline
    def u16_be(mut self) -> Int:
        """Reads two bytes sequentially as a big-endian 16-bit unsigned integer."""
        var hi = self.u8()
        var lo = self.u8()
        return (hi << 8) | lo

    @always_inline
    def u32_be(mut self) -> Int:
        """Reads four bytes sequentially as a big-endian 32-bit unsigned integer."""
        var b0 = self.u8()
        var b1 = self.u8()
        var b2 = self.u8()
        var b3 = self.u8()
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3

    @always_inline
    def peek_u8(self) -> Int:
        """Inspects the next byte without shifting the stream pointer."""
        if self.is_eof():
            return -1
        return Int(self.ptr[unsafe_offset=0])

    @always_inline
    def peek_u16_le(self) -> Int:
        """Inspects the next little-endian 16-bit unsigned integer without shifting the stream pointer."""
        if self.tell() + 1 >= self.length:
            return -1

        var lo = Int(self.ptr[unsafe_offset=0])
        var hi = Int(self.ptr[unsafe_offset=1])
        return lo | (hi << 8)

    @always_inline
    def peek_u16_be(self) -> Int:
        """Inspects the next big-endian 16-bit unsigned integer without shifting the stream pointer."""
        if self.tell() + 1 >= self.length:
            return -1

        var hi = Int(self.ptr[unsafe_offset=0])
        var lo = Int(self.ptr[unsafe_offset=1])
        return (hi << 8) | lo