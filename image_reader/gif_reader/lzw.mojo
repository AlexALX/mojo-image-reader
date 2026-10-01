from std.memory import Pointer

struct GifLZWDecoder:
    var prefix: List[Int16]
    var suffix: List[UInt8]
    var stack: List[UInt8]

    def __init__(out self):
        self.prefix = List[Int16](length=4096, fill=-1)
        self.suffix = List[UInt8](length=4096, fill=0)
        self.stack = List[UInt8](length=4096, fill=0)

    @always_inline
    def decompress(mut self, ref lzw_data: List[UInt8], min_code_size: Int, expected_pixels: Int) raises -> List[UInt8]:
        var out_pixels = List[UInt8](unsafe_uninit_length=expected_pixels)

        var out_ptr = out_pixels.unsafe_ptr()
        var prefix_ptr = self.prefix.unsafe_ptr()
        var suffix_ptr = self.suffix.unsafe_ptr()
        var stack_ptr = self.stack.unsafe_ptr()

        var clear_code = 1 << min_code_size
        var eoi_code = clear_code + 1
        var code_size = min_code_size + 1
        var next_code = clear_code + 2
        var code_mask = (1 << code_size) - 1

        # Initialize dictionary
        for i in range(clear_code):
            suffix_ptr.unsafe_offset(i).unsafe_store(UInt8(i))

        var bit_buffer: UInt64 = 0
        var bit_count: Int = 0
        var byte_pos: Int = 0

        var old_code: Int = -1
        var first_char: UInt8 = 0

        # Fast pointer to avoid bounds checking in the hot loop
        var data_ptr = Pointer[UInt8](lzw_data.unsafe_ptr())
        var data_len = len(lzw_data)

        var stack_top = 0
        var out_idx = 0

        while True:
            # Read bits
            if bit_count < code_size:
                while bit_count <= 32 and byte_pos + 4 <= data_len:
                    var val32 = UInt64(data_ptr.unsafe_offset(byte_pos).unsafe_bitcast[UInt32]().unsafe_load())
                    bit_buffer |= val32 << UInt64(bit_count)
                    bit_count += 32
                    byte_pos += 4

                while bit_count < code_size and byte_pos < data_len:
                    bit_buffer |= UInt64(data_ptr.unsafe_offset(byte_pos).unsafe_load()) << UInt64(bit_count)
                    bit_count += 8
                    byte_pos += 1

            if bit_count < code_size:
                break # EOF

            var code = Int(bit_buffer & UInt64(code_mask))
            bit_buffer >>= UInt64(code_size)
            bit_count -= code_size

            if code == clear_code:
                code_size = min_code_size + 1
                code_mask = (1 << code_size) - 1
                next_code = clear_code + 2
                old_code = -1
                continue
            elif code == eoi_code:
                break

            if old_code == -1:
                first_char = suffix_ptr.unsafe_offset(code).unsafe_load()
                out_ptr.unsafe_offset(out_idx).unsafe_store(first_char)
                out_idx += 1
                old_code = code
                continue

            var current_code = code
            if code >= next_code:
                stack_ptr.unsafe_offset(stack_top).unsafe_store(first_char)
                stack_top += 1
                current_code = old_code

            while current_code >= clear_code:
                var char_val = suffix_ptr.unsafe_offset(current_code).unsafe_load()
                stack_ptr.unsafe_offset(stack_top).unsafe_store(char_val)
                stack_top += 1
                current_code = Int(prefix_ptr.unsafe_offset(current_code).unsafe_load())

            first_char = suffix_ptr.unsafe_offset(current_code).unsafe_load()
            stack_ptr.unsafe_offset(stack_top).unsafe_store(first_char)
            stack_top += 1

            while stack_top > 0:
                stack_top -= 1
                var px = stack_ptr.unsafe_offset(stack_top).unsafe_load()
                out_ptr.unsafe_offset(out_idx).unsafe_store(px)
                out_idx += 1

            if next_code < 4096:
                prefix_ptr.unsafe_offset(next_code).unsafe_store(Int16(old_code))
                suffix_ptr.unsafe_offset(next_code).unsafe_store(first_char)
                next_code += 1
                if next_code == (1 << code_size) and code_size < 12:
                    code_size += 1
                    code_mask = (1 << code_size) - 1

            old_code = code

        return out_pixels^