from std.testing import assert_equal
from image_reader.jpg_reader.idct import IDCT
from tests.testslib import TestRunner

def test_idct_step() raises:
    """
    Equivalent to test_idct_step from E2 reference (idct_step_tests.txt).
    Tests a 1D DCT block across 8 columns with specific AC coefficients.
    """
    var idct = IDCT()
    var block = List[Float64]()
    for _ in range(64):
        block.append(0.0)

    # Input values matching E2 test
    block[0] = 321.0
    block[1] = -42.0
    block[2] = 17.0
    block[3] = 8.0
    block[4] = -5.0
    block[5] = 2.0
    block[6] = 1.0
    block[7] = -1.0

    # Build expected values array (8 distinct values repeated for 8 rows)
    var expected_row = List[Int]()
    expected_row.append(164)
    expected_row.append(163)
    expected_row.append(162)
    expected_row.append(162)
    expected_row.append(166)
    expected_row.append(173)
    expected_row.append(176)
    expected_row.append(176)

    var expected = List[Int]()
    for _ in range(8):
        for x in range(8):
            expected.append(expected_row[x])

    # Run IDCT with level_shift = 128.0 and output_shift = 1.0
    _ = idct.perform_idct(block, 128.0, 1.0)

    # Verify all 64 block values match expected array
    for i in range(64):
        var actual = Int(block[i])
        assert_equal(actual, expected[i])

def main() raises:
    var runner = TestRunner()
    runner.run(test_idct_step, "IDCT STEP")
    runner.results()