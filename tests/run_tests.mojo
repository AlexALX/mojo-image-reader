from std.subprocess import run

def main() raises:
    """Main function to execute all project test suites."""
    print("========================================")
    print("       RUNNING ALL JPEG TESTS           ")
    print("========================================")

    # Explicit list of all test files in the project
    var test_files : List[String] = [
        "tests/test_numpy.mojo",
        "tests/jpg_reader/test_idct.mojo",
        "tests/jpg_reader/test_bitreader.mojo",
        "tests/jpg_reader/test_assemble.mojo",
        "tests/jpg_reader/test_huffman.mojo",
        "tests/jpg_reader/test_extend.mojo",
        "tests/jpg_reader/test_idct_step.mojo",
        "tests/jpg_reader/test_ycbcrtorgb.mojo",
        "tests/jpg_reader/test_decoder_block.mojo",
        "tests/jpg_reader/test_huffman_read.mojo",
        "tests/jpg_reader/test_receive.mojo"
    ]

    # Iterate and execute each test file
    for i in range(len(test_files)):
        var file_path = test_files[i]

        print("\n----------------------------------------")
        print("Running: " + file_path)
        print("----------------------------------------")

        var result = run("mojo -I . " + file_path)
        print(result)