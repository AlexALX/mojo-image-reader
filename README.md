# Mojo Image Reader Library

A high-performance, native **Mojo v1.1+** library for reading and processing image formats. Designed with a modular architecture for low memory footprint, zero-overhead raw pointer memory access, and seamless interoperability with Python and NumPy.

Currently, the library features a robust **JPEG decoding pipeline** along with PPM/PFM format exporters and Python/NumPy interoperability.

## 🚀 Key Features

* **Core JPEG Support**:
  * Baseline (8-bit and 12-bit precision SOF1).
  * Progressive JPEG decoding.
  * Full Chroma Subsampling support: **4:4:4, 4:2:2, 4:2:0, and 4:2:0v**.
  * Grayscale JPEG (1-component) support.
  * Restart Marker support with automatic stream resynchronization.
* **Performance & Memory Optimizations**:
  * Built with raw pointer arithmetic (`Pointer`) to completely bypass bounds-checking and lifetime tracking overhead in hot loops.
  * SIMD accelerated pipeline for dequantization and IDCT blocks.
  * IDCT Core: High-precision 2D Floating-Point IDCT based on the Loeffler (LLM) butterfly algorithm, fully vectorized using 8-lane SIMD.
* **Flexible Export & Interoperability**:
  * **PPM Exporter**: Supports 8-bit and 12/16-bit integer color depths (`P6`).
  * **PGM Exporter**: Supports 8-bit and 12/16-bit grayscale export (`P5`).
  * **PFM Exporter**: 32-bit Float High Dynamic Range (HDR) export (`PF`/`Pf` formats, Little-Endian) with automatic channel detection.
  * **NumPy Bridge**: Direct zero-copy data exchange with the Python NumPy ecosystem.

## 📌 Notes

* **AI-Assisted**: Developed with AI acceleration for structuring and optimization.
* **Lineage**: Architecture and structure directly adapted from Expression 2 (E2) code within the [ALX PC](https://github.com/AlexALX/wiremod_e2_os) project.
* **Purpose**: Built as a portfolio showcase and a useful tool for the Mojo ecosystem.

---

## 📂 Project Structure

```text
.
├── image_reader/
│   ├── buffer.mojo              # Unified image buffer (u8, u16)
│   ├── binaryreader.mojo        # Low-level stream bit/byte reader
│   ├── jpg_reader/              # Core JPEG decoder (parser, huffman, IDCT, color conversion)
│   └── output/                  # Exporters: PPM (8/16-bit), PFM (32-bit HDR) & NumPy bridge
├── examples/                    # Usage examples and integration scripts
└── tests/                       # Unit and integration test suite
```

## 🚀 Quick Start

### 1. CLI Usage
You can run the JPEG reader directly from the command line using `image_reader/main.mojo`. It supports custom precision and output formats (`ppm`, `pgm` or `pfm`):

```bash
mojo image_reader/main.mojo input.jpg output.ppm --precision=8 --format=ppm --grayscale
```

### 2. NumPy & Python Integration

For seamless interoperability with Python ecosystems, you can convert the decoded image buffer into a NumPy `ndarray` and process it (e.g., save as PNG via Pillow). Check out [numpy_save_png.mojo](examples/numpy_save_png.mojo) for a complete reference.

### 3. Direct Programmatic Usage (Getting raw ImageBuffer)

To integrate the decoder into your own pipeline and obtain the raw `ImageBuffer` for custom processing:

```python
from image_reader.jpg_reader import JpegReader
from image_reader.buffer import ImageBuffer
from std.pathlib import Path

def main() raises:
    var path = Path("input.jpg")
    var bytes = path.read_bytes()

    # Initialize the reader with desired output precision (e.g., 8 or 12 bits)
    var reader = JpegReader(precision = 8)
    var opt_buffer = reader.read(bytes^)

    if opt_buffer:
        var buffer = opt_buffer.take()
        print("Decoded width:", buffer.width)
        print("Decoded height:", buffer.height)
        print("Is 16-bit:", buffer.is_16bit)
    else:
        print("Decoding failed.")
```

## 🧪 Running Tests

The project includes a robust test suite powered by a custom test library (`tests/testslib.mojo`) featuring clean, formatted test output, covering IDCT, Huffman decoding, block assembly, and other components.

You can run individual test files using the following command structure:

```bash
mojo -I . tests/jpg_reader/test_idct.mojo
mojo -I . tests/jpg_reader/test_ycbcrtorgb.mojo
mojo -I . tests/jpg_reader/test_assemble.mojo
```

## 🗺️ Roadmap

- [x] **Core & Exporters**
  - [x] Zero-overhead raw pointer memory management
  - [x] Exporters: PPM/PGM (8/16-bit), PFM (32-bit HDR)
  - [x] NumPy Bridge for seamless Python interoperability
  - [x] Grayscale export support

- [x] **JPEG Decoder**
  - [x] Baseline (8/12-bit) precision support
  - [x] Grayscale JPEG (1-component) support
  - [x] Progressive JPEG decoding
  - [x] Chroma Subsampling modes (4:4:4, 4:2:2, 4:2:0, 4:2:0v)
  - [x] Restart Marker support
  - [x] Fast IDCT Loeffler (LLM) butterfly algorithm

- [ ] **BMP Support**
  - [ ] Standard BITMAPINFOHEADER parser & DIB header handling
  - [ ] 24-bit RGB
  - [ ] 8-bit, 4-bit, and 1-bit Monochrome (with color palette tables)
  - [ ] 16-bit High Color Bitfields (RGB444, RGB555, RGB565)
  - [ ] OS/2 and legacy format support
  - [ ] RLE8 and RLE4 compression support

- [ ] **PNG Reader**
  - [ ] Core DEFLATE decompression & filtering pipeline
  - [ ] Bit depth support: 8-bit and 16-bit precision
  - [ ] Color types: Grayscale, Truecolor, Indexed, and Alpha channel (RGBA)
  - [ ] Adam7 interlace support

- [ ] **GIF Reader**
  - [ ] LZW decompression algorithm
  - [ ] Global and local color table parsing
  - [ ] Frame control: Disposal methods, transparency, and delay parsing
  - [ ] Static frame extraction (and full animation support)

## 📄 License

Distributed under the Apache License, Version 2.0. See `LICENSE` for more information.