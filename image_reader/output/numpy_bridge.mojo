from std.python import Python, PythonObject
from image_reader.buffer import ImageBuffer

struct NumPyBridge:
    """Provides zero-copy interoperability to convert ImageBuffer into a NumPy array."""

    @staticmethod
    def to_ndarray(ref buffer: ImageBuffer) -> PythonObject:
        """
        Converts the internal pixel buffer into a numpy.ndarray
        with shape [Height, Width, Channels] without memory copying.
        """
        try:
            var np = Python.import_module("numpy")
            var ctypes = Python.import_module("ctypes")

            if buffer.is_16bit:
                # Retrieve raw pointer for 16-bit data
                var ptr = buffer.data_u16.unsafe_ptr()
                var buffer_type = ctypes.c_uint16 * len(buffer.data_u16)
                var c_array = buffer_type.from_address(Int(ptr))

                # Wrap memory buffer into a NumPy array and reshape
                var arr = np.frombuffer(c_array, dtype=np.uint16)
                if buffer.channels == 1:
                    return arr.reshape(buffer.height, buffer.width)
                else:
                    return arr.reshape(buffer.height, buffer.width, buffer.channels)
            else:
                # Retrieve raw pointer for 8-bit data
                var ptr = buffer.data_u8.unsafe_ptr()
                var buffer_type = ctypes.c_uint8 * len(buffer.data_u8)
                var c_array = buffer_type.from_address(Int(ptr))

                # Wrap memory buffer into a NumPy array and reshape
                var arr = np.frombuffer(c_array, dtype=np.uint8)
                if buffer.channels == 1:
                    return arr.reshape(buffer.height, buffer.width)
                else:
                    return arr.reshape(buffer.height, buffer.width, buffer.channels)

        except e:
            print("Error while converting ImageBuffer to NumPy array:", e)
            return Python.none()