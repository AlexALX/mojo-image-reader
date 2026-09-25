from image_reader.buffer import ImageBuffer
from image_reader.output.numpy_bridge import NumPyBridge
from tests.testslib import TestRunner
from std.python import Python

def test_numpy_bridge_8bit() raises:
    """Tests zero-copy NumPy bridge conversion for 8-bit ImageBuffer."""
    var width = 4
    var height = 2
    var channels = 3

    # Initialize 8-bit image buffer
    var buffer = ImageBuffer(width, height, channels, bit_depth=8)

    # Fill buffer with dummy data
    for i in range(width * height * channels):
        buffer.data_u8.append(UInt8(i % 256))

    # Convert to NumPy array via bridge
    var np_arr = NumPyBridge.to_ndarray(buffer)

    # Verify properties using Python
    var py = Python.import_module("builtins")
    var np = Python.import_module("numpy")

    # Check if it is a valid numpy array
    if not py.isinstance(np_arr, np.ndarray):
        raise Error("Result is not a numpy.ndarray")

    # Check shape: should be (height, width, channels) -> (2, 4, 3)
    var shape = np_arr.shape
    if shape[0] != height or shape[1] != width or shape[2] != channels:
        raise Error("Incorrect NumPy array shape")

def test_numpy_bridge_16bit() raises:
    """Tests zero-copy NumPy bridge conversion for 16-bit ImageBuffer."""
    var width = 2
    var height = 2
    var channels = 3

    # Initialize 16-bit image buffer (bit_depth > 8)
    var buffer = ImageBuffer(width, height, channels, bit_depth=12)

    # Fill buffer with dummy 16-bit data
    for i in range(width * height * channels):
        buffer.data_u16.append(UInt16(i * 100))

    # Convert to NumPy array via bridge
    var np_arr = NumPyBridge.to_ndarray(buffer)

    # Verify properties using Python
    var py = Python.import_module("builtins")
    var np = Python.import_module("numpy")

    if not py.isinstance(np_arr, np.ndarray):
        raise Error("Result is not a numpy.ndarray for 16-bit")

    var shape = np_arr.shape
    if shape[0] != height or shape[1] != width or shape[2] != channels:
        raise Error("Incorrect 16-bit NumPy array shape")

def main() raises:
    var runner = TestRunner()

    runner.run(test_numpy_bridge_8bit, "NUMPY BRIDGE 8-BIT")
    runner.run(test_numpy_bridge_16bit, "NUMPY BRIDGE 16-BIT")

    runner.results()