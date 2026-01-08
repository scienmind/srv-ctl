# BitLocker Test Fixtures

This directory contains pre-created BitLocker volumes for testing srv-ctl's BitLocker unlock and mount functionality.

## Test Image

**Filename:** `bitlocker-test.img` (50MB)  
**Password:** `TestBitLocker123`  
**Format:** BitLocker-encrypted NTFS volume

## Why Pre-Created?

BitLocker volumes can only be created on Windows systems. Since srv-ctl only needs to **unlock and mount** existing BitLocker volumes (not create them), we use a small pre-created image for testing.

## Creating a New Test Image

If you need to recreate the test image:

### Option 1: Using Windows (Recommended)

1. Run `create-test-image.py` on a Windows system with BitLocker support
2. Copy the resulting `bitlocker-test.img` to this directory
3. Commit the file to the repository

### Option 2: Manual Creation

On Windows with BitLocker:

```powershell
# Create a 50MB VHD
diskpart
  create vdisk file=C:\bitlocker-test.vhd maximum=50 type=fixed
  select vdisk file=C:\bitlocker-test.vhd
  attach vdisk
  create partition primary
  format fs=ntfs quick label=BITLOCKTEST
  assign letter=X
  exit

# Enable BitLocker (you'll be prompted for password)
manage-bde -on X: -Password -UsedSpaceOnly
# When prompted, enter: TestBitLocker123

# Wait for encryption to complete
manage-bde -status X:

# Detach VHD
diskpart
  select vdisk file=C:\bitlocker-test.vhd
  detach vdisk
  exit

# Rename to .img and copy here
```

### Option 3: Without Windows

If a Windows system is not available:

1. Use a Windows VM (VirtualBox, VMware, etc.)
2. Use WSL2 with Windows 11 and BitLocker enabled
3. Use a CI/CD service with Windows runners to generate the fixture

## Testing Without BitLocker

If the BitLocker test image is not available or cryptsetup doesn't support BitLocker on the test system, the tests will automatically skip with an appropriate message.

## Verifying the Image

To verify the test image works:

```bash
# Check cryptsetup can recognize it
sudo cryptsetup luksDump --type bitlk bitlocker-test.img

# Try unlocking it
echo "TestBitLocker123" | sudo cryptsetup open --type bitlk bitlocker-test.img test_bitlocker
sudo cryptsetup close test_bitlocker
```

## File Size

The test image is kept small (~50MB) to minimize repository size while still being large enough for proper BitLocker testing.
