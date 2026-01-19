#!/usr/bin/env python3
"""
Create a minimal BitLocker test image for srv-ctl tests.

This creates a base64-encoded minimal BitLocker volume that can be decoded
and used for testing BitLocker unlock/mount functionality.

Password: TestBitLocker123

Requirements:
- Run on Windows with BitLocker enabled, or
- Use a Windows VM/WSL2 with BitLocker access
"""

import subprocess
import sys
import os
import base64

def create_bitlocker_image():
    """Create a minimal BitLocker test image."""
    
    image_path = "bitlocker-test.img"
    vhd_path = "bitlocker-test.vhd"
    password = "TestBitLocker123"
    size_mb = 50
    
    print(f"Creating BitLocker test image: {image_path}")
    print(f"Size: {size_mb}MB")
    print(f"Password: {password}")
    print()
    
    # Check if running on Windows
    if sys.platform != "win32":
        print("ERROR: This script must be run on Windows with BitLocker support")
        print()
        print("Steps to create manually:")
        print("1. On Windows, create a VHD:")
        print(f"   diskpart> create vdisk file=C:\\bitlocker-test.vhd maximum={size_mb} type=fixed")
        print("   diskpart> select vdisk file=C:\\bitlocker-test.vhd")
        print("   diskpart> attach vdisk")
        print("   diskpart> create partition primary")
        print("   diskpart> format fs=ntfs quick")
        print("   diskpart> assign letter=X")
        print()
        print("2. Enable BitLocker:")
        print(f"   manage-bde -on X: -Password -pw {password}")
        print()
        print("3. Wait for encryption, then detach and copy the VHD file")
        sys.exit(1)
    
    try:
        # Create VHD using diskpart
        diskpart_create = f"""create vdisk file={os.path.abspath(vhd_path)} maximum={size_mb} type=fixed
select vdisk file={os.path.abspath(vhd_path)}
attach vdisk
create partition primary
format fs=ntfs quick label=BITLOCKTEST
assign letter=X
exit
"""
        
        with open("diskpart_create.txt", "w") as f:
            f.write(diskpart_create)
        
        print("Creating VHD with diskpart...")
        subprocess.run(["diskpart", "/s", "diskpart_create.txt"], check=True)
        
        # Enable BitLocker
        print("Enabling BitLocker...")
        subprocess.run([
            "manage-bde", "-on", "X:",
            "-Password",
            "-UsedSpaceOnly"  # Only encrypt used space for smaller image
        ], input=f"{password}\n{password}\n", text=True, check=True)
        
        # Wait for encryption
        print("Waiting for encryption to complete...")
        while True:
            result = subprocess.run(
                ["manage-bde", "-status", "X:"],
                capture_output=True,
                text=True
            )
            if "100.0%" in result.stdout or "Fully Encrypted" in result.stdout:
                break
            print(".", end="", flush=True)
            import time
            time.sleep(2)
        print("\nEncryption complete!")
        
        # Detach VHD
        diskpart_detach = f"""select vdisk file={os.path.abspath(vhd_path)}
detach vdisk
exit
"""
        with open("diskpart_detach.txt", "w") as f:
            f.write(diskpart_detach)
        
        print("Detaching VHD...")
        subprocess.run(["diskpart", "/s", "diskpart_detach.txt"], check=True)
        
        # Rename to .img
        os.rename(vhd_path, image_path)
        
        print(f"\nBitLocker test image created: {image_path}")
        print(f"Password: {password}")
        print()
        
        # Create base64 version for embedding
        print("Creating base64-encoded version...")
        with open(image_path, "rb") as f:
            data = f.read()
        
        with open(f"{image_path}.base64", "w") as f:
            f.write(base64.b64encode(data).decode())
        
        print(f"Base64 version: {image_path}.base64")
        print(f"Original size: {len(data)} bytes")
        print(f"Base64 size: {len(base64.b64encode(data))} bytes")
        
        # Cleanup temp files
        os.remove("diskpart_create.txt")
        os.remove("diskpart_detach.txt")
        
        print("\nSuccess! Copy the .img file to tests/fixtures/bitlocker/")
        
    except subprocess.CalledProcessError as e:
        print(f"ERROR: {e}")
        sys.exit(1)

if __name__ == "__main__":
    create_bitlocker_image()
