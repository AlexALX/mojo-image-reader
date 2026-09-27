from std.math import cos, sqrt, pi

struct IDCT:
    var idct_cos: List[Float32]
    var temp_buf: List[Float32]
    var col_buf: List[Float32]
    var mask_05: SIMD[DType.float32, 8] # Pre-calculated mask to replace row_buf

    def __init__(out self):
        var sqrt_05 = Float32(sqrt(0.5))
        # Mask automatically multiplies the first element by sqrt(0.5) and leaves the rest unchanged
        self.mask_05 = SIMD[DType.float32, 8](sqrt_05, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0)
        self.idct_cos = List[Float32](length=64, fill=0.0)

        var p_cos = self.idct_cos.unsafe_ptr()

        var width = 4
        for x in range(8):
            for u_base in range(0, 8, width):
                var u_vec = SIMD[DType.float32, 4](
                    Float32(u_base), Float32(u_base + 1),
                    Float32(u_base + 2), Float32(u_base + 3)
                )
                var x_val = Float32(x)
                var term1 = (2.0 * x_val + 1.0)
                var angles = term1 * u_vec * Float32(pi) / 16.0
                var val_vec = cos(angles)
                p_cos.unsafe_store(x * 8 + u_base, val_vec)

        # Keep List as persistent workspace buffers (they usually stay in L1 cache)
        self.temp_buf = List[Float32](length=64, fill=0.0)
        self.col_buf = List[Float32](length=8, fill=0.0)

    def perform_idct(mut self, mut block: List[Float32], level_shift: Float32, output_shift: Float32) -> Bool:
        var p_block = block.unsafe_ptr()

        # 1. Solid color fast path
        var is_solid = True
        for i in range(1, 64):
            if abs(p_block.unsafe_load(i)) > 0.0001:
                is_solid = False
                break

        if is_solid:
            var dc_val = (p_block.unsafe_load(0) / 8.0) + level_shift
            if output_shift > 0.0:
                dc_val = dc_val / output_shift
            for i in range(64):
                p_block.unsafe_store(i, dc_val)
            return True

        var p_temp = self.temp_buf.unsafe_ptr()
        var p_col = self.col_buf.unsafe_ptr()
        var p_cos = self.idct_cos.unsafe_ptr()

        # 2. Process Rows
        for y in range(8):
            var row_offset = y * 8

            # OPTIMIZATION: Load the entire row as a vector and multiply by the mask.
            # This completely eliminates the need for a temporary row_buf and inner copy loop.
            var r_vals = p_block.unsafe_load[width=8](row_offset) * self.mask_05

            for x in range(8):
                var c_vals = p_cos.unsafe_load[width=8](x * 8)
                var sum_val = (r_vals * c_vals).reduce_add()
                p_temp.unsafe_store(row_offset + x, sum_val / 2.0)

        # 3. Process Columns
        for x in range(8):
            # For columns, we must gather data manually due to memory stride (stride = 8)
            p_col.unsafe_store(0, p_temp.unsafe_load(x) * self.mask_05[0])
            for i in range(1, 8):
                p_col.unsafe_store(i, p_temp.unsafe_load(x + i * 8))

            var c_col_vals = p_col.unsafe_load[width=8](0)

            for y in range(8):
                var c_cos_vals = p_cos.unsafe_load[width=8](y * 8)
                var sum_val = (c_col_vals * c_cos_vals).reduce_add()

                var val = (sum_val / 2.0) + level_shift
                if output_shift > 0.0:
                    val = val / output_shift

                p_block.unsafe_store(y * 8 + x, val)

        return True