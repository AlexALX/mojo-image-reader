from std.testing import assert_equal
from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader
from image_reader.jpg_reader.huffman import HuffmanTable
from tests.testslib import TestRunner

def test_huffman_read_simple() raises:
    """Tests basic symbol decoding from a single byte stream."""
    var ht = HuffmanTable(0, 0)

    ht.counts[0] = 1
    ht.counts[1] = 2

    ht.symbols = [10, 20, 30]

    ht.build_huffman()

    var bytes_data: List[UInt8] = [0x58]
    var bin_reader = BinaryReader(bytes_data^)
    var bit_reader = BitReader(bin_reader^)

    var res1 = ht.huffman_read(bit_reader)
    assert_equal(res1[0], 10)

    var res2 = ht.huffman_read(bit_reader)
    assert_equal(res2[0], 20)

    var res3 = ht.huffman_read(bit_reader)
    assert_equal(res3[0], 30)

def test_huffman_read_multi() raises:
    """Tests symbol decoding across multiple bytes in the stream."""
    var ht = HuffmanTable(0, 0)

    ht.counts[0] = 1
    ht.counts[1] = 2

    ht.symbols = [10, 20, 30]

    ht.build_huffman()

    var bytes_data: List[UInt8] = [0x5A, 0xC0]
    var bin_reader = BinaryReader(bytes_data^)
    var bit_reader = BitReader(bin_reader^)

    var expected: List[Int] = [10, 20, 30, 10, 20, 30]

    for i in range(len(expected)):
        var res = ht.huffman_read(bit_reader)
        assert_equal(res[0], expected[i])

def test_huffman_read_eof() raises:
    """Tests decoding against an empty bit stream (EOF handling)."""
    var ht = HuffmanTable(0, 0)

    ht.counts[0] = 1

    ht.symbols = [10]

    ht.build_huffman()

    var bytes_data: List[UInt8] = [0xFF, 0xD9]
    var bin_reader = BinaryReader(bytes_data^)
    var bit_reader = BitReader(bin_reader^)

    var res = ht.huffman_read(bit_reader)
    assert_equal(res[0], -1)

def main() raises:
    var runner = TestRunner()

    runner.run(test_huffman_read_simple, "HUFFMAN READ SIMPLE")
    runner.run(test_huffman_read_multi, "HUFFMAN READ MULTI")
    runner.run(test_huffman_read_eof, "HUFFMAN READ EOF")

    runner.results()