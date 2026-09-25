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
        # 1. Get the numeric memory address of the list's underlying buffer
        var raw_address = Int(bytes.unsafe_ptr())

        # 2. Construct the untracked Pointer directly from the address as documented
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
    def u8(mut self) -> Int:
        """Reads a single 8-bit unsigned byte and advances the internal stream pointer."""
        if self.is_eof():
            return -1
        # Official Mojo 1.1 dereferencing syntax via empty brackets ptr[]
        var val = Int(self.ptr[])
        self.ptr = self.ptr.unsafe_offset(1)
        return val

    @always_inline
    def u16(mut self) -> Int:
        """Reads two bytes sequentially as a big-endian 16-bit unsigned integer."""
        var hi = self.u8()
        var lo = self.u8()
        return (hi << 8) | lo

    @always_inline
    def skip(mut self, offset: Int):
        """Advances the internal stream pointer forward by a specified byte offset."""
        self.ptr = self.ptr.unsafe_offset(offset)

    @always_inline
    def peek_u16(self) -> Int:
        """Inspects the next big-endian 16-bit unsigned integer without shifting the stream pointer."""
        if self.tell() + 1 >= self.length:
            return -1
        # Use official subscript syntax with unsafe_offset keyword argument from manual
        var hi = Int(self.ptr[unsafe_offset=0])
        var lo = Int(self.ptr[unsafe_offset=1])
        return (hi << 8) | lo
