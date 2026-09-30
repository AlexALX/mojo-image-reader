from std.python import Python, PythonObject
from image_reader.buffer import ImageBuffer

struct NumPyBridge:
    """Provides zero-copy interoperability to convert ImageBuffer into a NumPy array."""

    @staticmethod
    def to_ndarray(mut buffer: ImageBuffer, grayscale: Bool = False) -> PythonObject:
        """
        Converts the internal pixel buffer into a numpy.ndarray
        with shape [Height, Width, Channels] without memory copying.
        """
        try:
            var np = Python.import_module("numpy")
            var ctypes = Python.import_module("ctypes")

            var out_channels: Int
            if grayscale or buffer.grayscale:
                out_channels = 2 if buffer.has_alpha else 1
            else:
                out_channels = 4 if buffer.has_alpha else 3

            if buffer.is_16bit:
                # Retrieve raw pointer for 16-bit data
                var data: List[UInt16]
                if grayscale or buffer.grayscale:
                    if buffer.has_alpha:
                        data = buffer.take_grayscale_16bit[with_alpha=True]()
                    else:
                        data = buffer.take_grayscale_16bit()
                else:
                    if buffer.has_alpha:
                        data = buffer.take_rgb_16bit[with_alpha=True]()
                    else:
                        data = buffer.take_rgb_16bit()

                var ptr = data.unsafe_ptr()
                var buffer_type = ctypes.c_uint16 * len(data)
                var c_array = buffer_type.from_address(Int(ptr))

                # Wrap memory buffer into a NumPy array and reshape
                var arr = np.frombuffer(c_array, dtype=np.uint16)
                if out_channels==1:
                    return arr.reshape(buffer.height, buffer.width)
                else:
                    return arr.reshape(buffer.height, buffer.width, out_channels)
            else:
                # Retrieve raw pointer for 8-bit data
                var data: List[UInt8]
                if grayscale or buffer.grayscale:
                    if buffer.has_alpha:
                        data = buffer.take_grayscale[with_alpha=True]()
                    else:
                        data = buffer.take_grayscale()
                else:
                    if buffer.has_alpha:
                        data = buffer.take_rgb[with_alpha=True]()
                    else:
                        data = buffer.take_rgb()

                var ptr = data.unsafe_ptr()
                var buffer_type = ctypes.c_uint8 * len(data)
                var c_array = buffer_type.from_address(Int(ptr))

                # Wrap memory buffer into a NumPy array and reshape
                var arr = np.frombuffer(c_array, dtype=np.uint8)
                if out_channels==1:
                    return arr.reshape(buffer.height, buffer.width)
                else:
                    return arr.reshape(buffer.height, buffer.width, out_channels)

        except e:
            print("Error while converting ImageBuffer to NumPy array:", e)
            return Python.none()