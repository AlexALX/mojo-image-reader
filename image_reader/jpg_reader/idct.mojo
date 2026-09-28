from std.math import cos, sqrt, pi

# ==============================================================================
# Algorithm: 2D Floating-Point Fast IDCT (Loeffler / LLM SIMD Butterfly)
# Description: Fully vectorized 8x8 Inverse Discrete Cosine Transform executing
#              8 parallel 1D passes across SIMD lanes (Row-Column decomposition).
# Precision: Single-Precision Float32 (100% ISO/IEC 10918-1 JPEG compliant)
# ==============================================================================

struct IDCT:
    var inv_sqrt2: Float32
    var c1: Float32
    var c2: Float32
    var c3: Float32
    var c5: Float32
    var c6: Float32
    var c7: Float32

    def __init__(out self):
        # Pre-calculate exact 1D IDCT cosine values
        self.inv_sqrt2 = Float32(1.0 / sqrt(2.0))
        self.c1 = Float32(cos(1.0 * pi / 16.0))
        self.c2 = Float32(cos(2.0 * pi / 16.0))
        self.c3 = Float32(cos(3.0 * pi / 16.0))
        self.c5 = Float32(cos(5.0 * pi / 16.0))
        self.c6 = Float32(cos(6.0 * pi / 16.0))
        self.c7 = Float32(cos(7.0 * pi / 16.0))

    # Fully vectorized 8-point 1D IDCT butterfly executing across 8 SIMD lanes simultaneously
    @staticmethod
    def _fast_idct_1d_simd(
        x0: SIMD[DType.float32, 8],
        x1: SIMD[DType.float32, 8],
        x2: SIMD[DType.float32, 8],
        x3: SIMD[DType.float32, 8],
        x4: SIMD[DType.float32, 8],
        x5: SIMD[DType.float32, 8],
        x6: SIMD[DType.float32, 8],
        x7: SIMD[DType.float32, 8],
        inv_sqrt2: Float32,
        c1: Float32,
        c2: Float32,
        c3: Float32,
        c5: Float32,
        c6: Float32,
        c7: Float32,
    ) -> Tuple[
        SIMD[DType.float32, 8],
        SIMD[DType.float32, 8],
        SIMD[DType.float32, 8],
        SIMD[DType.float32, 8],
        SIMD[DType.float32, 8],
        SIMD[DType.float32, 8],
        SIMD[DType.float32, 8],
        SIMD[DType.float32, 8],
    ]:
        # Even components calculation (u = 0, 2, 4, 6)
        var a0 = (x0 + x4) * inv_sqrt2
        var a1 = (x0 - x4) * inv_sqrt2
        var a2 = x2 * c2 + x6 * c6
        var a3 = x2 * c6 - x6 * c2

        var even0 = a0 + a2
        var even1 = a1 + a3
        var even2 = a1 - a3
        var even3 = a0 - a2

        # Odd components calculation (u = 1, 3, 5, 7)
        var odd3 = x1 * c1 + x3 * c3 + x5 * c5 + x7 * c7
        var odd2 = x1 * c3 - x3 * c7 - x5 * c1 - x7 * c5
        var odd1 = x1 * c5 - x3 * c1 + x5 * c7 + x7 * c3
        var odd0 = x1 * c7 - x3 * c5 + x5 * c3 - x7 * c1

        # Symmetric butterfly combination
        return (
            even0 + odd3,
            even1 + odd2,
            even2 + odd1,
            even3 + odd0,
            even3 - odd0,
            even2 - odd1,
            even1 - odd2,
            even0 - odd3,
        )

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

        # Local constant copies for static method call
        var inv_sqrt2_val = self.inv_sqrt2
        var c1_val = self.c1
        var c2_val = self.c2
        var c3_val = self.c3
        var c5_val = self.c5
        var c6_val = self.c6
        var c7_val = self.c7

        # 2. Load the 8 rows of the block
        var r0 = p_block.unsafe_load[width=8](0 * 8)
        var r1 = p_block.unsafe_load[width=8](1 * 8)
        var r2 = p_block.unsafe_load[width=8](2 * 8)
        var r3 = p_block.unsafe_load[width=8](3 * 8)
        var r4 = p_block.unsafe_load[width=8](4 * 8)
        var r5 = p_block.unsafe_load[width=8](5 * 8)
        var r6 = p_block.unsafe_load[width=8](6 * 8)
        var r7 = p_block.unsafe_load[width=8](7 * 8)

        # 3. Construct SIMD column vectors for Row Pass
        var x0 = SIMD[DType.float32, 8](r0[0], r1[0], r2[0], r3[0], r4[0], r5[0], r6[0], r7[0])
        var x1 = SIMD[DType.float32, 8](r0[1], r1[1], r2[1], r3[1], r4[1], r5[1], r6[1], r7[1])
        var x2 = SIMD[DType.float32, 8](r0[2], r1[2], r2[2], r3[2], r4[2], r5[2], r6[2], r7[2])
        var x3 = SIMD[DType.float32, 8](r0[3], r1[3], r2[3], r3[3], r4[3], r5[3], r6[3], r7[3])
        var x4 = SIMD[DType.float32, 8](r0[4], r1[4], r2[4], r3[4], r4[4], r5[4], r6[4], r7[4])
        var x5 = SIMD[DType.float32, 8](r0[5], r1[5], r2[5], r3[5], r4[5], r5[5], r6[5], r7[5])
        var x6 = SIMD[DType.float32, 8](r0[6], r1[6], r2[6], r3[6], r4[6], r5[6], r6[6], r7[6])
        var x7 = SIMD[DType.float32, 8](r0[7], r1[7], r2[7], r3[7], r4[7], r5[7], r6[7], r7[7])

        # Execute 1D IDCT across all 8 rows simultaneously
        var y_res = IDCT._fast_idct_1d_simd(
            x0, x1, x2, x3, x4, x5, x6, x7,
            inv_sqrt2_val, c1_val, c2_val, c3_val, c5_val, c6_val, c7_val
        )
        var y0 = y_res[0]
        var y1 = y_res[1]
        var y2 = y_res[2]
        var y3 = y_res[3]
        var y4 = y_res[4]
        var y5 = y_res[5]
        var y6 = y_res[6]
        var y7 = y_res[7]

        # 4. Construct SIMD row vectors for Column Pass
        var z0 = SIMD[DType.float32, 8](y0[0], y1[0], y2[0], y3[0], y4[0], y5[0], y6[0], y7[0])
        var z1 = SIMD[DType.float32, 8](y0[1], y1[1], y2[1], y3[1], y4[1], y5[1], y6[1], y7[1])
        var z2 = SIMD[DType.float32, 8](y0[2], y1[2], y2[2], y3[2], y4[2], y5[2], y6[2], y7[2])
        var z3 = SIMD[DType.float32, 8](y0[3], y1[3], y2[3], y3[3], y4[3], y5[3], y6[3], y7[3])
        var z4 = SIMD[DType.float32, 8](y0[4], y1[4], y2[4], y3[4], y4[4], y5[4], y6[4], y7[4])
        var z5 = SIMD[DType.float32, 8](y0[5], y1[5], y2[5], y3[5], y4[5], y5[5], y6[5], y7[5])
        var z6 = SIMD[DType.float32, 8](y0[6], y1[6], y2[6], y3[6], y4[6], y5[6], y6[6], y7[6])
        var z7 = SIMD[DType.float32, 8](y0[7], y1[7], y2[7], y3[7], y4[7], y5[7], y6[7], y7[7])

        # Execute 1D IDCT across all 8 columns simultaneously
        var w_res = IDCT._fast_idct_1d_simd(
            z0, z1, z2, z3, z4, z5, z6, z7,
            inv_sqrt2_val, c1_val, c2_val, c3_val, c5_val, c6_val, c7_val
        )
        var w0 = w_res[0]
        var w1 = w_res[1]
        var w2 = w_res[2]
        var w3 = w_res[3]
        var w4 = w_res[4]
        var w5 = w_res[5]
        var w6 = w_res[6]
        var w7 = w_res[7]

        # 5. Final scaling (divide by 4.0), level shift and output store
        var scale = Float32(0.25)
        var out0 = w0 * scale + level_shift
        var out1 = w1 * scale + level_shift
        var out2 = w2 * scale + level_shift
        var out3 = w3 * scale + level_shift
        var out4 = w4 * scale + level_shift
        var out5 = w5 * scale + level_shift
        var out6 = w6 * scale + level_shift
        var out7 = w7 * scale + level_shift

        if output_shift > 0.0:
            out0 = out0 / output_shift
            out1 = out1 / output_shift
            out2 = out2 / output_shift
            out3 = out3 / output_shift
            out4 = out4 / output_shift
            out5 = out5 / output_shift
            out6 = out6 / output_shift
            out7 = out7 / output_shift

        p_block.unsafe_store[width=8](0 * 8, out0)
        p_block.unsafe_store[width=8](1 * 8, out1)
        p_block.unsafe_store[width=8](2 * 8, out2)
        p_block.unsafe_store[width=8](3 * 8, out3)
        p_block.unsafe_store[width=8](4 * 8, out4)
        p_block.unsafe_store[width=8](5 * 8, out5)
        p_block.unsafe_store[width=8](6 * 8, out6)
        p_block.unsafe_store[width=8](7 * 8, out7)

        return True