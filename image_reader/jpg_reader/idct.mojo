from std.math import cos, sqrt

struct IDCT:
    var idct_cos: List[Float64]
    var sqrt_05: Float64

    def __init__(out self):
        self.sqrt_05 = sqrt(0.5)
        self.idct_cos = List[Float64]()

        for x in range(8):
            for u in range(8):
                var val = cos((2.0 * Float64(x) + 1.0) * Float64(u) * 3.141592653589793 / 16.0)
                self.idct_cos.append(val)

    def perform_idct(mut self, mut block: List[Float64], level_shift: Float64, output_shift: Float64) -> Bool:
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

        var temp = List[Float64](capacity=64)
        for _ in range(64):
            temp.append(0.0)

        # 2. Process Rows (1D IDCT on Rows, dividing sum by 2)
        for y in range(8):
            var row_offset = y * 8

            var b = List[Float64](capacity=8)
            b.append(block[row_offset + 0] * self.sqrt_05)
            for i in range(1, 8):
                b.append(block[row_offset + i])

            for x in range(8):
                var sum_val = 0.0
                var base_idx = x * 8
                for u in range(8):
                    sum_val += b[u] * self.idct_cos[base_idx + u]
                temp[row_offset + x] = sum_val / 2.0

        # 3. Process Columns (1D IDCT on Cols)
        for x in range(8):
            var t = List[Float64](capacity=8)
            t.append(temp[x + 0] * self.sqrt_05)
            for i in range(1, 8):
                t.append(temp[x + i * 8])

            for y in range(8):
                var sum_val = 0.0
                var base_idx = y * 8
                for v in range(8):
                    sum_val += t[v] * self.idct_cos[base_idx + v]

                # Full 2D synthesis without extra column division
                var val = (sum_val / 2.0) + level_shift
                if output_shift > 0.0:
                    val = val / output_shift

                block[y * 8 + x] = val

        return True