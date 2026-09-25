struct TestRunner:
	var passed: Int
	var failed: Int

	def __init__(out self):
		self.passed = 0
		self.failed = 0

	def run(mut self, test_fn: def() thin raises -> None, name: String):
		"""Executes a test function wrapped in a try-catch block using std.testing."""
		try:
			test_fn()
			self.passed += 1
			print("\033[1;32m[PASS]\033[0m", name)
		except e:
			self.failed += 1
			print("\033[1;31m[FAIL]\033[0m", name)
			print("       \033[33mError detail:\033[0m", e)


	def results(self):
		"""Prints the final summary of the test execution."""
		print("----------------------------------------")
		if self.failed == 0:
			print(
				"\033[1;32mALL TESTS PASSED!\033[0m Total:", self.passed,
				"\nPassed:", self.passed,
				"| Failed:", self.failed
			)
		else:
			print(
				"\033[1;31mSOME TESTS FAILED!\033[0m Total:", self.passed + self.failed,
				"\nPassed:", self.passed,
				"| Failed:", self.failed
			)
		print("----------------------------------------")