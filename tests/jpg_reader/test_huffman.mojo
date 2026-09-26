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

    # Primary Lookup Table Assertions (E2 Parity: stores symbol + 1)
    # Key formula: (bits << 16) + code
    assert_equal(ht.lookup[(1 << 16) + 0], 11)   # Symbol 10 + 1
    assert_equal(ht.lookup[(2 << 16) + 2], 21)   # Symbol 20 + 1
    assert_equal(ht.lookup[(2 << 16) + 3], 31)   # Symbol 30 + 1
    assert_equal(ht.lookup[(3 << 16) + 8], 41)   # Symbol 40 + 1

    assert_equal(ht.max_bits, 3)

def main() raises:
    var runner = TestRunner()

    runner.run(test_huffman_build_simple, "HUFFMAN BUILD SIMPLE")

    runner.results()