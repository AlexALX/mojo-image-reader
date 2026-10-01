from std.memory import unsafe_memcpy
from std.sys.info import simd_width_of

@always_inline
def _paeth_predictor(a: Int, b: Int, c: Int) -> Int:
    """Calculates the Paeth predictor value for PNG filter type 4."""
    var p = a + b - c
    var pa = abs(p - a)
    var pb = abs(p - b)
    var pc = abs(p - c)

    if pa <= pb and pa <= pc:
        return a
    elif pb <= pc:
        return b
    else:
        return c

def unfilter_scanlines(
    ref filtered: List[UInt8],
    width: Int,
    height: Int,
    bpp: Int
) raises -> List[UInt8]:
    """Fast scanline unfiltering using memcpy and raw pointers."""
    var line_bytes = width * bpp

    var unfiltered = List[UInt8](unsafe_uninit_length=height * line_bytes)

    var src_p = filtered.unsafe_ptr()
    var dst_p = unfiltered.unsafe_ptr()

    var src_idx = 0
    var dst_idx = 0

    comptime VEC = simd_width_of[DType.uint8]()

    for row in range(height):
        if src_idx >= len(filtered):
            raise Error("PNG stream truncated before unfiltering finished")

        var filter_type = Int(src_p.unsafe_load(src_idx))
        src_idx += 1

        var curr_dst = dst_p.unsafe_offset(dst_idx)
        var curr_src = src_p.unsafe_offset(src_idx)

        if filter_type == 0:
            # Filter Type 0: None -> memcpy
            unsafe_memcpy(dest=curr_dst, src=curr_src, count=line_bytes)

        elif filter_type == 1:
            # Filter Type 1: Sub
            for i in range(bpp):
                curr_dst.unsafe_store(i, curr_src.unsafe_load(i))
            for i in range(bpp, line_bytes):
                var raw = curr_src.unsafe_load(i)
                var left = curr_dst.unsafe_load(i - bpp)
                curr_dst.unsafe_store(i, raw + left)

        elif filter_type == 2:
            # Filter Type 2: Up
            if row == 0:
                unsafe_memcpy(dest=curr_dst, src=curr_src, count=line_bytes)
            else:
                var prev_dst = dst_p.unsafe_offset(dst_idx - line_bytes)
                var i = 0

                while i <= line_bytes - VEC:
                    var raw_vec = curr_src.unsafe_load[width=VEC](i)
                    var above_vec = prev_dst.unsafe_load[width=VEC](i)
                    curr_dst.unsafe_store[width=VEC](i, raw_vec + above_vec)
                    i += VEC

                for j in range(i, line_bytes):
                    var raw = curr_src.unsafe_load(j)
                    var above = prev_dst.unsafe_load(j)
                    curr_dst.unsafe_store(j, raw + above)

        elif filter_type == 3:
            # Filter Type 3: Average
            var prev_dst = dst_p.unsafe_offset(dst_idx - line_bytes) if row > 0 else curr_dst
            for i in range(line_bytes):
                var raw = Int(curr_src.unsafe_load(i))
                var left = Int(curr_dst.unsafe_load(i - bpp)) if i >= bpp else 0
                var above = Int(prev_dst.unsafe_load(i)) if row > 0 else 0
                curr_dst.unsafe_store(i, UInt8((raw + ((left + above) >> 1)) & 0xFF))

        elif filter_type == 4:
            # Filter Type 4: Paeth
            var prev_dst = dst_p.unsafe_offset(dst_idx - line_bytes) if row > 0 else curr_dst
            for i in range(line_bytes):
                var raw = Int(curr_src.unsafe_load(i))
                var left = Int(curr_dst.unsafe_load(i - bpp)) if i >= bpp else 0
                var above = Int(prev_dst.unsafe_load(i)) if row > 0 else 0
                var upper_left = Int(prev_dst.unsafe_load(i - bpp)) if (row > 0 and i >= bpp) else 0

                var predictor = _paeth_predictor(left, above, upper_left)
                curr_dst.unsafe_store(i, UInt8((raw + predictor) & 0xFF))

        else:
            raise Error("Invalid PNG filter type detected")

        src_idx += line_bytes
        dst_idx += line_bytes

    return unfiltered^