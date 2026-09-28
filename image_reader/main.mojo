from std.sys import argv
from std.pathlib import Path
from image_reader.jpg_reader import JpegReader
from image_reader.buffer import ImageBuffer
from image_reader.output.ppm import PPMCodec
from image_reader.output.pfm import PFMCodec

struct CLIConfig:
    var input_path: String
    var output_path: String
    var precision: Int
    var format: String

    def __init__(out self, input_path: String, output_path: String, precision: Int, output_format: String):
        self.input_path = input_path
        self.output_path = output_path
        self.precision = precision
        self.format = output_format

def parse_cli_args() raises -> CLIConfig:
    """
    Simple, zero-dependency CLI parser for Mojo.
    """

    # Get command-line arguments using the proper Mojo 1.1 standard library
    var args = argv()

    # Check if the user provided the required file path argument
    if len(args) < 2:
        print("Error: Missing file path argument!")
        print("Usage: mojo image_reader/main.mojo <image> [output.ppm] [--precision=12] [--format=pfm]")
        raise "Missing file path argument"

    var input_path = ""
    var output_path = ""
    var precision = 8 # Default precision
    var output_format = ""

    var i = 1
    while i < len(args):
        var arg = args[i]

        if arg.startswith("--precision="):
            var val_str = arg[byte=12:]
            try:
                precision = atol(val_str)
            except:
                precision = 0

            if precision != 8 and precision != 12 and precision != 16:
                raise Error("Unsupported precision value: " + val_str + ".\nSupported values are: 8, 12, 16")
        elif arg.startswith("--format="):
            output_format = arg[byte=9:].lower()

            if output_format!="ppm" and output_format!="pgm" and output_format!="pfm":
                raise Error("Unsupported format: " + output_format + ".\nSupported formats are: ppm, pgm, pfm")

        elif arg.startswith("-"):
            print("Warning: Unknown flag:", arg)
        else:
            # Positional arguments: first is input, second (if any) is output
            if input_path == "":
                input_path = arg
            elif output_path == "":
                output_path = arg

        i += 1

    # automatically detect if not specified
    if output_format=="":
        var length = output_path.byte_length()
        if length >= 4:
            var out_format = output_path[byte=length-4:].lower()
            if out_format==".pgm" or out_format==".pfm":
                output_format = String(out_format[byte=1:])

    if output_format=="":
        output_format = "ppm"

    return CLIConfig(input_path, output_path, precision, output_format)

def main():
    print("Initializing Modular Image Parser Pipeline...")

    var config: CLIConfig
    try:
        config = parse_cli_args()
    except e:
        print(e)
        return

    # Extract the first user-provided argument as the target file path
    # Index 0 is the script/binary name, Index 1 is the first argument
    var file_path_str = config.input_path

    try:
        var path = Path(file_path_str)
        # Verify that the specified file actually exists on disk
        if not path.exists():
            print("Error: File not found at path:", file_path_str)
            return

        var bytes = path.read_bytes()
        var reader = JpegReader(config.precision)
        var opt_buffer = reader.read(bytes^)
        if opt_buffer:
            print("JPEG parsing completed successfully.")

            var output_path: String
            if config.output_path:
                output_path = config.output_path
            else:
                output_path = get_output_path(file_path_str, config.format)

            if config.format=="ppm" or config.format=="pgm":
                PPMCodec.save(opt_buffer.take(), output_path, config.precision, True if config.format=="pgm" else False)
            elif config.format=="pfm":
                PFMCodec.save(opt_buffer.take(), output_path, config.precision)
        else:
            print("JPEG parsing failed.")
    except e:
        print("Execution failed: ", e)

def get_output_path(file_path_str: String, extension: String) -> String:
    """
    Extracts the file name from the path, strips its extension using byte-level slicing,
    and appends extension. Handles both Unix ('/') and Windows ('\\') separators.
    """
    var last_slash = file_path_str.rfind("/")
    var last_backslash = file_path_str.rfind("\\")
    var filename_start = max(last_slash, last_backslash) + 1
    var filename = file_path_str[byte=filename_start:]

    # Strip extension using byte slicing
    var last_dot = filename.rfind(".")
    var stem = filename
    if last_dot != -1:
        stem = filename[byte=0:last_dot]

    # Use byte_length() instead of len() for Mojo v1.1 strings
    if stem.byte_length() > 0:
        return stem + "." + extension
    return "output." + extension