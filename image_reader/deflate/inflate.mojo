from image_reader.deflate import BitReader, HuffmanTable

struct Inflater:
    """High-performance DEFLATE and ZLIB stream decompressor."""

    var length_base: List[Int]
    var length_extra: List[UInt64]
    var dist_base: List[Int]
    var dist_extra: List[UInt64]
    var cl_order: List[UInt64]

    @always_inline
    def __init__(out self):
        self.length_base = [
            3, 4, 5, 6, 7, 8, 9, 10, 11, 13, 15, 17, 19, 23, 27, 31, 35, 43, 51, 59, 67, 83, 99, 115, 131, 163, 195, 227, 258
        ]
        self.length_extra = [
            0, 0, 0, 0, 0, 0, 0, 0, 1, 1, 1, 1, 2, 2, 2, 2, 3, 3, 3, 3, 4, 4, 4, 4, 5, 5, 5, 5, 0
        ]
        self.dist_base = [
            1, 2, 3, 4, 5, 7, 9, 13, 17, 25, 33, 49, 65, 97, 129, 193, 257, 385, 513, 769, 1025, 1537, 2049, 3073, 4097, 6145, 8193, 12289, 16385, 24577
        ]
        self.dist_extra = [
            0, 0, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 5, 6, 6, 7, 7, 8, 8, 9, 9, 10, 10, 11, 11, 12, 12, 13, 13
        ]
        self.cl_order = [
            16, 17, 18, 0, 8, 7, 9, 6, 10, 5, 11, 4, 12, 3, 13, 2, 14, 1, 15
        ]

    def _build_fixed_literal_table(self) raises -> HuffmanTable:
        """Constructs fixed literal/length Huffman table specified in RFC 1951."""
        var lens = List[Int]()
        lens.resize(288, 0)
        for i in range(0, 144): lens[i] = 8
        for i in range(144, 256): lens[i] = 9
        for i in range(256, 280): lens[i] = 7
        for i in range(280, 288): lens[i] = 8

        var table = HuffmanTable()
        table.build(lens, 288)
        return table^

    def _build_fixed_distance_table(self) raises -> HuffmanTable:
        """Constructs fixed distance Huffman table specified in RFC 1951."""
        var lens = List[Int]()
        lens.resize(32, 5)

        var table = HuffmanTable()
        table.build(lens, 32)
        return table^

    @always_inline
    def _decode_lz77_block(
        self,
        mut reader: BitReader,
        lit_table: HuffmanTable,
        dist_table: HuffmanTable,
        mut out_data: List[UInt8],
        mut cur_pos: Int,
    ) raises -> Int:
        """Decodes LZ77 stream with 64-bit chunk copies and direct raw pointer access."""
        var out_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(out_data.unsafe_ptr()))

        while True:
            var sym = lit_table.decode_symbol(reader)

            if sym < 256:
                # Direct Literal Byte store without append() overhead
                out_ptr.unsafe_offset(cur_pos).unsafe_store(UInt8(sym))
                cur_pos += 1
            elif sym == 256:
                # End of DEFLATE block
                break
            else:
                # LZ77 Length + Distance Back-reference
                var len_idx = sym - 257
                var match_len = self.length_base[len_idx] + reader.read_bits(self.length_extra[len_idx])

                var dist_sym = dist_table.decode_symbol(reader)
                var dist = self.dist_base[dist_sym] + reader.read_bits(self.dist_extra[dist_sym])

                var src_pos = cur_pos - Int(dist)
                if src_pos < 0:
                    raise Error("Invalid LZ77 backward distance out of bounds")

                # Ensure buffer space in large chunks to prevent constant reallocations
                if cur_pos + match_len + 32 > len(out_data):
                    out_data.resize(cur_pos + match_len + 65536, 0)
                    out_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(out_data.unsafe_ptr()))

                # Fast LZ77 copying logic
                if dist >= 8:
                    # Non-overlapping or >= 8-byte overlap: copy in fast 64-bit (8-byte) chunks
                    var copied = 0
                    while copied < match_len:
                        var src_p64 = Pointer[UInt64, MutUntrackedOrigin](unsafe_from_address=Int(out_ptr.unsafe_offset(src_pos + copied)))
                        var dst_p64 = Pointer[UInt64, MutUntrackedOrigin](unsafe_from_address=Int(out_ptr.unsafe_offset(cur_pos + copied)))
                        dst_p64.unsafe_store(src_p64.unsafe_load())
                        copied += 8
                elif dist == 1:
                    # RLE fill: broadcast single byte across 64-bit integers
                    var fill_byte = UInt64(out_ptr.unsafe_offset(src_pos).unsafe_load())
                    var pattern = fill_byte * 0x0101010101010101
                    var copied = 0
                    while copied < match_len:
                        var dst_p64 = Pointer[UInt64, MutUntrackedOrigin](unsafe_from_address=Int(out_ptr.unsafe_offset(cur_pos + copied)))
                        dst_p64.unsafe_store(pattern)
                        copied += 8
                else:
                    # Short overlap (dist < 8): byte-by-byte copy fallback
                    for i in range(match_len):
                        var b = out_ptr.unsafe_offset(src_pos + i).unsafe_load()
                        out_ptr.unsafe_offset(cur_pos + i).unsafe_store(b)

                cur_pos += match_len

        return cur_pos

    def decompress_deflate(mut self, mut reader: BitReader, initial_capacity: Int = 65536) raises -> List[UInt8]:
        """Decompresses raw DEFLATE stream directly into uncompressed output byte list."""
        var out_data = List[UInt8]()

        # Pre-allocate expected size + padding safety zone
        var alloc_size = max(initial_capacity, 65536) + 256
        out_data.resize(alloc_size, 0)

        var cur_pos = 0
        var is_final = False

        # Build reusable fixed Huffman tables
        var fixed_lit_table = self._build_fixed_literal_table()
        var fixed_dist_table = self._build_fixed_distance_table()

        while not is_final:
            is_final = (reader.read_bits(1) == 1)
            var block_type = reader.read_bits(2)

            if block_type == 0:
                # BTYPE 00: Uncompressed (Raw) Block
                reader.align_to_byte()
                var len_lo = Int(reader.read_byte_aligned())
                var len_hi = Int(reader.read_byte_aligned())
                var block_len = len_lo | (len_hi << 8)

                var nlen_lo = Int(reader.read_byte_aligned())
                var nlen_hi = Int(reader.read_byte_aligned())
                var nblock_len = nlen_lo | (nlen_hi << 8)

                if (block_len ^ 0xFFFF) != nblock_len:
                    raise Error("Raw DEFLATE block length check failed")

                if cur_pos + block_len > len(out_data):
                    out_data.resize(cur_pos + block_len + 65536, 0)

                var out_ptr = Pointer[UInt8, MutUntrackedOrigin](unsafe_from_address=Int(out_data.unsafe_ptr()))
                for i in range(block_len):
                    out_ptr.unsafe_offset(cur_pos + i).unsafe_store(reader.read_byte_aligned())
                cur_pos += block_len

            elif block_type == 1:
                cur_pos = self._decode_lz77_block(reader, fixed_lit_table, fixed_dist_table, out_data, cur_pos)
            elif block_type == 2:
                # Dynamic Huffman Tree Setup
                var hlit = reader.read_bits(5) + 257
                var hdist = reader.read_bits(5) + 1
                var hclen = reader.read_bits(4) + 4

                var cl_lens = List[Int]()
                cl_lens.resize(19, 0)
                for i in range(hclen):
                    cl_lens[Int(self.cl_order[i])] = reader.read_bits(3)

                var cl_table = HuffmanTable()
                cl_table.build(cl_lens, 19)

                var total_codes = hlit + hdist
                var code_lens = List[Int]()
                code_lens.reserve(total_codes)

                while len(code_lens) < total_codes:
                    var sym = cl_table.decode_symbol(reader)
                    if sym <= 15:
                        code_lens.append(sym)
                    elif sym == 16:
                        if len(code_lens) == 0:
                            raise Error("Repeat code 16 with no preceding symbol")
                        var prev = code_lens[len(code_lens) - 1]
                        var repeat_times = 3 + reader.read_bits(2)
                        for _ in range(repeat_times):
                            code_lens.append(prev)
                    elif sym == 17:
                        var repeat_times = 3 + reader.read_bits(3)
                        for _ in range(repeat_times):
                            code_lens.append(0)
                    elif sym == 18:
                        var repeat_times = 11 + reader.read_bits(7)
                        for _ in range(repeat_times):
                            code_lens.append(0)

                # Split code lengths into Literal/Length and Distance sets
                var lit_lens = List[Int]()
                lit_lens.reserve(hlit)
                for i in range(hlit):
                    lit_lens.append(code_lens[i])

                var dist_lens = List[Int]()
                dist_lens.reserve(hdist)
                for i in range(hlit, total_codes):
                    dist_lens.append(code_lens[i])

                var lit_table = HuffmanTable()
                lit_table.build(lit_lens, hlit)

                var dist_table = HuffmanTable()
                dist_table.build(dist_lens, hdist)

                cur_pos = self._decode_lz77_block(reader, lit_table, dist_table, out_data, cur_pos)
            else:
                raise Error("Reserved invalid DEFLATE block type (11)")

        # Final resize to exact unpacked length
        out_data.resize(cur_pos, 0)
        return out_data^

    def decompress_zlib(mut self, var bytes: List[UInt8], expected_size: Int = 65536) raises -> List[UInt8]:
        """Parses ZLIB header (RFC 1950) and decompresses the underlying DEFLATE stream."""
        var reader = BitReader(bytes^, expected_size)

        # 1. Parse CMF & FLG Header
        var cmf = Int(reader.read_byte_aligned())
        var flg = Int(reader.read_byte_aligned())

        var cm = cmf & 0x0F
        if cm != 8:
            raise Error("Unsupported ZLIB compression method (must be 8 for DEFLATE)")

        if ((cmf * 256) + flg) % 31 != 0:
            raise Error("ZLIB header checksum verification failed")

        # Check FDICT flag
        if (flg & 0x20) != 0:
            # Skip 4-byte dictionary identifier
            _ = reader.read_byte_aligned()
            _ = reader.read_byte_aligned()
            _ = reader.read_byte_aligned()
            _ = reader.read_byte_aligned()

        # 2. Decompress raw DEFLATE stream
        var decompressed = self.decompress_deflate(reader, expected_size)
        return decompressed^