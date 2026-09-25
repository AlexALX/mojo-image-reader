from image_reader.binaryreader import BinaryReader
from image_reader.jpg_reader.bitreader import BitReader
from image_reader.jpg_reader.huffman import HuffmanTable
from image_reader.jpg_reader.idct import IDCT
from image_reader.jpg_reader.decoder import JpgDecoder

# Global compile-time constant for debugging output
comptime DEBUG = False

struct JpegComponent:
    var id: Int
    var h: Int
    var v: Int
    var qt: Int
    var dc_table_id: Int
    var ac_table_id: Int
    var width: Int
    var height: Int

    def __init__(out self: Self):
        self.id = 0
        self.h = 0
        self.v = 0
        self.qt = 0
        self.dc_table_id = 0
        self.ac_table_id = 0
        self.width = 0
        self.height = 0

struct JpegParser:
    var width: Int
    var height: Int
    var precision: Int
    var output_precision: Int
    var level_shift: Int
    var precision_diff: Int
    var max_h: Int
    var max_v: Int
    var mcu_width: Int
    var mcu_height: Int
    var mcu_x: Int
    var mcu_y: Int
    var mcu_count: Int
    var restart_interval: Int
    var component_count: Int

    # Scan parameters and state variables
    var scan_length: Int
    var scan_components_count: Int
    var scan_component_index: Int
    var scan_is_single_component: Bool
    var first_scan_offset: Int
    var scan_state: Int
    var scan_eob_run: Int
    var scan_start: Int
    var scan_mcu: Int
    var restart_pending: Int
    var scan_mcu_count: Int
    var progressive: Bool
    var scan_ss: Int
    var scan_se: Int
    var scan_ah: Int
    var scan_al: Int
    var scan_count: Int
    var coefficients: List[List[List[Int]]]
    var dirty_blocks: Dict[Int, Bool]

    var components: List[JpegComponent]
    var frame_components: List[Int]
    var zigzag_map: List[Int]
    var quantization_tables: List[List[Int]]
    var huffman_dc: List[HuffmanTable]
    var huffman_ac: List[HuffmanTable]

    var bit_reader: BitReader

    def __init__(out self: Self, var bytes: List[UInt8], output_precision: Int = 8):
        var reader = BinaryReader(bytes^)
        self.bit_reader = BitReader(reader^)
        self.width = 0
        self.height = 0
        self.precision = 0
        self.output_precision = output_precision
        self.level_shift = 0
        self.precision_diff = 0
        self.max_h = 0
        self.max_v = 0
        self.mcu_width = 0
        self.mcu_height = 0
        self.mcu_x = 0
        self.mcu_y = 0
        self.mcu_count = 0
        self.restart_interval = 0
        self.component_count = 0

        # Initialize scan and parser state variables
        self.scan_length = 0
        self.scan_components_count = 0
        self.scan_component_index = 0
        self.scan_is_single_component = False
        self.first_scan_offset = 0
        self.scan_state = 0
        self.scan_eob_run = 0
        self.scan_start = 0
        self.scan_mcu = 0
        self.restart_pending = 0
        self.scan_mcu_count = 0
        self.progressive = False
        self.scan_ss = 0
        self.scan_se = 0
        self.scan_ah = 0
        self.scan_al = 0
        self.scan_count = 0
        self.coefficients = List[List[List[Int]]]()
        self.dirty_blocks = Dict[Int, Bool]()

        self.components = List[JpegComponent]()
        for _ in range(4):
            self.components.append(JpegComponent())

        self.frame_components = List[Int]()

        # Populate the JPEG standard zigzag mapping matrix
        self.zigzag_map = [
            0,  1,  8, 16,  9,  2,  3, 10,
            17, 24, 32, 25, 18, 11,  4,  5,
            12, 19, 26, 33, 40, 48, 41, 34,
            27, 20, 13,  6,  7, 14, 21, 28,
            35, 42, 49, 56, 57, 50, 43, 36,
            29, 22, 15, 23, 30, 37, 44, 51,
            58, 59, 52, 45, 38, 31, 39, 46,
            53, 60, 61, 54, 47, 55, 62, 63
        ]

        self.quantization_tables = List[List[Int]]()
        for _ in range(4):
            var empty_table = List[Int]()
            for _ in range(64): empty_table.append(0)
            self.quantization_tables.append(empty_table^)

        # Initialize storage for Huffman DC and AC tables
        self.huffman_dc = List[HuffmanTable]()
        for i in range(4):
            self.huffman_dc.append(HuffmanTable(0, i))

        self.huffman_ac = List[HuffmanTable]()
        for i in range(4):
            self.huffman_ac.append(HuffmanTable(1, i))

    @always_inline
    def jpg_marker_name(mut self, marker: Int) -> String:
        if marker == 0xFFD8: return "SOI"
        elif marker == 0xFFD9: return "EOI"
        elif marker == 0xFFC0: return "SOF0"
        elif marker == 0xFFC1: return "SOF1"
        elif marker == 0xFFC2: return "SOF2"
        elif marker == 0xFFC3: return "SOF3"
        elif marker == 0xFFC5: return "SOF5"
        elif marker == 0xFFC6: return "SOF6"
        elif marker == 0xFFC7: return "SOF7"
        elif marker == 0xFFC9: return "SOF9"
        elif marker == 0xFFCA: return "SOF10"
        elif marker == 0xFFCB: return "SOF11"
        elif marker == 0xFFCD: return "SOF13"
        elif marker == 0xFFCE: return "SOF14"
        elif marker == 0xFFCF: return "SOF15"
        elif marker == 0xFFC8: return "Reserved"
        elif marker == 0xFFC4: return "DHT"
        elif marker == 0xFFCC: return "DAC"
        elif marker == 0xFFDB: return "DQT"
        elif marker == 0xFFDA: return "SOS"
        elif marker == 0xFFDC: return "DNL"
        elif marker == 0xFFDD: return "DRI"
        elif marker == 0xFFDE: return "DHP"
        elif marker == 0xFFDF: return "EXP"
        elif marker == 0xFFFE: return "COM"
        elif marker == 0xFF01: return "TEM"
        elif marker >= 0xFFE0 and marker <= 0xFFEF:
            return "APP" + String(marker - 0xFFE0)
        elif marker >= 0xFFD0 and marker <= 0xFFD7:
            return "RST" + String(marker - 0xFFD0)
        else:
            return "UNKNOWN (0x" + hex(marker, prefix="").upper() + ")"

    def jpg_build_mcu(mut self):
        self.mcu_width = self.max_h * 8
        self.mcu_height = self.max_v * 8
        self.mcu_x = (self.width + self.mcu_width - 1) // self.mcu_width
        self.mcu_y = (self.height + self.mcu_height - 1) // self.mcu_height
        self.mcu_count = self.mcu_x * self.mcu_y

        comptime if DEBUG:
            print("--------------------------------")
            print("MCU Parameters")
            print("--------------------------------")
            print("  MCU Size:", self.mcu_width, "x", self.mcu_height)
            print("  Grid Layout:", self.mcu_x, "x", self.mcu_y)
            print("  Total MCU Count:", self.mcu_count)

    def jpg_parse_dri(mut self):
        ref reader = self.bit_reader.reader

        var _ = reader.u16()
        var interval = reader.u16()
        self.restart_interval = interval
        comptime if DEBUG:
            print("Parsed DRI: Restart Interval =", interval)

    def jpg_parse_sof(mut self, marker: Int) raises:
        ref reader = self.bit_reader.reader

        var _ = reader.u16()
        self.precision = reader.u8()
        self.level_shift = 1 << (self.precision - 1)
        self.precision_diff = self.output_precision - self.precision

        self.height = reader.u16()
        self.width = reader.u16()
        var num_components = reader.u8()
        self.component_count = num_components

        self.progressive = True if marker == 0xC2 else False

        comptime if DEBUG:
            print("Parsed SOF0: Size =", self.width, "x", self.height, "| Components =", num_components)

        for _ in range(num_components):
            var comp_id = reader.u8()
            var sampling = reader.u8()
            var q_table_idx = reader.u8()
            var h_factor = (sampling >> 4) & 0x0F
            var v_factor = sampling & 0x0F

            if h_factor > self.max_h: self.max_h = h_factor
            if v_factor > self.max_v: self.max_v = v_factor

            var comp_width = self.width * h_factor // self.max_h
            var comp_height = self.height * v_factor // self.max_v

            if comp_id < len(self.components):
                self.components[comp_id].id = comp_id
                self.components[comp_id].h = h_factor
                self.components[comp_id].v = v_factor
                self.components[comp_id].qt = q_table_idx
                self.components[comp_id].width = comp_width
                self.components[comp_id].height = comp_height

            comptime if DEBUG:
                print("  Component ID:", comp_id, "H:", h_factor, "V:", v_factor, "Q-Table:", q_table_idx)

        self.jpg_build_mcu()

    def jpg_parse_dqt(mut self):
        ref reader = self.bit_reader.reader

        var length = reader.u16()
        var end_offset = reader.tell() + length - 2

        while reader.tell() < end_offset:
            var info = reader.u8()
            var precision = info >> 4
            var table_id = info & 15

            var normalized_table = List[Int]()
            for _ in range(64): normalized_table.append(0)

            for i in range(64):
                var item_val: Int = reader.u8() if precision == 0 else reader.u16()
                var matrix_pos = self.zigzag_map[i]
                normalized_table[matrix_pos] = item_val

            self.quantization_tables[table_id] = normalized_table^

            comptime if DEBUG:
                print("Parsed Quantization Table DQT ID:", table_id, "(" + ("8" if precision == 0 else "16") + " bit precision)")

    def jpg_parse_dht(mut self) raises:
        ref reader = self.bit_reader.reader

        var length = reader.u16()
        var end_offset = reader.tell() + length - 2

        comptime if DEBUG:
            print("--------------------------------")
            print("DHT (Define Huffman Table)")
            print("--------------------------------")
            print("  Segment Length:", length)

        while reader.tell() < end_offset:
            var info = reader.u8()
            var class_type = info >> 4 # 0 = DC, 1 = AC
            var table_id = info & 0x0F  # Table ID (0-3)

            var ht = HuffmanTable(class_type, table_id)
            var total_symbols = 0

            # Read 16 code length counts
            for i in range(16):
                var count = reader.u8()
                ht.counts[i] = count
                total_symbols += count

            # Read symbols for each length
            for _ in range(total_symbols):
                var symbol = reader.u8()
                ht.symbols.append(symbol)

            # Build Huffman lookup and lookahead structures via huffman module method
            ht.build_huffman()

            # Store table in parser state
            if class_type == 0:
                if table_id < len(self.huffman_dc):
                    self.huffman_dc[table_id] = ht^
            else:
                if table_id < len(self.huffman_ac):
                    self.huffman_ac[table_id] = ht^

            comptime if DEBUG:
                print("  Loaded Huffman Table -> Class:", "DC" if class_type == 0 else "AC", "ID:", table_id, "Symbols:", total_symbols)

    def jpg_parse_sos(mut self) raises -> Bool:
            ref reader = self.bit_reader.reader

            self.scan_length = reader.u16()
            var components = reader.u8()

            self.scan_components_count = components
            self.scan_component_index = 1
            self.scan_is_single_component = (components == 1)
            self.frame_components.clear()

            if self.first_scan_offset == 0:
                self.first_scan_offset = reader.tell()

            comptime if DEBUG:
                print("--------------------------------")
                print("Start Of Scan")
                print("--------------------------------")
                print("Components:", components)

            # Read configuration for each scan component
            for _ in range(components):
                var id = reader.u8()
                var tables = reader.u8()
                var dc_table = tables >> 4
                var ac_table = tables & 0x0F

                for c_idx in range(len(self.components)):
                    if self.components[c_idx].id == id:
                        self.components[c_idx].dc_table_id = dc_table
                        self.components[c_idx].ac_table_id = ac_table
                        break

                comptime if DEBUG:
                    print("Component ID =", id, "DC =", dc_table, "AC =", ac_table)

                self.frame_components.append(id)

            # Read spectral selection and successive approximation parameters
            var ss = reader.u8()
            var se = reader.u8()
            var ah_al = reader.u8()

            self.scan_ss = ss
            self.scan_se = se
            self.scan_ah = ah_al >> 4
            self.scan_al = ah_al & 0x0F
            self.scan_eob_run = 0
            self.scan_start = reader.tell()

            comptime if DEBUG:
                print("Spectral: Ss =", ss, "Se =", se, "Ah =", self.scan_ah, "Al =", self.scan_al)

            self.scan_mcu = 0
            self.restart_pending = 0

            # Determine scan MCU count based on component count and sampling factors
            if self.scan_components_count == 1:
                var target_id = self.frame_components[0]
                var comp_w = 0
                var comp_h = 0

                for c_idx in range(len(self.components)):
                    if self.components[c_idx].id == target_id:
                        comp_w = self.components[c_idx].width
                        comp_h = self.components[c_idx].height
                        break

                # Correct block grid count for single component scan (Width in blocks * Height in blocks)
                var blocks_x = (comp_w + 7) // 8
                var blocks_y = (comp_h + 7) // 8
                self.scan_mcu_count = blocks_x * blocks_y
            else:
                # Interleaved scan (e.g. standard YCbCr Baseline 4:4:4 or 4:2:0)
                self.scan_mcu_count = self.mcu_count

            comptime if DEBUG:
                print("Scan MCU count:", self.scan_mcu_count)

            return True

    def jpg_parse(mut self) raises -> Bool:
        ref reader = self.bit_reader.reader

        if reader.u8() != 0xFF or reader.u8() != 0xD8:
            raise Error("Invalid JPEG SOI marker")

        comptime if DEBUG:
            print("=== MOJO_DEBUG: STARTING PROCEDURAL HEADER PARSE ===")

        while not reader.is_eof():
            var byte = reader.u8()
            if byte == 0xFF:
                var marker = reader.u8()
                if marker == 0x00 or marker == 0xFF:
                    continue

                comptime if DEBUG:
                    print("[" + String(reader.tell() - 2) + "] Found Marker: " + self.jpg_marker_name(0xFF00 | marker))

                if marker == 0xC0 or marker == 0xC1 or marker == 0xC2:
                    self.jpg_parse_sof(marker)
                    continue
                elif marker >= 0xC3 and marker <= 0xCF and marker != 0xC4:
                    raise Error("Unsupported JPEG format (" + self.jpg_marker_name(0xFF00 | marker) + ")")
                elif marker == 0xDD:
                    self.jpg_parse_dri()
                    continue
                elif marker == 0xDB:
                    self.jpg_parse_dqt()
                    continue
                elif marker == 0xC4:
                    self.jpg_parse_dht()
                    continue
                elif marker == 0xDA:
                    if self.jpg_parse_sos():
                        comptime if DEBUG:
                            print("Reached SOS Marker. Intercept Success!")
                            print("=== READY FOR ENTROPY DECODING ===")
                        return True
                else:
                    # Safely skip unhandled segments that specify length (e.g. APPn, COM)
                    if marker != 0xD8 and marker != 0xD9 and not (marker >= 0xD0 and marker <= 0xD7):
                        var length = reader.u16()
                        reader.skip(length - 2)

        return True