# srv-ctl

Small utility to manage home server services dependent on encrypted storage.

## Features

- **Multiple Syncthing Services**: Supports running 2 parallel Syncthing services with different users
- **Multiple Storage Devices**: Supports 5 storage devices (1 primary data + 4 paired storage devices)
- **Dual Encryption Support**: Supports both LUKS and BitLocker encryption formats
- **LVM Support**: Optional LVM (Logical Volume Manager) support for device management
- **Network Storage**: CIFS/SMB network share mounting support
- **Configuration Validation**: Built-in validation to verify setup before execution

## Requirements

- **cryptsetup**: Version 2.4.0+ (supports both LUKS and BitLocker encryption)
- **lvm2**: Required only if using LVM volumes
- **Root privileges**: Script must be run as root

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
readonly DOCKER_SERVICE="docker.service"
```

### Storage Device Configuration

Each storage device supports:

- **Mount Point**: Local directory under `/mnt/`
- **Device Mapper**: Name for the unlocked device
- **LVM Support**: Optional logical volume management
- **Encryption Type**: Either `luks` or `bitlocker`
- **Key Files**: Optional for automated unlocking

Example for BitLocker device:

```bash
readonly STORAGE_2A_MOUNT="storage2a"
readonly STORAGE_2A_MAPPER="storage2a-data"
readonly STORAGE_2A_UUID="your-device-uuid"
readonly STORAGE_2A_KEY_FILE="/path/to/recovery.key"
readonly STORAGE_2A_ENCRYPTION_TYPE="bitlocker"
```

## Usage

```bash
sudo ./srv-ctl.sh start               # Start all services and mount devices
sudo ./srv-ctl.sh stop                # Stop all services and unmount devices
sudo ./srv-ctl.sh unlock-only         # Only unlock and mount devices
sudo ./srv-ctl.sh stop-services-only  # Only stop services
./srv-ctl.sh validate-config          # Validate configuration without making changes
./srv-ctl.sh help                     # Show help message
```

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
