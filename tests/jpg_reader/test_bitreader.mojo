from std.testing import assert_equal, assert_true
from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader
from tests.testslib import TestRunner

def test_readbyte_normal() raises:
    var bytes_data: List[UInt8] = [0x12, 0x34, 0x56]
    var bin_reader = BinaryReader(bytes_data^)
    var reader = BitReader(bin_reader^)

    assert_equal(reader.read_byte(), 0x12)
    assert_equal(reader.read_byte(), 0x34)
    assert_equal(reader.read_byte(), 0x56)

def test_readbyte_stuffing() raises:
    var bytes_data: List[UInt8] = [0xFF, 0x00, 0x11]
    var bin_reader = BinaryReader(bytes_data^)
    var reader = BitReader(bin_reader^)

    assert_equal(reader.read_byte(), 0xFF)
    assert_equal(reader.read_byte(), 0x11)

def test_readbyte_restart() raises:
    var bytes_data: List[UInt8] = [0xAA, 0xFF, 0xD0, 0xBB]
    var bin_reader = BinaryReader(bytes_data^)
    var reader = BitReader(bin_reader^)

    assert_equal(reader.read_byte(), 0xAA)
    assert_equal(reader.read_byte(), -2)
    assert_equal(reader.restart_marker, 0xD0)
    assert_equal(reader.read_byte(), 0xBB)

def test_readbyte_end() raises:
    var bytes_data: List[UInt8] = [0xAA, 0xFF, 0xD9]
    var bin_reader = BinaryReader(bytes_data^)
    var reader = BitReader(bin_reader^)

    assert_equal(reader.read_byte(), 0xAA)
    assert_equal(reader.read_byte(), -1)
    assert_equal(reader.reader.tell(), 3)
    assert_equal(reader.early_marker, 0xFFD9)

def test_bit_single_byte() raises:
    var bytes_data: List[UInt8] = [0xB2]
    var bin_reader = BinaryReader(bytes_data^)
    var reader = BitReader(bin_reader^)
    var expected: List[Int] = [1, 0, 1, 1, 0, 0, 1, 0]

    for i in range(len(expected)):
        assert_equal(reader.bit(), expected[i])

def test_bit_two_bytes() raises:
    var bytes_data: List[UInt8] = [0xB2, 0x71]
    var bin_reader = BinaryReader(bytes_data^)
    var reader = BitReader(bin_reader^)
    var expected: List[Int] = [
        1, 0, 1, 1, 0, 0, 1, 0,
        0, 1, 1, 1, 0, 0, 0, 1
    ]

    for i in range(len(expected)):
        assert_equal(reader.bit(), expected[i])

def test_bit_stuffing() raises:
    var bytes_data: List[UInt8] = [0xFF, 0x00, 0xAA]
    var bin_reader = BinaryReader(bytes_data^)
    var reader = BitReader(bin_reader^)
    var expected: List[Int] = [
        1, 1, 1, 1, 1, 1, 1, 1,
        1, 0, 1, 0, 1, 0, 1, 0
    ]

    for i in range(len(expected)):
        assert_equal(reader.bit(), expected[i])

def test_bits() raises:
    var bytes1: List[UInt8] = [0xD2]
    var bin_reader1 = BinaryReader(bytes1^)
    var reader1 = BitReader(bin_reader1^)
    assert_equal(reader1.bits(3), 6)
    assert_equal(reader1.bits(5), 18)

    var bytes2: List[UInt8] = [0xF0, 0x0F]
    var bin_reader2 = BinaryReader(bytes2^)
    var reader2 = BitReader(bin_reader2^)
    assert_equal(reader2.bits(12), 3840)
    assert_equal(reader2.bits(4), 15)

def main() raises:
    var runner = TestRunner()

    runner.run(test_readbyte_normal, "READBYTE NORMAL")
    runner.run(test_readbyte_stuffing, "READBYTE STUFFING")
    runner.run(test_readbyte_restart, "READBYTE RESTART")
    runner.run(test_readbyte_end, "READBYTE END")
    runner.run(test_bit_single_byte, "BIT SINGLE BYTE")
    runner.run(test_bit_two_bytes, "BIT TWO BYTES")
    runner.run(test_bit_stuffing, "BIT STUFFING")
    runner.run(test_bits, "BITS")

    runner.results()