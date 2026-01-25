# srv-ctl

Small utility to manage home server services dependent on encrypted storage.

## Features

- **Multiple Syncthing Services**: Supports running 2 parallel Syncthing services with different users
- **Multiple Storage Devices**: Supports 5 storage devices (1 primary data + 4 paired storage devices)
- **Dual Encryption Support**: Supports both LUKS and BitLocker encryption formats
- **LVM Support**: Optional LVM (Logical Volume Manager) support for device management
- **Network Storage**: CIFS/SMB and NFS network share mounting support
- **Service Management**: Start/stop systemd services with error handling and idempotency
- **Configuration Validation**: Built-in validation to verify setup before execution

## Requirements

- **cryptsetup**: Version 2.4.0+ (supports both LUKS and BitLocker encryption)
   - Note: cryptsetup >=2.4.0 is only available in Debian 12+ and Ubuntu 22.04+.
   - BitLocker support and all system/integration tests require these or newer OS versions.
- **lvm2**: Required only if using LVM volumes
- **GNU coreutils**: Required for version comparison (`sort -V`)
- **systemd**: Required for service management
- **Root privileges**: Script must be run as root for start/stop/unlock operations

## Configuration

Copy `config.local.template` to `config.local` and customize:

```bash
cp config.local.template config.local
```

### Service Configuration

```bash
# Syncthing users (set to "none" to disable)
readonly ST_USER_1="alice"
readonly ST_USER_2="bob"

# Service names (constructed automatically)
readonly ST_SERVICE_1="syncthing@${ST_USER_1}.service"
readonly ST_SERVICE_2="syncthing@${ST_USER_2}.service"

# Additional services (set to "none" to disable)
readonly DOCKER_SERVICE="docker.service"  # Manage Docker service
readonly SAMBA_SERVICE="smbd.service"     # Manage Samba service (for network shares)
```

All configured services are started when running `srv-ctl.sh start` and stopped when running `srv-ctl.sh stop`.

### Storage Device Configuration

Each storage device supports:

- **Mount Point**: Local directory under `/mnt/`
- **Device Mapper**: Name for the unlocked device
- **LVM Support**: Optional logical volume management
- **Encryption Type**: Either `luks` or `bitlocker`
- **Key Files**: Optional for automated unlocking
- **Ownership**: Optional user/group for mount point
- **Mount Options**: Additional filesystem mount options

Example for a BitLocker device (all fields shown):

```bash
readonly STORAGE_2A_MOUNT="storage2a"           # Mount point under /mnt/
readonly STORAGE_2A_MAPPER="storage2a-data"     # Device mapper name
readonly STORAGE_2A_LVM_NAME="none"             # LVM volume name ("none" to disable)
readonly STORAGE_2A_LVM_GROUP="vg-srv"          # LVM group (used if LVM enabled)
readonly STORAGE_2A_UUID="your-device-uuid"     # Device UUID (find with: sudo blkid)
readonly STORAGE_2A_KEY_FILE="/path/to/key"     # Key file path ("none" for interactive)
readonly STORAGE_2A_ENCRYPTION_TYPE="bitlocker" # "luks" or "bitlocker"
readonly STORAGE_2A_OWNER_USER="sync_srv"       # Mount ownership user ("none" to skip)
readonly STORAGE_2A_OWNER_GROUP="sync_srv"      # Mount ownership group ("none" to skip)
readonly STORAGE_2A_MOUNT_OPTIONS="defaults"    # Additional mount options
```

> **Note**: See `config.local.template` for the complete list of all configurable devices and their default values.

## Usage

```bash
sudo ./srv-ctl.sh start               # Start all services and mount devices
sudo ./srv-ctl.sh stop                # Stop all services and unmount devices
sudo ./srv-ctl.sh unlock-only         # Only unlock and mount devices
sudo ./srv-ctl.sh stop-services-only  # Only stop services
./srv-ctl.sh validate-config          # Validate configuration (no root required)
./srv-ctl.sh help                     # Show help message
```

**Note**: The `validate-config` command does not require root privileges unless key files have restricted permissions.

## Migration from Old Format

If you have an existing `config.local` from an earlier version, you'll need to update it to the new format. The main changes:

1. **Service Configuration**:
   - `ST_SERVICE` → `ST_SERVICE_1` and `ST_SERVICE_2`
   - `ST_USER` → `ST_USER_1` and `ST_USER_2`

2. **Storage Device Configuration**:
   - `ACTIVE_DATA_*` → `PRIMARY_DATA_*`
   - `STORAGE_DATA_*` → `STORAGE_1A_*`, `STORAGE_1B_*`, `STORAGE_2A_*`, `STORAGE_2B_*`

3. **New Parameters**:
   - Added `*_ENCRYPTION_TYPE` parameters for each device
   - Updated minimum cryptsetup version requirement to 2.4.0
   - Enhanced validation and error handling

Use `./srv-ctl.sh validate-config` to check your configuration after updating.

## Development & Testing

The project includes comprehensive tests with VM-based testing:

```bash
# Run local tests (no root required)
./tests/run-tests.sh

# Run integration tests in VM (CI or manual)
./tests/vm/run-tests.sh ubuntu-22.04

# Run system tests in VM (CI or manual)
./tests/vm/run-system-tests.sh ubuntu-22.04
```

See [`tests/README.md`](tests/README.md) for detailed testing documentation.

## Project Structure

```
srv-ctl/
├── srv-ctl.sh              # Main script
├── lib/
│   ├── os-utils.sh        # OS-level utilities
│   └── storage.sh         # Storage operations
├── config.local.template   # Configuration template
└── tests/                  # Test suite
```

## License

See repository for license information.

