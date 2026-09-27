from std.testing import assert_equal
from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader
from image_reader.jpg_reader.huffman import HuffmanTable
from image_reader.jpg_reader.parser import JpegParser
from image_reader.jpg_reader.decoder import JpgDecoder
from tests.testslib import TestRunner

def test_decodeblock_dc() raises:
    """
    Equivalent to test_decodeblock_dc from E2 reference (jpgblock.txt).
    """
    # 1. Сразу передаём входные данные прямо в парсер
    var data = List[UInt8]()
    data.append(0x40)
    var parser = JpegParser(data^)

    # DC Table: 1 symbol of length 1 (symbol value = 2)
    var dc_ht = HuffmanTable(0, 0)
    dc_ht.counts[0] = 1
    dc_ht.symbols.append(2)
    dc_ht.build_huffman()
    parser.huffman_dc[0] = dc_ht^

    # AC Table: 1 symbol of length 1 (symbol value = 0 / EOB)
    var ac_ht = HuffmanTable(1, 0)
    ac_ht.counts[0] = 1
    ac_ht.symbols.append(0)
    ac_ht.build_huffman()
    parser.huffman_ac[0] = ac_ht^

    var decoder = JpgDecoder(parser^)
    ref parser_ref = decoder.parser

    var raw_block = List[Int16](length=64, fill=0)

    var updated_dc = decoder.decode_dc_first(0, 0)
    raw_block[0] = Int16(updated_dc)

    var raw_p = raw_block.unsafe_ptr()

    _ = decoder.decode_ac_first(
        parser_ref.bit_reader,
        parser_ref.scan_eob_run,
        parser_ref.huffman_ac[0],
        parser_ref.zigzag_map,
        1, 63, 0,
        raw_p
    )

    assert_equal(raw_block[0], 2)
    for i in range(1, 64):
        assert_equal(raw_block[i], 0)

def test_decodeblock_ac_only() raises:
    """
    Equivalent to test_decodeblock_ac_only from E2 reference (jpgblock.txt).
    """
    # Data: 0x28
    var data = List[UInt8]()
    data.append(0x28)
    var parser = JpegParser(data^)

    # DC Table: size 0
    var dc_ht = HuffmanTable(0, 0)
    dc_ht.counts[0] = 1
    dc_ht.symbols.append(0)
    dc_ht.build_huffman()
    parser.huffman_dc[0] = dc_ht^

    # AC Table: 0x02 (run 0, size 2) and 0x00 (EOB)
    var ac_ht = HuffmanTable(1, 0)
    ac_ht.counts[0] = 1
    ac_ht.counts[1] = 1
    ac_ht.symbols.append(0x02)
    ac_ht.symbols.append(0x00)
    ac_ht.build_huffman()
    parser.huffman_ac[0] = ac_ht^

    var decoder = JpgDecoder(parser^)
    ref parser_ref = decoder.parser

    var raw_block = List[Int16](length=64, fill=0)

    var updated_dc = decoder.decode_dc_first(0, 0)
    raw_block[0] = Int16(updated_dc)

    var raw_p = raw_block.unsafe_ptr()

    _ = decoder.decode_ac_first(
        parser_ref.bit_reader,
        parser_ref.scan_eob_run,
        parser_ref.huffman_ac[0],
        parser_ref.zigzag_map,
        1, 63, 0,
        raw_p
    )

    assert_equal(raw_block[0], 0)
    assert_equal(raw_block[1], 2)
    for i in range(2, 64):
        assert_equal(raw_block[i], 0)

def test_decodeblock_mixed() raises:
    """
    Equivalent to test_decodeblock_mixed from E2 reference (jpgblock.txt).
    """
    # Data: 0x4E, 0x60
    var data = List[UInt8]()
    data.append(0x4E)
    data.append(0x60)
    var parser = JpegParser(data^)

    # DC Table
    var dc_ht = HuffmanTable(0, 0)
    dc_ht.counts[0] = 1
    dc_ht.symbols.append(2)
    dc_ht.build_huffman()
    parser.huffman_dc[0] = dc_ht^

    # AC Table
    var ac_ht = HuffmanTable(1, 0)
    ac_ht.counts[0] = 1
    ac_ht.counts[1] = 2
    ac_ht.symbols.append(0x02)
    ac_ht.symbols.append(0x21)
    ac_ht.symbols.append(0x00)
    ac_ht.build_huffman()
    parser.huffman_ac[0] = ac_ht^

    var decoder = JpgDecoder(parser^)
    ref parser_ref = decoder.parser

    var raw_block = List[Int16](length=64, fill=0)

    var updated_dc = decoder.decode_dc_first(0, 0)
    raw_block[0] = Int16(updated_dc)

    var raw_p = raw_block.unsafe_ptr()

    _ = decoder.decode_ac_first(
        parser_ref.bit_reader,
        parser_ref.scan_eob_run,
        parser_ref.huffman_ac[0],
        parser_ref.zigzag_map,
        1, 63, 0,
        raw_p
    )

    assert_equal(raw_block[0], 2)
    assert_equal(raw_block[1], 3)
    assert_equal(raw_block[9], -1)

    for i in range(2, 64):
        if i != 9:
            assert_equal(raw_block[i], 0)

def main() raises:
    var runner = TestRunner()
    runner.run(test_decodeblock_dc, "DECODEBLOCK DC")
    runner.run(test_decodeblock_ac_only, "DECODEBLOCK AC ONLY")
    runner.run(test_decodeblock_mixed, "DECODEBLOCK MIXED")
    runner.results()