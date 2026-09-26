from std.testing import assert_equal
from image_reader.jpg_reader.parser import JpegComponent
from image_reader.jpg_reader.draw import ImageDrawer
from tests.testslib import TestRunner

def test_jpg_assemble_3() raises:
    # 1. Initialize image parameters 16x16 (matching setupAssembleTest)
    var width = 16
    var height = 16
    var mcus_per_row = 1

    # Create components using JpegComponent with correct IDs
    var y_comp = JpegComponent()
    y_comp.id = 1
    y_comp.h = 2
    y_comp.v = 2
    y_comp.width = width
    y_comp.height = height

    var cb_comp = JpegComponent()
    cb_comp.id = 2
    cb_comp.h = 1
    cb_comp.v = 1
    cb_comp.width = width / 2
    cb_comp.height = height / 2

    var cr_comp = JpegComponent()
    cr_comp.id = 3
    cr_comp.h = 1
    cr_comp.v = 1
    cr_comp.width = width / 2
    cr_comp.height = height / 2

    var components = List[JpegComponent]()
    components.append(JpegComponent()) # Dummy placeholder for 0-index
    components.append(y_comp^)
    components.append(cb_comp^)
    components.append(cr_comp^)

    # Initialize plane buffers with zeros based on component dimensions
    var planes_y = List[Float64]()
    var planes_cb = List[Float64]()
    var planes_cr = List[Float64]()

    for _ in range(16 * 16):
        planes_y.append(0.0)
    for _ in range(8 * 8):
        planes_cb.append(0.0)
        planes_cr.append(0.0)

    # 2. Emulate Y blocks (4 blocks for 2x2 MCU, values from 10 to 13)
    for b_idx in range(4):
        var block = List[Float64]()
        var fill_val = Float64(10 + b_idx)
        for _ in range(64):
            block.append(fill_val)

        # Call the real block-to-plane copying method for component ID = 1 (Y)
        ImageDrawer.copy_block_to_plane(
            block, 0, b_idx, components[1], mcus_per_row, planes_y
        )

    # Emulate Cb block (value 50)
    var cb_block = List[Float64]()
    for _ in range(64):
        cb_block.append(50.0)
    ImageDrawer.copy_block_to_plane(
        cb_block, 0, 0, components[2], mcus_per_row, planes_cb
    )

    # Emulate Cr block (value 100)
    var cr_block = List[Float64]()
    for _ in range(64):
        cr_block.append(100.0)
    ImageDrawer.copy_block_to_plane(
        cr_block, 0, 0, components[3], mcus_per_row, planes_cr
    )

    # 3. Assert exact parity with assemble_2.txt / assemble_3.txt stage assertions
    assert_equal(Int(planes_y[0]), 10)     # Y[0]
    assert_equal(Int(planes_y[8]), 11)     # Y[8]
    assert_equal(Int(planes_y[128]), 12)   # Y[128]
    assert_equal(Int(planes_y[136]), 13)   # Y[136]
    assert_equal(Int(planes_cb[0]), 50)    # Cb[0]
    assert_equal(Int(planes_cr[0]), 100)   # Cr[0]

def main() raises:
    var runner = TestRunner()
    runner.run(test_jpg_assemble_3, "JPG ASSEMBLE PARITY TEST (assemble_2.txt / assemble_3.txt)")
    runner.results()