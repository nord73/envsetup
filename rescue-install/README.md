# Rescue Install Scripts

## Enhanced Flexible Installer

The new `install-flexible.sh` script supports multiple installation modes and distributions:

### Features

- **Multi-distribution support**: Debian (bookworm+) and Ubuntu (24.04+)
- **Flexible partitioning modes**:
  - `full-zfs`: Traditional ZFS-on-root (like original script)
  - `fixed-root-zfs`: Fixed-size root partition + ZFS for data
- **Multiple root filesystems**: ext4, xfs, btrfs (for fixed-root mode)
- **Automatic distribution detection**
- **Configurable partition sizes**

### Quick Start

1. **Copy and edit configuration:**
   ```bash
   cp .env.flexible .env
   # Edit .env to match your requirements
   ```

2. **Run the installer:**
   ```bash
   set -a; source .env; set +a
   bash install-flexible.sh
   ```

### Configuration Options

Key variables in `.env`:

- `PARTITION_MODE`: `full-zfs` or `fixed-root-zfs`
- `DISTRO`: `auto`, `debian`, or `ubuntu`
- `CODENAME`: `auto`, `bookworm`, `trixie`, `noble`, etc.
- `ROOT_SIZE`: Size of root partition (fixed-root mode)
- `ROOT_FS`: Root filesystem type (fixed-root mode)

### Examples

**Debian Bookworm with full ZFS:**
```bash
DISTRO=debian
CODENAME=bookworm
PARTITION_MODE=full-zfs
```

**Ubuntu Noble with 25GB ext4 root + ZFS data:**
```bash
DISTRO=ubuntu
CODENAME=noble
PARTITION_MODE=fixed-root-zfs
ROOT_SIZE=25G
ROOT_FS=ext4
```

**Auto-detect with 30GB XFS root + encrypted ZFS:**
```bash
PARTITION_MODE=fixed-root-zfs
ROOT_SIZE=30G
ROOT_FS=xfs
ENCRYPT=yes
```

## Original Debian Trixie ZFS Installer

For the original Debian Trixie ZFS-only installation:

    set -a; source .env; set +a
    bash install-zfs-trixie.sh
