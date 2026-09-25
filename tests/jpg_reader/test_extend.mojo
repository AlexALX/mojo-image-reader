from std.testing import assert_equal
from image_reader.jpg_reader.bitreader import BitReader
from tests.testslib import TestRunner

def test_extend_size1() raises:
    var inputs: List[Int] = [0, 1]
    var expected: List[Int] = [-1, 1]

    for i in range(len(inputs)):
        var res = BitReader.extend(inputs[i], 1)
        assert_equal(res, expected[i])

def test_extend_size2() raises:
    var inputs: List[Int] = [0, 1, 2, 3]
    var expected: List[Int] = [-3, -2, 2, 3]

    for i in range(len(inputs)):
        var res = BitReader.extend(inputs[i], 2)
        assert_equal(res, expected[i])

def test_extend_size3() raises:
    var inputs: List[Int] = [0, 1, 2, 3, 4, 5, 6, 7]
    var expected: List[Int] = [-7, -6, -5, -4, 4, 5, 6, 7]

    for i in range(len(inputs)):
        var res = BitReader.extend(inputs[i], 3)
        assert_equal(res, expected[i])

def main() raises:
    var runner = TestRunner()

    runner.run(test_extend_size1, "EXTEND SIZE1")
    runner.run(test_extend_size2, "EXTEND SIZE2")
    runner.run(test_extend_size3, "EXTEND SIZE3")

    runner.results()