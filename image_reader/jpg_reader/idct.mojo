from std.math import cos, sqrt

struct IDCT:
    var idct_cos: List[Float32]
    var sqrt_05: Float32
    # Pre-allocated workspace buffers to eliminate heap allocations per block
    var temp_buf: List[Float32]
    var row_buf: List[Float32]
    var col_buf: List[Float32]

    def __init__(out self):
        self.sqrt_05 = Float32(sqrt(0.5))
        self.idct_cos = List[Float32]()

        for x in range(8):
            for u in range(8):
                var val = cos((2.0 * Float32(x) + 1.0) * Float32(u) * 3.141592653589793 / 16.0)
                self.idct_cos.append(val)

        # Initialize persistent workspace buffers once
        self.temp_buf = List[Float32]()
        self.temp_buf.resize(64, 0.0)

        self.row_buf = List[Float32]()
        self.row_buf.resize(8, 0.0)

        self.col_buf = List[Float32]()
        self.col_buf.resize(8, 0.0)

    def perform_idct(mut self, mut block: List[Float32], level_shift: Float32, output_shift: Float32) -> Bool:
        """
        Performs 8x8 IDCT using SIMD acceleration and explicit pointer operations.
        """
        var p_block = block.unsafe_ptr()

        # 1. Solid color fast path (DC-only check)
        var is_solid = True
        for i in range(1, 64):
            if abs(p_block.unsafe_offset(i).unsafe_load()) > 0.0001:
                is_solid = False
                break

        if is_solid:
            var dc_val = (p_block.unsafe_offset(0).unsafe_load() / 8.0) + level_shift
            if output_shift > 0.0:
                dc_val = dc_val / output_shift

            for i in range(64):
                p_block.unsafe_offset(i).unsafe_store(dc_val)
            return True

        # Cache pointers to avoid overhead inside tight loops
        var p_temp = self.temp_buf.unsafe_ptr()
        var p_row = self.row_buf.unsafe_ptr()
        var p_col = self.col_buf.unsafe_ptr()
        var p_cos = self.idct_cos.unsafe_ptr()

        # Zero out temp buffer safely
        for i in range(64):
            p_temp.unsafe_offset(i).unsafe_store(0.0)

        # 2. Process Rows (1D IDCT on Rows, dividing sum by 2)
        for y in range(8):
            var row_offset = y * 8

            # Load first element with scaling factor using unsafe operations
            p_row.unsafe_offset(0).unsafe_store(p_block.unsafe_offset(row_offset + 0).unsafe_load() * self.sqrt_05)
            for i in range(1, 8):
                p_row.unsafe_offset(i).unsafe_store(p_block.unsafe_offset(row_offset + i).unsafe_load())

            # Vectorized row processing loop
            for x in range(8):
                var sum_vec = SIMD[DType.float32, 8](0.0)
                var base_idx = x * 8

                var r_vals = p_row.unsafe_load[width=8](0)
                var c_vals = p_cos.unsafe_load[width=8](base_idx)

                sum_vec += r_vals * c_vals
                var sum_val = sum_vec.reduce_add()

                p_temp.unsafe_offset(row_offset + x).unsafe_store(sum_val / 2.0)

        # 3. Process Columns (1D IDCT on Cols)
        for x in range(8):
            p_col.unsafe_offset(0).unsafe_store(p_temp.unsafe_offset(x + 0).unsafe_load() * self.sqrt_05)
            for i in range(1, 8):
                p_col.unsafe_offset(i).unsafe_store(p_temp.unsafe_offset(x + i * 8).unsafe_load())

            # Vectorized column processing loop
            for y in range(8):
                var sum_vec = SIMD[DType.float32, 8](0.0)
                var base_idx = y * 8

                var c_col_vals = p_col.unsafe_load[width=8](0)
                var c_cos_vals = p_cos.unsafe_load[width=8](base_idx)

                sum_vec += c_col_vals * c_cos_vals
                var sum_val = sum_vec.reduce_add()

                var val = (sum_val / 2.0) + level_shift
                if output_shift > 0.0:
                    val = val / output_shift

                p_block.unsafe_offset(y * 8 + x).unsafe_store(val)

        return True