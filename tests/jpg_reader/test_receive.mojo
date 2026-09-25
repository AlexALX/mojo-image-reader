from std.testing import assert_equal
from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader
from tests.testslib import TestRunner

def test_receive_zero() raises:
    """
    Equivalent to test_receive_zero from E2 reference (jpgreceive.txt).
    Reading 0 bits should always return 0.
    """
    var data = List[UInt8]()
    var reader = BinaryReader(data^)
    var bit_reader = BitReader(reader^)

    var val = bit_reader.bits(0)
    assert_equal(val, 0)

def test_receive() raises:
    """
    Equivalent to test_receive from E2 reference (jpgreceive.txt).
    Test byte 0xD2 (binary: 11010010):
    - First 3 bits: 110 (binary) = 6 (decimal)
    - Next 5 bits: 10010 (binary) = 18 (decimal).
    """
    var data = List[UInt8]()
    data.append(0xD2)
    var reader = BinaryReader(data^)
    var bit_reader = BitReader(reader^)

    var val1 = bit_reader.bits(3)
    assert_equal(val1, 6)

    var val2 = bit_reader.bits(5)
    assert_equal(val2, 18)

def main() raises:
    var runner = TestRunner()
    runner.run(test_receive_zero, "RECEIVE ZERO")
    runner.run(test_receive, "RECEIVE")
    runner.results()