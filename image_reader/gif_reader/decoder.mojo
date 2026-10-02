from image_reader.buffer import ImageBuffer
from image_reader.binaryreader import BinaryReader
from .parser import GifParser
from .lzw import GifLZWDecoder
from .frame import GifFrame
from std.memory import Pointer, unsafe_memcpy
from std.sys.info import simd_width_of

struct GifDecoder:
    var parser: GifParser
    var canvas: List[UInt8] # RGBA 32-bit
    var backup_canvas: List[UInt8]
    var lzw: GifLZWDecoder
    var global_lut: List[UInt32]

    var prev_disposal: Int
    var prev_x: Int
    var prev_y: Int
    var prev_w: Int
    var prev_h: Int

    def __init__(out self, var parser: GifParser) raises:
        self.parser = parser^

        self.prev_disposal = 0
        self.prev_x = 0
        self.prev_y = 0
        self.prev_w = 0
        self.prev_h = 0

        var total_bytes = self.parser.global_width * self.parser.global_height * 4
        self.canvas = List[UInt8](unsafe_uninit_length=total_bytes)
        self.backup_canvas = List[UInt8]()
        self.lzw = GifLZWDecoder()
        self.global_lut = List[UInt32](unsafe_uninit_length=256)

        var lut_ptr = self.global_lut.unsafe_ptr()
        var pal_ptr = self.parser.global_palette.unsafe_ptr()
        var pal_len = len(self.parser.global_palette)

        # Build 32-bit LUT palette (256 UInt32 values)
        for i in range(256):
            if i * 3 + 2 < pal_len:
                var r = UInt32(pal_ptr.unsafe_offset(i * 3).unsafe_load())
                var g = UInt32(pal_ptr.unsafe_offset(i * 3 + 1).unsafe_load())
                var b = UInt32(pal_ptr.unsafe_offset(i * 3 + 2).unsafe_load())
                lut_ptr.unsafe_offset(i).unsafe_store(r | (g << 8) | (b << 16) | 0xFF000000)
            else:
                lut_ptr.unsafe_offset(i).unsafe_store(0)

    # The compile-time parameter [global_palette: Bool] is strictly required to satisfy
    # Mojo's borrow checker. Passing self.parser.global_palette as a 'ref' argument while
    # passing 'self' as 'mut self' triggers a mutable aliasing error.
    @always_inline
    def _draw_pixels[global_palette: Bool](
        mut self,
        ref pixels: List[UInt8],
        ref palette: List[UInt8],
        frame_x: Int, frame_y: Int, frame_w: Int, frame_h: Int,
        trans_flag: Bool, trans_idx: UInt8, interlace: Bool
    ):
        # Build 32-bit LUT palette (256 UInt32 values)
        var lut = List[UInt32](unsafe_uninit_length=256)
        var lut_ptr = lut.unsafe_ptr()

        var global_lut_ptr = self.global_lut.unsafe_ptr()

        # Keep separate branches to respect pointer origins and mutability rules in Mojo's borrow checker
        if not global_palette:
            var pal_ptr = Pointer[UInt8](palette.unsafe_ptr())
            var pal_len = len(palette)

            for i in range(256):
                if i * 3 + 2 < pal_len:
                    var r = UInt32(pal_ptr.unsafe_offset(i * 3).unsafe_load())
                    var g = UInt32(pal_ptr.unsafe_offset(i * 3 + 1).unsafe_load())
                    var b = UInt32(pal_ptr.unsafe_offset(i * 3 + 2).unsafe_load())
                    lut_ptr.unsafe_offset(i).unsafe_store(r | (g << 8) | (b << 16) | 0xFF000000)
                else:
                    lut_ptr.unsafe_offset(i).unsafe_store(0)

        var canvas_32 = self.canvas.unsafe_ptr().unsafe_bitcast[UInt32]()
        var src_ptr = pixels.unsafe_ptr()

        var global_w = self.parser.global_width
        var global_h = self.parser.global_height

        # Calculate valid width for rendering
        var valid_w = 0
        if frame_x < global_w:
            valid_w = min(frame_w, global_w - frame_x)

        var idx = 0
        var pass_step = 8
        var pass_y = 0
        var pass_id = 0

        comptime simd_w32 = simd_width_of[DType.uint32]()

        for y in range(frame_h):
            var draw_y = y
            if interlace:
                draw_y = pass_y
                pass_y += pass_step
                if pass_y >= frame_h:
                    pass_id += 1
                    if pass_id == 1: pass_y = 4; pass_step = 8
                    elif pass_id == 2: pass_y = 2; pass_step = 4
                    elif pass_id == 3: pass_y = 1; pass_step = 2

            var canvas_y = frame_y + draw_y

            # Skip row if canvas_y is out of vertical bounds
            if canvas_y >= global_h or canvas_y < 0:
                idx += frame_w
                continue

            var row_offset = canvas_y * global_w + frame_x

            if trans_flag:
                # Scalar path for transparent pixels
                for x in range(valid_w):
                    var color_idx = src_ptr.unsafe_offset(idx).unsafe_load()
                    idx += 1
                    if color_idx != trans_idx:
                        var color: UInt32
                        if global_palette:
                            color = global_lut_ptr.unsafe_offset(Int(color_idx)).unsafe_load()
                        else:
                            color = lut_ptr.unsafe_offset(Int(color_idx)).unsafe_load()
                        canvas_32.unsafe_offset(row_offset + x).unsafe_store(color)
            else:
                # SIMD Gather path for non-transparent pixels
                var vec_valid_w = (valid_w // simd_w32) * simd_w32
                for x in range(0, vec_valid_w, simd_w32):
                    var indices = src_ptr.unsafe_offset(idx + x).unsafe_load[width=simd_w32]()
                    var offset_vec = indices.cast[DType.uint8]()
                    var colors: SIMD[DType.uint32, simd_w32]
                    if global_palette:
                        colors = global_lut_ptr.unsafe_gather(offset_vec)
                    else:
                        colors = lut_ptr.unsafe_gather(offset_vec)
                    canvas_32.unsafe_offset(row_offset + x).unsafe_store[width=simd_w32](colors)

                idx += vec_valid_w

                # Scalar tail loop
                for x in range(vec_valid_w, valid_w):
                    var color_idx = src_ptr.unsafe_offset(idx).unsafe_load()
                    idx += 1

                    var color: UInt32
                    if global_palette:
                        color = global_lut_ptr.unsafe_offset(Int(color_idx)).unsafe_load()
                    else:
                        color = lut_ptr.unsafe_offset(Int(color_idx)).unsafe_load()
                    canvas_32.unsafe_offset(row_offset + x).unsafe_store(color)

            # Skip pixels exceeding right boundary
            idx += (frame_w - valid_w)

    def decode_frame(mut self, mut current_disposal: Int, mut current_delay: Int, trans_flag: Bool, trans_idx: UInt8) raises -> GifFrame:
        var frame_x = Int(self.parser.reader.u16_le())
        var frame_y = Int(self.parser.reader.u16_le())
        var frame_w = Int(self.parser.reader.u16_le())
        var frame_h = Int(self.parser.reader.u16_le())
        var packed = self.parser.reader.u8()

        var has_lct = (packed & 0x80) != 0
        var interlace = (packed & 0x40) != 0

        var local_palette = List[UInt8]()
        if has_lct:
            var lct_bytes = (1 << ((packed & 0x07) + 1)) * 3
            local_palette.resize(unsafe_uninit_length=lct_bytes)
            unsafe_memcpy(dest=local_palette.unsafe_ptr(), src=self.parser.reader.ptr, count=lct_bytes)
            self.parser.reader.skip(lct_bytes)

        var min_code_size = Int(self.parser.reader.u8())
        var lzw_data = self.parser.read_sub_blocks()

        # Decompress LZW pixels
        var pixels = self.lzw.decompress(lzw_data^, min_code_size, frame_w * frame_h)

        self.prev_x = frame_x
        self.prev_y = frame_y
        self.prev_w = frame_w
        self.prev_h = frame_h

        # Backup canvas without unnecessary reallocations
        if current_disposal == 3:
            self.backup_canvas.resize(unsafe_uninit_length=len(self.canvas))
            unsafe_memcpy(dest=self.backup_canvas.unsafe_ptr(), src=self.canvas.unsafe_ptr(), count=len(self.canvas))

        # Draw to canvas
        if has_lct:
            self._draw_pixels[False](pixels, local_palette, frame_x, frame_y, frame_w, frame_h, trans_flag, trans_idx, interlace)
        else:
            self._draw_pixels[True](pixels, local_palette, frame_x, frame_y, frame_w, frame_h, trans_flag, trans_idx, interlace)

        # Copy canvas to ImageBuffer using SIMD
        var frame_buffer = ImageBuffer(self.parser.global_width, self.parser.global_height, 4, 8)

        if self.parser.precision == 8:
            frame_buffer.data_u8 = self.canvas.copy()
        else:
            var total_elements = len(self.canvas)
            frame_buffer.data_u16.resize(unsafe_uninit_length=total_elements)

            var dst_ptr = frame_buffer.data_u16.unsafe_ptr()
            var src_ptr = self.canvas.unsafe_ptr()

            comptime simd_w8 = simd_width_of[DType.uint8]()
            var vec_len = (total_elements // simd_w8) * simd_w8

            # Vectorized precision conversion loop
            if self.parser.precision == 16:
                for i in range(0, vec_len, simd_w8):
                    var v8 = src_ptr.unsafe_offset(i).unsafe_load[width=simd_w8]()
                    var v16 = v8.cast[DType.uint16]() << 8
                    dst_ptr.unsafe_offset(i).unsafe_store[width=simd_w8](v16)

                for i in range(vec_len, total_elements):
                    var val = UInt16(src_ptr.unsafe_offset(i).unsafe_load())
                    dst_ptr.unsafe_offset(i).unsafe_store(val << 8)
            else:
                var scale_shift = UInt16(self.parser.precision - 8)
                for i in range(0, vec_len, simd_w8):
                    var v8 = src_ptr.unsafe_offset(i).unsafe_load[width=simd_w8]()
                    var v16 = v8.cast[DType.uint16]() << scale_shift
                    dst_ptr.unsafe_offset(i).unsafe_store[width=simd_w8](v16)

                for i in range(vec_len, total_elements):
                    var val = UInt16(src_ptr.unsafe_offset(i).unsafe_load())
                    dst_ptr.unsafe_offset(i).unsafe_store(val << scale_shift)

        return GifFrame(frame_buffer^, current_delay, current_disposal)

    def decode_frames[only_first: Bool = True](mut self) raises -> List[GifFrame]:
        var frames = List[GifFrame]()

        var current_delay = 0
        var current_disposal = 0
        var trans_flag = False
        var trans_idx: UInt8 = 0

        # Initialize canvas with background color using SIMD vector stores
        var bg_color: UInt32 = 0
        var bg_idx = Int(self.parser.background_index)
        if len(self.parser.global_palette) > bg_idx * 3 + 2:
            var bg_r = UInt32(self.parser.global_palette[bg_idx * 3])
            var bg_g = UInt32(self.parser.global_palette[bg_idx * 3 + 1])
            var bg_b = UInt32(self.parser.global_palette[bg_idx * 3 + 2])
            bg_color = bg_r | (bg_g << 8) | (bg_b << 16)

        var c_ptr32 = self.canvas.unsafe_ptr().unsafe_bitcast[UInt32]()
        var total_pixels = self.parser.global_width * self.parser.global_height

        comptime simd_w32 = simd_width_of[DType.uint32]()
        var bg_vec = SIMD[DType.uint32, simd_w32](bg_color)
        var vec_pixels = (total_pixels // simd_w32) * simd_w32

        for i in range(0, vec_pixels, simd_w32):
            c_ptr32.unsafe_offset(i).unsafe_store[width=simd_w32](bg_vec)

        for i in range(vec_pixels, total_pixels):
            c_ptr32.unsafe_offset(i).unsafe_store(bg_color)

        while not self.parser.reader.is_eof():
            var block_type = self.parser.reader.u8()

            if block_type == 0x3B: # Trailer
                break

            elif block_type == 0x21: # Extension
                var ext_type = self.parser.reader.u8()
                if ext_type == 0xF9: # Graphic Control Extension
                    _ = self.parser.reader.u8()
                    var packed = self.parser.reader.u8()
                    current_disposal = Int((packed >> 2) & 0x07)
                    trans_flag = (packed & 0x01) != 0
                    current_delay = Int(self.parser.reader.u16_le()) * 10
                    trans_idx = self.parser.reader.u8_uint()
                    _ = self.parser.reader.u8()
                elif ext_type == 0xFF: # Application (Loop count)
                    var size = Int(self.parser.reader.u8_uint())
                    var is_netscape = False

                    if size == 11:
                        var char0 = self.parser.reader.u8()
                        var char1 = self.parser.reader.u8()
                        self.parser.reader.skip(9)

                        if char0 == 0x4E and char1 == 0x45:
                            is_netscape = True
                    else:
                        self.parser.reader.skip(size)

                    if is_netscape:
                        _ = self.parser.reader.u8()
                        _ = self.parser.reader.u8()
                        self.parser.loop_count = self.parser.reader.u16_le()
                        _ = self.parser.reader.u8()
                    else:
                        _ = self.parser.read_sub_blocks()
                else:
                    _ = self.parser.read_sub_blocks()

            elif block_type == 0x2C: # Image Descriptor

                # Disposal Method 2 (Restore to background) using SIMD
                if self.prev_disposal == 2:
                    var clear_32 = self.canvas.unsafe_ptr().unsafe_bitcast[UInt32]()
                    var gw = self.parser.global_width
                    var gh = self.parser.global_height

                    var bg_color: UInt32 = 0
                    var bg_idx = Int(self.parser.background_index)
                    if len(self.parser.global_palette) > bg_idx * 3 + 2:
                        if not (trans_flag and UInt8(bg_idx) == trans_idx):
                            var bg_r = UInt32(self.parser.global_palette[bg_idx * 3])
                            var bg_g = UInt32(self.parser.global_palette[bg_idx * 3 + 1])
                            var bg_b = UInt32(self.parser.global_palette[bg_idx * 3 + 2])
                            bg_color = bg_r | (bg_g << 8) | (bg_b << 16)

                    var start_y = min(self.prev_y, gh)
                    var end_y = min(self.prev_y + self.prev_h, gh)
                    var valid_w = 0
                    if self.prev_x < gw:
                        valid_w = min(self.prev_w, gw - self.prev_x)

                    comptime simd_w32 = simd_width_of[DType.uint32]()
                    var bg_vec = SIMD[DType.uint32, simd_w32](bg_color)
                    var vec_w = (valid_w // simd_w32) * simd_w32

                    for cy in range(start_y, end_y):
                        var row_offset = cy * gw + self.prev_x
                        for cx in range(0, vec_w, simd_w32):
                            clear_32.unsafe_offset(row_offset + cx).unsafe_store[width=simd_w32](bg_vec)
                        for cx in range(vec_w, valid_w):
                            clear_32.unsafe_offset(row_offset + cx).unsafe_store(bg_color)

                elif self.prev_disposal == 3: # Restore from backup
                    unsafe_memcpy(dest=self.canvas.unsafe_ptr(), src=self.backup_canvas.unsafe_ptr(), count=len(self.canvas))

                var frame = self.decode_frame(current_disposal, current_delay, trans_flag, trans_idx)
                frames.append(frame^)

                self.prev_disposal = current_disposal

                current_disposal = 1
                trans_flag = False
                trans_idx = 0

                if only_first:
                    break

        return frames^