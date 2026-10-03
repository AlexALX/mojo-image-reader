from std.memory import Pointer
from std.sys.info import size_of

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

    # =========================================================================
    # BYTE READERS
    # =========================================================================

    @always_inline
    def u8_uint[unchecked: Bool = True](mut self) -> UInt8:
        """Reads a single 8-bit unsigned byte as UInt8 with optional bounds checking."""
        if not unchecked and self.is_eof():
                return 0
        var val = self.ptr[]
        self.ptr = self.ptr.unsafe_offset(1)
        return val

    @always_inline
    def u8[unchecked: Bool = True](mut self) -> Int:
        """Reads a single 8-bit unsigned byte as Int (-1 on EOF if checked)."""
        if not unchecked and self.is_eof():
                return -1
        var val = Int(self.ptr[])
        self.ptr = self.ptr.unsafe_offset(1)
        return val

    # =========================================================================
    # LITTLE-ENDIAN
    # =========================================================================

    @always_inline
    def u16_le[unchecked: Bool = True](mut self) -> Int:
        """Reads 2 bytes as little-endian 16-bit int in a single memory access."""
        if not unchecked and self.tell() + 2 > self.length:
                return 0
        var val = Int(self.ptr.unsafe_bitcast[UInt16]().unsafe_load(0))
        self.ptr = self.ptr.unsafe_offset(2)
        return val

    @always_inline
    def u32_le[unchecked: Bool = True](mut self) -> Int:
        """Reads 4 bytes as little-endian 32-bit int in a single memory access."""
        if not unchecked and self.tell() + 4 > self.length:
                return 0
        var val = Int(self.ptr.unsafe_bitcast[UInt32]().unsafe_load(0))
        self.ptr = self.ptr.unsafe_offset(4)
        return val

    # =========================================================================
    # BIG-ENDIAN
    # =========================================================================

    @always_inline
    def u16_be[unchecked: Bool = True](mut self) -> Int:
        """Reads 2 bytes as big-endian 16-bit int without separate byte calls."""
        if not unchecked and self.tell() + 2 > self.length:
                return 0
        var b0 = Int(self.ptr.unsafe_load(0))
        var b1 = Int(self.ptr.unsafe_load(1))
        self.ptr = self.ptr.unsafe_offset(2)
        return (b0 << 8) | b1

    @always_inline
    def u32_be[unchecked: Bool = True](mut self) -> Int:
        """Reads 4 bytes as big-endian 32-bit int without separate byte calls."""
        if not unchecked and self.tell() + 4 > self.length:
                return 0
        var b0 = Int(self.ptr.unsafe_load(0))
        var b1 = Int(self.ptr.unsafe_load(1))
        var b2 = Int(self.ptr.unsafe_load(2))
        var b3 = Int(self.ptr.unsafe_load(3))
        self.ptr = self.ptr.unsafe_offset(4)
        return (b0 << 24) | (b1 << 16) | (b2 << 8) | b3

    # =========================================================================
    # PEEK & SIMD METHODS
    # =========================================================================

    @always_inline
    def peek_u8(self) -> Int:
        """Inspects the next byte without shifting the stream pointer."""
        if self.is_eof():
            return -1
        return Int(self.ptr[unsafe_offset=0])

    @always_inline
    def peek_u16_le(self) -> Int:
        """Inspects the next little-endian 16-bit unsigned integer."""
        if self.tell() + 1 >= self.length:
            return -1
        return Int(self.ptr.unsafe_bitcast[UInt16]().unsafe_load(0))

    @always_inline
    def peek_u16_be(self) -> Int:
        """Inspects the next big-endian 16-bit unsigned integer."""
        if self.tell() + 1 >= self.length:
            return -1
        var b0 = Int(self.ptr.unsafe_load(0))
        var b1 = Int(self.ptr.unsafe_load(1))
        return (b0 << 8) | b1

    @always_inline
    def read_simd[type: DType, width: Int](mut self) -> SIMD[type, width]:
        """Directly loads a SIMD vector from current pointer position."""
        var val = self.ptr.unsafe_bitcast[SIMD[type, width]]()[unsafe_offset=0]
        self.ptr = self.ptr.unsafe_offset(width * size_of[type]())
        return val

    @always_inline
    def debug_dump_bytes(mut self, bytes_read: Int):
        var curpos = self.tell()
        var bytes = List[UInt8]()

        self.seek(curpos - bytes_read / 2)

        print("Current position: ", curpos)

        for _ in range(bytes_read):
            bytes.append(self.u8_uint())

        self.seek(curpos)

        print("Bytes around: ", bytes)