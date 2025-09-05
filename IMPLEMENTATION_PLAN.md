# Implementation Plan for Enhanced rescue-install

## Overview
This document outlines the implementation of enhanced rescue-install functionality to support:
1. Optional fixed-size root partition with specified filesystem
2. Support for Debian (bookworm+) and Ubuntu (24.04+)

## Implementation Status: ✅ COMPLETED

### New Features Implemented

#### 1. Multi-Distribution Support ✅
- **Auto-detection**: Automatically detects current distribution and codename
- **Debian support**: bookworm, trixie
- **Ubuntu support**: noble (24.04), oracular (24.10+)
- **Configurable**: Manual override via `DISTRO` and `CODENAME` variables

#### 2. Flexible Partitioning Modes ✅
- **`full-zfs`**: Traditional ZFS-on-root (compatible with original script)
- **`fixed-root-zfs`**: Fixed-size root partition + ZFS for data

#### 3. Multiple Root Filesystem Support ✅
- **ext4**: Default, widely compatible
- **xfs**: High-performance filesystem
- **btrfs**: Advanced filesystem with snapshots

#### 4. Enhanced Configuration ✅
- **`ROOT_SIZE`**: Configurable root partition size (e.g., "25G", "30G")
- **`ROOT_FS`**: Choice of root filesystem type
- **`PARTITION_MODE`**: Selection between full-zfs and fixed-root-zfs modes

## Files Created/Modified

### New Files
1. **`rescue-install/install-flexible.sh`**: Enhanced installer script
2. **`rescue-install/.env.flexible`**: Comprehensive configuration template
3. **`IMPLEMENTATION_PLAN.md`**: This documentation

### Modified Files
1. **`rescue-install/README.md`**: Updated with new installer documentation

## Partitioning Schemes

### Full ZFS Mode (`PARTITION_MODE=full-zfs`)
```
UEFI:                           BIOS:
1. EFI System (1GB, vfat)      1. BIOS Boot (1MB)
2. Boot Pool (2GB, ZFS)        2. Boot Pool (2GB, ZFS)  
3. Root Pool (remaining, ZFS)   3. Root Pool (remaining, ZFS)
```

### Fixed Root + ZFS Mode (`PARTITION_MODE=fixed-root-zfs`)
```
UEFI:                           BIOS:
1. EFI System (1GB, vfat)      1. BIOS Boot (1MB)
2. Boot Pool (2GB, ZFS)        2. Boot Pool (2GB, ZFS)
3. Root (ROOT_SIZE, ROOT_FS)    3. Root (ROOT_SIZE, ROOT_FS)
4. Data Pool (remaining, ZFS)   4. Data Pool (remaining, ZFS)
```

## Configuration Examples

### Debian Bookworm with Full ZFS
```bash
DISTRO=debian
CODENAME=bookworm
PARTITION_MODE=full-zfs
```

### Ubuntu Noble with 25GB ext4 Root + ZFS Data
```bash
DISTRO=ubuntu
CODENAME=noble
PARTITION_MODE=fixed-root-zfs
ROOT_SIZE=25G
ROOT_FS=ext4
```

### Auto-detect with 30GB XFS Root + Encrypted ZFS
```bash
PARTITION_MODE=fixed-root-zfs
ROOT_SIZE=30G
ROOT_FS=xfs
ENCRYPT=yes
```

## Testing Performed

### ✅ Syntax Validation
- Script syntax checking with `bash -n`
- Configuration file validation
- Function definition verification

### ✅ Partitioning Logic Testing
- UEFI and BIOS boot modes
- All supported root filesystems (ext4, xfs, btrfs)
- Both partitioning modes (full-zfs, fixed-root-zfs)

### ✅ Distribution Detection Testing
- Valid distribution/codename combinations
- Invalid configuration rejection
- Auto-detection logic

## Usage Instructions

1. **Choose configuration approach:**
   ```bash
   # Use provided template
   cp rescue-install/.env.flexible rescue-install/.env
   
   # Or modify existing
   vi rescue-install/.env
   ```

2. **Edit configuration:**
   - Set `PARTITION_MODE` (full-zfs or fixed-root-zfs)
   - Set `DISTRO` and `CODENAME` (or leave as "auto")
   - For fixed-root-zfs: set `ROOT_SIZE` and `ROOT_FS`

3. **Run installer:**
   ```bash
   cd rescue-install
   set -a; source .env; set +a
   bash install-flexible.sh
   ```

## Backward Compatibility

The original `install-zfs-trixie.sh` remains unchanged and fully functional. Users can continue using it for Debian Trixie ZFS-only installations.

## Future Enhancements

Potential areas for future improvement:
- Support for additional distributions (Fedora, openSUSE)
- RAID configurations
- Additional filesystem options
- Automated testing framework
- Integration with cloud-init