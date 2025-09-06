Install ZFS on root for Debian Trixie from rescue environment:

## Quick Start

    set -a; source .env; set +a
    bash install-zfs-trixie.sh

## If Installation Fails Due to Existing ZFS

If you encounter errors about existing ZFS pools or device conflicts, use the cleanup script first:

    sudo ./cleanup-zfs.sh --disk /dev/sda
    
Then re-run the installer:

    bash install-zfs-trixie.sh

## Scripts

- **install-zfs-trixie.sh** - Main ZFS installation script
- **cleanup-zfs.sh** - Standalone ZFS cleanup utility for resolving conflicts

## Troubleshooting

The cleanup script provides several options:

    # Basic cleanup
    sudo ./cleanup-zfs.sh
    
    # Verbose output to see what's being cleaned
    sudo ./cleanup-zfs.sh --verbose
    
    # Dry run to see what would be cleaned without executing
    sudo ./cleanup-zfs.sh --dry-run
    
    # Cleanup specific disk
    sudo ./cleanup-zfs.sh --disk /dev/nvme0n1
