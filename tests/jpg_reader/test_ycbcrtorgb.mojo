from std.testing import assert_true
from image_reader.buffer import ImageBuffer
from image_reader.jpg_reader.draw import ImageDrawer
from tests.testslib import TestRunner

def assert_near(val: Int, target: Int, tolerance: Int) -> Bool:
    return abs(val - target) <= tolerance

def run_ycbcr_test(y: Float64, cb: Float64, cr: Float64, exp_r: Int, exp_g: Int, exp_b: Int, tol: Int) raises:
    # Test on a 1x1 pixel canvas
    var width = 1
    var height = 1

    var planes_y = List[Float64]()
    planes_y.append(y)

    var planes_cb = List[Float64]()
    planes_cb.append(cb)

    var planes_cr = List[Float64]()
    planes_cr.append(cr)

    var buffer = ImageBuffer(width, height, 3, 8)

    # Process through the actual image drawing/conversion pipeline
    ImageDrawer.process_image[False](
        buffer, width, height,
        planes_y, planes_cb, planes_cr,
        width, height, width, height,
        128.0, 0, 255
    )

    # Extract the resulting RGB values from the buffer
    var r = Int(buffer.data_u8[0])
    var g = Int(buffer.data_u8[1])
    var b = Int(buffer.data_u8[2])

    assert_true(assert_near(r, exp_r, tol), String("R failed: ") + String(r))
    assert_true(assert_near(g, exp_g, tol), String("G failed: ") + String(g))
    assert_true(assert_near(b, exp_b, tol), String("B failed: ") + String(b))

def test_ycbcrtorgb_white() raises:
    # WHITE Test (Y=255, Cb=128, Cr=128 -> RGB 255,255,255, tol=1)
    run_ycbcr_test(255.0, 128.0, 128.0, 255, 255, 255, 1)

def test_ycbcrtorgb_black() raises:
    # BLACK Test (Y=0, Cb=128, Cr=128 -> RGB 0,0,0, tol=1)
    run_ycbcr_test(0.0, 128.0, 128.0, 0, 0, 0, 1)

def test_ycbcrtorgb_red() raises:
    # RED Test (Y=76, Cb=85, Cr=255 -> RGB 255,0,0, tol=3)
    run_ycbcr_test(76.0, 85.0, 255.0, 255, 0, 0, 3)

def main() raises:
    var runner = TestRunner()

    runner.run(test_ycbcrtorgb_white, "YCbCrToRGB WHITE")
    runner.run(test_ycbcrtorgb_black, "YCbCrToRGB BLACK")
    runner.run(test_ycbcrtorgb_red, "YCbCrToRGB RED")

    runner.results()