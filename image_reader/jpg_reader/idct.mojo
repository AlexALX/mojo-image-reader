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
        Performs 8x8 IDCT.
        """
        # 1. Solid color fast path (DC-only)
        var is_solid = True
        for i in range(1, 64):
            if abs(block[i]) > 0.0001:
                is_solid = False
                break

        if is_solid:
            var dc_val = (block[0] / 8.0) + level_shift
            if output_shift > 0.0:
                dc_val = dc_val / output_shift

            for i in range(64):
                block[i] = dc_val
            return True

        # Reuse pre-allocated temp buffer instead of creating a new List per block
        for i in range(64):
            self.temp_buf[i] = 0.0

        # 2. Process Rows (1D IDCT on Rows, dividing sum by 2)
        for y in range(8):
            var row_offset = y * 8

            # Reuse row buffer by direct indexing assignments
            self.row_buf[0] = block[row_offset + 0] * self.sqrt_05
            for i in range(1, 8):
                self.row_buf[i] = block[row_offset + i]

            for x in range(8):
                var sum_val = Float32(0.0)
                var base_idx = x * 8
                for u in range(8):
                    sum_val += self.row_buf[u] * self.idct_cos[base_idx + u]
                self.temp_buf[row_offset + x] = sum_val / 2.0

        # 3. Process Columns (1D IDCT on Cols)
        for x in range(8):
            # Reuse column buffer by direct indexing assignments
            self.col_buf[0] = self.temp_buf[x + 0] * self.sqrt_05
            for i in range(1, 8):
                self.col_buf[i] = self.temp_buf[x + i * 8]

            for y in range(8):
                var sum_val = Float32(0.0)
                var base_idx = y * 8
                for v in range(8):
                    sum_val += self.col_buf[v] * self.idct_cos[base_idx + v]

                # Full 2D synthesis without extra column division
                var val = (sum_val / 2.0) + level_shift
                if output_shift > 0.0:
                    val = val / output_shift

                block[y * 8 + x] = val

        return True