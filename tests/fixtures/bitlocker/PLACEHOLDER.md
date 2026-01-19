# BitLocker Test Fixture Placeholder

The file `bitlocker-test.img` should be placed here for BitLocker tests to run.

**Why this file doesn't exist yet:**
BitLocker volumes can only be created on Windows systems. Since this is optional for testing, the file is not included by default.

**To create the test fixture:**

1. Run `create-test-image.py` on Windows (see README.md)
2. Or manually create a 50MB BitLocker volume on Windows
3. Copy the resulting file here as `bitlocker-test.img`
4. Password must be: `TestBitLocker123`

**Without this file:**
- Integration and system tests will still run
- BitLocker-specific tests will be skipped with a clear message
- All other encryption types (LUKS) will still be tested

See `README.md` in this directory for detailed instructions.
