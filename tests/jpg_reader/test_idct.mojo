from std.testing import assert_almost_equal, assert_equal
from image_reader.jpg_reader.idct import IDCT
from tests.testslib import TestRunner
from std.math import sqrt

def test_idct1d() raises:
    """
    Equivalent to test_idct1d from E2 reference.
    Row[0] = 80, all other 0. Expected result = 80 * sqrt(0.5) / 2 = 28.284271247462.
    """
    var idct = IDCT()
    var x0 = SIMD[DType.float32, 8](80.0)
    var zero = SIMD[DType.float32, 8](0.0)

    var res = IDCT._fast_idct_1d_simd(
        x0, zero, zero, zero, zero, zero, zero, zero,
        idct.inv_sqrt2, idct.c1, idct.c2, idct.c3, idct.c5, idct.c6, idct.c7
    )

    var expected = (80.0 * idct.inv_sqrt2) / 2.0

    assert_almost_equal(res[0][0] / 2.0, expected, atol=0.0001)
    assert_almost_equal(expected, 28.284271247462, atol=0.0001)

def test_idct_dc() raises:
    """
    Equivalent to test_idct from E2 reference.
    Block[0] = 80, level_shift = 128, output_shift = 1.0.
    Expected output for all 64 elements = 138.
    """
    var idct = IDCT()
    var block = List[Float32]()
    for _ in range(64):
        block.append(0.0)

    block[0] = 80.0

    _ = idct.perform_idct(block, 128.0, 1.0)

    for i in range(64):
        assert_equal(Int(block[i]), 138)

def test_idct_min() raises:
    """
    Equivalent to test_idct_minmax("min") from E2 reference.
    Block[0] = -1024, level_shift = 128.0 (retained from previous E2 test execution), output_shift = 1.0.
    Expected output clamped to 0 (-1024 / 8 + 128 = 0).
    """
    var idct = IDCT()
    var block = List[Float32]()
    for _ in range(64):
        block.append(0.0)

    block[0] = -1024.0

    _ = idct.perform_idct(block, 128.0, 1.0)

    for i in range(64):
        assert_equal(Int(block[i]), 0)

def test_idct_max() raises:
    """
    Equivalent to test_idct_minmax("max") from E2 reference.
    Block[0] = 1016, level_shift = 128.0 (retained from previous E2 test execution), output_shift = 1.0.
    Expected output clamped to 255 (1016 / 8 + 128 = 255).
    """
    var idct = IDCT()
    var block = List[Float32]()
    for _ in range(64):
        block.append(0.0)

    block[0] = 1016.0

    _ = idct.perform_idct(block, 128.0, 1.0)

    for i in range(64):
        assert_equal(Int(block[i]), 255)

def main() raises:
    var runner = TestRunner()

    runner.run(test_idct1d, "IDCT 1D")
    runner.run(test_idct_dc, "IDCT DC")
    runner.run(test_idct_min, "IDCT MIN")
    runner.run(test_idct_max, "IDCT MAX")

    runner.results()