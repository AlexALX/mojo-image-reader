from std.testing import assert_equal, assert_true
from image_reader.jpg_reader.huffman import HuffmanTable
from tests.testslib import TestRunner

def test_huffman_build_simple() raises:
    """Tests Huffman table code generation and lookup structures."""
    var ht = HuffmanTable(0, 0)

    # Set code counts for bit lengths:
    # 1 code (1 bit), 2 codes (2 bits), 1 code (3 bits)
    ht.counts[0] = 1
    ht.counts[1] = 2
    ht.counts[2] = 1

    ht.symbols = [10, 20, 30, 40]

    ht.build_huffman()

    # Primary Lookup Table Assertions
    # Key formula: (bits << 16) + code

    # Symbol 10
    var entry1 = ht.fast_lookup[0]
    assert_equal(entry1 & 0x0F, 1)
    assert_equal(entry1 >> 4, 10)

    # Symbol 20
    var entry2 = ht.fast_lookup[512]
    assert_equal(entry2 & 0x0F, 2)
    assert_equal(entry2 >> 4, 20)

    # Symbol 30
    var entry3 = ht.fast_lookup[768]
    assert_equal(entry3 & 0x0F, 2)
    assert_equal(entry3 >> 4, 30)

    assert_equal(ht.lookup[(3 << 16) + 8], 40)   # Symbol 40

    assert_equal(ht.max_bits, 3)

def main() raises:
    var runner = TestRunner()

    runner.run(test_huffman_build_simple, "HUFFMAN BUILD SIMPLE")

    runner.results()