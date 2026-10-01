# Mojo Image Reader Library

A high-performance, native **Mojo v1.0+** library for reading and processing image formats. Designed with a modular architecture for low memory footprint, zero-overhead raw pointer memory access, and seamless interoperability with Python and NumPy.

Currently, the library features a robust **JPEG, PNG, GIF and BMP decoding pipelines** along with **PPM/PFM/PAM** format exporters and **Python/NumPy** interoperability.

## 🚀 Key Features

* **Core JPEG Support**:
  * Baseline (8-bit and 12-bit precision SOF1).
  * Progressive JPEG decoding.
  * Full Chroma Subsampling support: **4:4:4, 4:2:2, 4:2:0, and 4:2:0v**.
  * Grayscale JPEG (1-component) support.
  * Restart Marker support with automatic stream resynchronization.
  * SIMD accelerated pipeline for JPG dequantization.
  * IDCT Core: High-precision 2D Floating-Point IDCT based on the Loeffler (LLM) butterfly algorithm, fully vectorized using 8-lane SIMD.
* **Core BMP Support**
  * Standard `BITMAPINFOHEADER` parser & DIB header handling
  * **Truecolor**: 24-bit RGB and 32-bit RGB/RGBA (`v5`)
  * **High Color Bitfields**: 16-bit (`RGB444`, `RGB555`, `RGB565`)
  * **Indexed / Monochrome**: 8-bit, 4-bit, and 1-bit (with color palette tables)
  * **Compression**: `RLE8` and `RLE4` support
  * Legacy and **OS/2** format support
  * SIMD acceleration for 8 and 32 bit BMP
* **Core PNG Support**:
  * High-performance DEFLATE (ZLIB) decompression & filtering pipeline.
  * **Bit Depth Precision**: 8-bit and 16-bit channel depth support.
  * **Full Color Type Coverage**: Grayscale, Truecolor (RGB), Indexed-color (Palette), Grayscale + Alpha, and Truecolor + Alpha (RGBA).
  * **Adam7 Interlacing**: Full 7-pass interlaced PNG stream decoding.
* **Core GIF Support**:
  * **LZW Decompression**: Fast dictionary-based LZW stream decoding.
  * **Color Tables**: Global (GCT) & Local (LCT) palettes with 32-bit RGBA LUT.
  * **Multi-Frame & Metadata**: Frame extraction, per-frame delays, transparency, Disposal Methods (0–3), and Netscape looping metadata.
  * **Interlacing**: Full 4-pass interlaced GIF decoding.
* **Performance & Memory Optimizations**:
  * Built with raw pointer arithmetic (`Pointer`) to completely bypass bounds-checking and lifetime tracking overhead in hot loops.
  * **SIMD Acceleration**: Hardware-adaptive vectorization applied where applicable across decoder pipelines.
* **Flexible Export & Interoperability**:
  * **PAM Exporter**: Supports 8-bit and 12/16-bit export with alpha channel (`P7`).
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
from image_reader import ImageReader
from std.pathlib import Path

def main() raises:
    # Initialize the reader with desired output precision (e.g., 8 or 12 bits)
    var reader = ImageReader(precision = 8)
    var opt_buffer = reader.readfile("input.jpg")

    if opt_buffer:
        var buffer = opt_buffer.take()
        print("Decoded width:", buffer.width)
        print("Decoded height:", buffer.height)
        print("Decoded channels:", buffer.channels)
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
  - [x] PAM Exporter (8/16-bit), with alpha support
  - [x] NumPy Bridge for seamless Python interoperability
  - [x] Grayscale export support
  - [x] Unified ImageReader struct

- [x] **JPEG Decoder**
  - [x] Baseline (8/12-bit) precision support
  - [x] Grayscale JPEG (1-component) support
  - [x] Progressive JPEG decoding
  - [x] Chroma Subsampling modes (4:4:4, 4:2:2, 4:2:0, 4:2:0v)
  - [x] Restart Marker support
  - [x] Fast IDCT Loeffler (LLM) butterfly algorithm

- [x] **BMP Support**
  - [x] Standard BITMAPINFOHEADER parser & DIB header handling
  - [x] 24-bit RGB
  - [x] 32-bit RGB and RGBA (v5)
  - [x] 8-bit, 4-bit, and 1-bit Monochrome (with color palette tables)
  - [x] 16-bit High Color Bitfields (RGB444, RGB555, RGB565)
  - [x] OS/2 and legacy format support
  - [x] RLE8 and RLE4 compression support
  - [x] SIMD acceleration (8/32 bit BMP)

- [x] **PNG Reader**
  - [x] Core DEFLATE decompression & filtering pipeline
  - [x] Bit depth support: 8-bit and 16-bit precision
  - [x] Color types: Grayscale, Truecolor, Indexed, and Alpha channel (RGBA)
  - [x] Adam7 interlace support

- [x] **GIF Reader**
  - [x] LZW decompression algorithm
  - [x] Global and local color table parsing
  - [x] Frame control: Disposal methods, transparency, and delay parsing
  - [x] Static frame extraction

## 📄 License

Distributed under the Apache License, Version 2.0. See `LICENSE` for more information.