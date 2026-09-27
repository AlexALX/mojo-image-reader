from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader
from image_reader.jpg_reader.huffman import HuffmanTable
from image_reader.jpg_reader.parser import JpegParser, JpegComponent, DEBUG
from image_reader.jpg_reader.idct import IDCT
from image_reader.jpg_reader.draw import ImageDrawer
from image_reader.buffer import ImageBuffer

struct Quantization:
    @always_inline
    @staticmethod
    def dequantize_block[origin: MutOrigin](p_raw: Pointer[Int16, origin], q_table: List[Int], mut out_block: List[Float32]):
        """
        Dequantizes an 8x8 block in-place using SIMD acceleration and explicit pointers.
        """
        var p_q = q_table.unsafe_ptr()
        var p_out = out_block.unsafe_ptr()

        # Process 64 elements in chunks of 8 using SIMD vectors
        for i in range(0, 64, 8):
            # Load 8 raw integer coefficients and 8 quantization values
            var raw_vec = p_raw.unsafe_offset(i).unsafe_load[width=8]()
            var q_vec = p_q.unsafe_offset(i).unsafe_load[width=8]()

            var dequant_vec = SIMD[DType.float32, 8](raw_vec) * SIMD[DType.float32, 8](q_vec)

            p_out.unsafe_offset(i).unsafe_store(dequant_vec)

struct JpgDecoder:
    var parser: JpegParser
    var mcu_cols: Int
    var mcu_rows: Int
    var max_blocks_per_comp: Int
    var coefficients: List[Int16]

    def __init__(out self, var parser: JpegParser):
        """
        Initializes the JPEG decoder context with stream and dimensions.
        """
        self.mcu_cols = 0
        self.mcu_rows = 0
        self.max_blocks_per_comp = 0
        self.coefficients = List[Int16]()
        self.parser = parser^

    def decode_image(mut self) raises -> ImageBuffer:
        """
        Executes entropy decoding, dequantization, IDCT, and writes the final color image (P6 format).
        Supports both Baseline and Progressive JPEG pipelines.
        """
        comptime if DEBUG:
            print("=== STARTING ENTROPY DECODING & IDCT PIPELINE ===")

        if self.parser.progressive:
            return self.decode_progressive_image()
        else:
            return self.decode_baseline_image()

    def decode_baseline_image(mut self) raises -> ImageBuffer:
        ref parser = self.parser
        var idct_processor = IDCT()

        var prev_dcs = List[Int](length=len(parser.components), fill=0)

        var raw_block = List[Int16](length=64,fill=0)
        var p_raw = raw_block.unsafe_ptr()

        var block_output = List[Float32](length=64,fill=0.0)

        # Initialize planes for Y, Cb, Cr based on component specific dimensions (1-based component indexing)
        var planes_cb = List[Float32]()
        var planes_cr = List[Float32]()

        var comp_y_w = parser.components[1].width
        var comp_y_h = parser.components[1].height
        var planes_y = List[Float32](length=comp_y_w * comp_y_h, fill=0.0)

        if parser.component_count>1:
            var comp_cb_w = parser.components[2].width
            var comp_cb_h = parser.components[2].height
            planes_cb.resize(comp_cb_w * comp_cb_h, 0.0)

            var comp_cr_w = parser.components[3].width
            var comp_cr_h = parser.components[3].height
            planes_cr.resize(comp_cr_w * comp_cr_h, 0.0)

        var mcu_since_restart = 0
        var restart_interval = parser.restart_interval
        var mcus_per_row = parser.mcu_x

        var level_shift = Float32(parser.level_shift)

        # Loop through all Minimum Coded Units (MCUs)
        for mcu_idx in range(parser.mcu_count):

            if restart_interval > 0 and mcu_since_restart >= restart_interval:
                self.parser.bit_reader.align()

                if parser.bit_reader.restart_marker==0:
                    _ = self.parser.bit_reader.read_byte()

                parser.bit_reader.restart_marker = 0

                self.parser.scan_eob_run = 0
                for i in range(len(prev_dcs)):
                    prev_dcs[i] = 0

                mcu_since_restart = 0

            # Iterate through components in the scan
            for scan_comp_idx in range(len(parser.frame_components)):
                var comp_id = parser.frame_components[scan_comp_idx]
                ref comp_info = parser.components[comp_id]

                var qt_id = comp_info.qt
                var dc_tbl_id = comp_info.dc_table_id
                var ac_tbl_id = comp_info.ac_table_id

                var h_factor = comp_info.h
                var v_factor = comp_info.v
                var blocks_per_mcu = h_factor * v_factor

                # Process all blocks belonging to this component within the current MCU
                for block_num in range(blocks_per_mcu):
                    # 1. Decode DC coefficient
                    var updated_dc = self.decode_dc_first(
                        dc_tbl_id, prev_dcs[comp_id]
                    )

                    prev_dcs[comp_id] = updated_dc
                    raw_block[0] = Int16(updated_dc)

                    for i in range(1, 64):
                        raw_block[i] = 0

                    # 2. Decode AC coefficients using zigzag mapping
                    _ = self.decode_ac_first(
                        parser.bit_reader,
                        parser.scan_eob_run,
                        parser.huffman_ac[ac_tbl_id],
                        parser.zigzag_map,
                        1, 63, 0,
                        p_raw
                    )

                    # 3. Dequantize and perform IDCT into a temporary block buffer
                    ref q_table = parser.quantization_tables[qt_id]
                    Quantization.dequantize_block(p_raw, q_table, block_output)

                    # Perform IDCT (level shift / clamping handled during copy or color conversion)
                    _ = idct_processor.perform_idct(block_output, level_shift, 0.0)

                    # 4. Delegate plane placement back to ImageDrawer
                    if comp_id == 1:
                        ImageDrawer.copy_block_to_plane(
                            block_output, mcu_idx, block_num,
                            parser.components[comp_id], mcus_per_row, planes_y
                        )
                    elif comp_id == 2:
                        ImageDrawer.copy_block_to_plane(
                            block_output, mcu_idx, block_num,
                            parser.components[comp_id], mcus_per_row, planes_cb
                        )
                    else:
                        ImageDrawer.copy_block_to_plane(
                            block_output, mcu_idx, block_num,
                            parser.components[comp_id], mcus_per_row, planes_cr
                        )

            mcu_since_restart += 1

        comptime if DEBUG:
            print("=== ENTROPY DECODING & IDCT FINISHED SUCCESSFULLY ===")

        # Final assembly
        return ImageDrawer.assemble_to_buffer(
            self.parser,
            planes_y,
            planes_cb,
            planes_cr
        )

    def decode_progressive_image(mut self) raises -> ImageBuffer:
        """
        Decodes progressive JPEG across multiple scans and builds final planes.
        """
        ref parser = self.parser

        # Initialize global coefficient storage precisely to avoid dynamic allocations during scans
        if len(self.coefficients) == 0:
            var max_blocks = 0
            for comp_id in range(len(parser.components)):
                ref comp_info = self.parser.components[comp_id]
                var h_factor = comp_info.h
                var v_factor = comp_info.v
                var m_blocks = parser.mcu_count * h_factor * v_factor

                # Fallback to dimensions-based block count if MCU count is smaller
                var blocks_x = (comp_info.width + 7) // 8
                var blocks_y = (comp_info.height + 7) // 8
                var total_blocks = blocks_x * blocks_y
                if total_blocks < m_blocks:
                    total_blocks = m_blocks
                if total_blocks > max_blocks:
                    max_blocks = total_blocks

            self.max_blocks_per_comp = max_blocks

            # Pre-allocate all blocks in a single flat array
            var total_size = len(parser.components) * self.max_blocks_per_comp * 64
            self.coefficients.resize(length=total_size, fill=0)

        # Multi-scan progressive processing loop
        while True:
            var ss = parser.scan_ss
            var se = parser.scan_se
            var ah = parser.scan_ah
            var al = parser.scan_al
            var is_dc = (ss == 0 and se == 0)

            var prev_dcs = List[Int](length=len(parser.components), fill=0)

            var is_single = parser.scan_is_single_component
            var scan_mcu_count = parser.scan_mcu_count

            # Scan loop over MCU / blocks
            for scan_mcu in range(scan_mcu_count):
                for comp_idx in range(len(parser.frame_components)):
                    var comp_id = parser.frame_components[comp_idx]
                    ref comp_info = parser.components[comp_id]
                    var dc_tbl_id = comp_info.dc_table_id
                    var ac_tbl_id = comp_info.ac_table_id

                    var h_factor = comp_info.h
                    var v_factor = comp_info.v
                    var blocks_per_mcu = h_factor * v_factor
                    var comp_width = comp_info.width

                    var scan_blocks_per_mcu = 1 if is_single else blocks_per_mcu

                    for block_num in range(scan_blocks_per_mcu):
                        var index: Int

                        if is_single:
                            # single component block mapping
                            var blocks_x = (comp_width + 7) // 8
                            var block_x = scan_mcu % blocks_x
                            var block_y = scan_mcu // blocks_x

                            var target_mcu_x = block_x // h_factor
                            var target_mcu_y = block_y // v_factor
                            var target_mcu = target_mcu_y * parser.mcu_x + target_mcu_x
                            var internal_block = (block_y % v_factor) * h_factor + (block_x % h_factor)

                            index = target_mcu * blocks_per_mcu + internal_block
                        else:
                            # Interleaved scan block mapping
                            var block_y_in_mcu = block_num // h_factor
                            var block_x_in_mcu = block_num % h_factor
                            var internal_offset = block_y_in_mcu * h_factor + block_x_in_mcu
                            index = scan_mcu * blocks_per_mcu + internal_offset

                        # Ensure safe bounds
                        if index < self.max_blocks_per_comp:
                            var block_offset = (comp_id * self.max_blocks_per_comp + index) * 64
                            var p_block = self.coefficients.unsafe_ptr().unsafe_offset(block_offset)

                            if is_dc:
                                if ah == 0:
                                    var updated_dc = self.decode_dc_first(dc_tbl_id, prev_dcs[comp_id])
                                    prev_dcs[comp_id] = updated_dc
                                    p_block.unsafe_store(Int16(updated_dc << al))
                                else:
                                    self.decode_dc_refinement(parser.bit_reader, al, p_block)
                            else:
                                if ah == 0:
                                    _ = self.decode_ac_first(
                                        parser.bit_reader,
                                        parser.scan_eob_run,
                                        parser.huffman_ac[ac_tbl_id],
                                        parser.zigzag_map,
                                        ss, se, al,
                                        p_block
                                    )
                                else:
                                    _ = self.decode_ac_refinement(
                                        parser.bit_reader,
                                        parser.scan_eob_run,
                                        parser.huffman_ac[ac_tbl_id],
                                        parser.zigzag_map,
                                        ss, se, al,
                                        p_block
                                    )

            # Align stream after entropy scan block
            parser.bit_reader.align()

            # Find next marker using robust parser logic
            var found_nested_scan = False
            ref reader = parser.bit_reader.reader

            while not reader.is_eof():

                var b: Int

                if parser.bit_reader.early_marker:
                    b = (parser.bit_reader.early_marker >> 8) & 0xFF
                else:
                    b = reader.u8()

                if b == 0xFF:
                    var marker: Int

                    if parser.bit_reader.early_marker:
                        marker = parser.bit_reader.early_marker & 0xFF
                        parser.bit_reader.early_marker = 0
                    else:
                        marker = reader.u8()

                    # Skip padding 0xFF or 0x00 bytes
                    if marker == 0x00 or marker == 0xFF:
                        continue

                    if marker == 0xD9:
                        break

                    if marker == 0xDA: # Found next SOS marker (0xFFDA)
                        _ = parser.jpg_parse_sos()
                        found_nested_scan = True
                        break
                    elif marker == 0xD9: # EOI (End of Image)
                        break
                    elif marker >= 0xD0 and marker <= 0xD7:
                        continue # RST markers
                    elif marker == 0xC4:
                        _ = parser.jpg_parse_dht()
                    else:
                        # Skip other markers (like APPn, COM, etc.) using their segment length
                        var length = reader.u16()
                        reader.skip(length - 2)

            if not found_nested_scan:
                break

        # Reconstruct planes & IDCT
        var planes_y = List[Float32](length=parser.components[1].width * parser.components[1].height, fill=0.0)
        var planes_cb = List[Float32]()
        var planes_cr = List[Float32]()

        if parser.component_count>1:
            planes_cb.resize(parser.components[2].width * parser.components[2].height,0.0)
            planes_cr.resize(parser.components[3].width * parser.components[3].height,0.0)

        var idct_processor = IDCT()
        var level_shift = Float32(parser.level_shift)
        var mcus_per_row = parser.mcu_x

        var block_output = List[Float32](length=64, fill=0.0)

        var p_coeff_base = self.coefficients.unsafe_ptr()

        for comp_id in range(1, len(parser.components)):
            ref comp_info = parser.components[comp_id]
            var qt_id = comp_info.qt
            ref q_table = parser.quantization_tables[qt_id]

            var h_factor = comp_info.h
            var v_factor = comp_info.v
            var blocks_per_mcu = h_factor * v_factor

            for mcu_idx in range(parser.mcu_count):
                for block_num in range(blocks_per_mcu):
                    var blk_idx = mcu_idx * blocks_per_mcu + block_num
                    if blk_idx >= self.max_blocks_per_comp:
                        continue

                    var block_offset = (comp_id * self.max_blocks_per_comp + blk_idx) * 64
                    var p_block = p_coeff_base.unsafe_offset(block_offset)

                    Quantization.dequantize_block(p_block, q_table, block_output)
                    _ = idct_processor.perform_idct(block_output, level_shift, 0.0)

                    if comp_id == 1:
                        ImageDrawer.copy_block_to_plane(
                            block_output, mcu_idx, block_num,
                            parser.components[comp_id], mcus_per_row, planes_y
                        )
                    elif comp_id == 2:
                        ImageDrawer.copy_block_to_plane(
                            block_output, mcu_idx, block_num,
                            parser.components[comp_id], mcus_per_row, planes_cb
                        )
                    else:
                        ImageDrawer.copy_block_to_plane(
                            block_output, mcu_idx, block_num,
                            parser.components[comp_id], mcus_per_row, planes_cr
                        )

        return ImageDrawer.assemble_to_buffer(self.parser, planes_y, planes_cb, planes_cr)

    def decode_dc_first(mut self, dc_tbl_id: Int, prev_dc: Int) raises -> Int:
        var s = self.parser.huffman_dc[dc_tbl_id].huffman_read(self.parser.bit_reader)

        if s < 0: return prev_dc
        var diff = 0
        if s > 0:
            diff = self.parser.bit_reader.bits(s)
            if diff < 0: return prev_dc
            diff = BitReader.extend(diff, s)

        var dc = prev_dc + diff
        return dc

    @staticmethod
    def decode_dc_refinement[origin: MutOrigin](mut bit_reader: BitReader, al: Int, p_block: Pointer[Int16, origin]) raises:
        var bit = bit_reader.bit()
        if bit > 0:
            var current_val = p_block.unsafe_load()
            p_block.unsafe_store(current_val | Int16(1 << al))

    @staticmethod
    def decode_ac_first[origin: MutOrigin](
        mut bit_reader: BitReader,
        mut scan_eob_run: Int,
        ref acht: HuffmanTable,
        ref zigzag_map: List[Int],
        ss: Int,
        se: Int,
        al: Int,
        p_block: Pointer[Int16, origin]
    ) raises -> Bool:
        if scan_eob_run > 0:
            scan_eob_run -= 1
            return True

        var k = ss
        while k <= se:
            var symbol = acht.huffman_read(bit_reader)

            if symbol < 0: return False
            var run = symbol >> 4
            var size = symbol & 0x0F

            if size == 0:
                if run == 15:
                    k += 16
                    if k > se: break
                    continue
                else:
                    var extra = 0
                    if run > 0:
                        extra = bit_reader.bits(run)
                        if extra < 0: return False
                    scan_eob_run = (1 << run) + extra - 1
                    return True
            else:
                k += run
                if k > se: return False
                var val = bit_reader.bits(size)
                if val < 0: return False
                val = BitReader.extend(val, size)
                p_block.unsafe_offset(zigzag_map[k]).unsafe_store(Int16(val << al))
                k += 1
        return True

    @staticmethod
    @always_inline
    def refine_coefficient[origin: MutOrigin](
        mut bit_reader: BitReader,
        zigzag_idx: Int,
        al: Int,
        p_block: Pointer[Int16, origin]
    ) raises -> Bool:
        var block_val = p_block.unsafe_offset(zigzag_idx).unsafe_load()

        if block_val == 0:
            return True

        var delta = Int16(1 << al)

        if (block_val & delta) != 0:
            return True

        var bit = bit_reader.bit()
        if bit < 0:
            return False

        if bit > 0:
            if block_val > 0:
                p_block.unsafe_offset(zigzag_idx).unsafe_store(block_val + delta)
            else:
                p_block.unsafe_offset(zigzag_idx).unsafe_store(block_val - delta)

        return True

    @staticmethod
    def decode_ac_refinement[origin: MutOrigin](
        mut bit_reader: BitReader,
        mut scan_eob_run: Int,
        ref acht: HuffmanTable,
        ref zigzag_map: List[Int],
        ss: Int,
        se: Int,
        al: Int,
        p_block: Pointer[Int16, origin]
    ) raises -> Bool:
        #
        # Existing EOB run
        #
        if scan_eob_run > 0:
            var k = ss
            while k <= se:
                var zigzag_idx = zigzag_map[k]

                if not JpgDecoder.refine_coefficient(
                    bit_reader,
                    zigzag_idx,
                    al,
                    p_block
                ):
                    return False

                k += 1

            scan_eob_run -= 1
            return True

        var k = ss

        #
        # Main AC refinement loop
        #
        while k <= se:
            var symbol = acht.huffman_read(bit_reader)

            if symbol < 0:
                return False

            var run = symbol >> 4
            var size = symbol & 0x0F

            #
            # EOBRUN / ZRL
            #
            if size == 0:

                #
                # ZRL
                #
                if run == 15:
                    var current_run = 16

                    while k <= se and current_run > 0:
                        var zigzag_idx = zigzag_map[k]

                        if p_block.unsafe_offset(zigzag_idx).unsafe_load() != 0:
                            if not JpgDecoder.refine_coefficient(
                                bit_reader,
                                zigzag_idx,
                                al,
                                p_block
                            ):
                                return False
                        else:
                            current_run -= 1

                        k += 1

                    continue

                #
                # EOB run
                #
                var extra = 0

                if run > 0:
                    extra = bit_reader.bits(run)
                    if extra < 0:
                        return False

                var eob_count = (1 << run) + extra

                while k <= se:
                    var zigzag_idx = zigzag_map[k]

                    if p_block.unsafe_offset(zigzag_idx).unsafe_load() != 0:
                        if not JpgDecoder.refine_coefficient(
                            bit_reader,
                            zigzag_idx,
                            al,
                            p_block
                        ):
                            return False

                    k += 1

                scan_eob_run = eob_count - 1
                return True

            #
            # Normal new coefficient
            #
            var val_bits = bit_reader.bits(size)
            if val_bits < 0:
                return False

            var symbol_val = BitReader.extend(val_bits, size)

            while k <= se:
                var zigzag_idx = zigzag_map[k]

                if p_block.unsafe_offset(zigzag_idx).unsafe_load() != 0:
                    if not JpgDecoder.refine_coefficient(
                        bit_reader,
                        zigzag_idx,
                        al,
                        p_block
                    ):
                        return False

                else:
                    if run == 0:
                        p_block.unsafe_offset(zigzag_idx).unsafe_store(Int16(symbol_val << al))
                        k += 1
                        break # Break inner loop to read next huffman symbol

                    run -= 1

                k += 1

        return True