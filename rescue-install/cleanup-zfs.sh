#!/usr/bin/env bash
set -Eeuo pipefail

# ZFS Cleanup Script
# Comprehensive cleanup of ZFS pools, devices, and kernel state
# Can be run independently before installation or as part of troubleshooting

# --- Configuration ---
DISK="${DISK:-/dev/sda}"
POOL_R="${POOL_R:-rpool}"
POOL_B="${POOL_B:-bpool}"
VERBOSE="${VERBOSE:-0}"

# --- Helper functions ---
b() { echo -e "\033[1;34m$*\033[0m"; }
ok() { echo -e "\033[1;32m[OK]\033[0m $*"; }
warn() { echo -e "\033[1;33m[WARN]\033[0m $*"; }
die() { echo -e "\033[1;31m[FATAL]\033[0m $*" >&2; exit 1; }

show_help() {
cat << 'EOF'
ZFS Cleanup Script

USAGE:
    sudo ./cleanup-zfs.sh [OPTIONS]

DESCRIPTION:
    Comprehensive cleanup of ZFS pools, devices, and kernel state.
    Use this before running the ZFS installer to ensure clean state.

OPTIONS:
    -h, --help          Show this help
    -v, --verbose       Enable verbose output
    -d, --disk DISK     Target disk (default: /dev/sda)
    -n, --dry-run       Show what would be done without executing

ENVIRONMENT VARIABLES:
    DISK                Target disk (default: /dev/sda)
    POOL_R              Root pool name (default: rpool)
    POOL_B              Boot pool name (default: bpool)
    VERBOSE             Enable verbose output (0/1)

EXAMPLES:
    # Basic cleanup
    sudo ./cleanup-zfs.sh

    # Cleanup specific disk with verbose output
    sudo DISK=/dev/nvme0n1 ./cleanup-zfs.sh -v

    # Dry run to see what would be cleaned
    sudo ./cleanup-zfs.sh --dry-run
EOF
}

# --- Parse arguments ---
DRY_RUN=0
while [[ $# -gt 0 ]]; do
    case $1 in
        -h|--help)
            show_help
            exit 0
            ;;
        -v|--verbose)
            VERBOSE=1
            shift
            ;;
        -d|--disk)
            DISK="$2"
            shift 2
            ;;
        -n|--dry-run)
            DRY_RUN=1
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            show_help
            exit 1
            ;;
    esac
done

# --- Logging functions ---
log() {
    [ "$VERBOSE" = 1 ] && echo "  $*" || true
}

run_cmd() {
    local cmd="$*"
    if [ "$DRY_RUN" = 1 ]; then
        echo "DRY-RUN: $cmd"
        return 0
    fi
    
    if [ "$VERBOSE" = 1 ]; then
        echo "EXEC: $cmd"
        eval "$cmd"
    else
        eval "$cmd" >/dev/null 2>&1 || true
    fi
}

# --- Validation ---
[ "$EUID" -eq 0 ] || die "This script must be run as root"
[ -b "$DISK" ] || die "Disk $DISK not found or not a block device"

# Check if ZFS is available
if ! command -v zpool >/dev/null 2>&1; then
    die "ZFS utilities not found. Install zfsutils-linux first."
fi

# --- Main cleanup logic ---
b "ZFS Cleanup Script"
echo "Target disk: $DISK"
echo "Pool names: $POOL_B (boot), $POOL_R (root)"
[ "$DRY_RUN" = 1 ] && echo "DRY RUN MODE - no changes will be made"
echo

# 1. Check what exists
b "Checking current ZFS state"
pools_found=()
importable_pools=()

# Check for active pools
for pool in "$POOL_B" "$POOL_R"; do
    if zpool list "$pool" >/dev/null 2>&1; then
        pools_found+=("$pool")
        log "Found active pool: $pool"
    fi
done

# Check for importable pools
while IFS= read -r pool; do
    if [[ "$pool" =~ ^[[:space:]]*pool:[[:space:]]*(.+)$ ]]; then
        pool_name="${BASH_REMATCH[1]}"
        if [[ "$pool_name" == "$POOL_B" || "$pool_name" == "$POOL_R" ]]; then
            importable_pools+=("$pool_name")
            log "Found importable pool: $pool_name"
        fi
    fi
done < <(zpool import 2>/dev/null || true)

# Check for ZFS signatures on target devices
zfs_devices=()
for part in "${DISK}"*; do
    if [ -b "$part" ]; then
        if blkid -p "$part" 2>/dev/null | grep -q zfs_member; then
            zfs_devices+=("$part")
            log "Found ZFS signature on: $part"
        fi
    fi
done

# Report findings
if [ ${#pools_found[@]} -eq 0 ] && [ ${#importable_pools[@]} -eq 0 ] && [ ${#zfs_devices[@]} -eq 0 ]; then
    ok "No ZFS pools or signatures found. System appears clean."
    exit 0
fi

echo "Cleanup required:"
[ ${#pools_found[@]} -gt 0 ] && echo "  Active pools: ${pools_found[*]}"
[ ${#importable_pools[@]} -gt 0 ] && echo "  Importable pools: ${importable_pools[*]}"
[ ${#zfs_devices[@]} -gt 0 ] && echo "  Devices with ZFS signatures: ${zfs_devices[*]}"
echo

# 2. Pool cleanup
if [ ${#pools_found[@]} -gt 0 ] || [ ${#importable_pools[@]} -gt 0 ]; then
    b "Cleaning up ZFS pools"
    
    # Destroy active pools
    for pool in "${pools_found[@]}"; do
        log "Exporting pool: $pool"
        run_cmd "zpool export -f '$pool'"
        log "Destroying pool: $pool"
        run_cmd "zpool destroy -f '$pool'"
    done
    
    # Import and destroy importable pools
    for pool in "${importable_pools[@]}"; do
        log "Importing pool for cleanup: $pool"
        run_cmd "zpool import -N -f '$pool'"
        log "Destroying imported pool: $pool"
        run_cmd "zpool destroy -f '$pool'"
    done
    
    ok "Pool cleanup completed"
fi

# 3. Device cleanup
if [ ${#zfs_devices[@]} -gt 0 ]; then
    b "Cleaning device signatures"
    
    for device in "${zfs_devices[@]}"; do
        log "Clearing ZFS labels on: $device"
        run_cmd "zpool labelclear -f '$device'"
        run_cmd "wipefs -af '$device'"
        
        # Clear potential ZFS metadata areas
        log "Clearing metadata areas on: $device"
        run_cmd "dd if=/dev/zero of='$device' bs=1M count=10 conv=notrunc"
        
        # Get device size and clear end
        if device_size=$(blockdev --getsz "$device" 2>/dev/null); then
            # Clear last 10MB (convert sectors to bytes, subtract 10MB, convert back)
            end_sector=$((device_size - 20480))  # 10MB = 20480 sectors
            if [ $end_sector -gt 0 ]; then
                log "Clearing end metadata on: $device"
                run_cmd "dd if=/dev/zero of='$device' bs=512 seek='$end_sector' count=20480 conv=notrunc"
            fi
        fi
    done
    
    ok "Device cleanup completed"
fi

# 4. Kernel state cleanup
b "Refreshing kernel state"
run_cmd "partprobe '$DISK'"
run_cmd "udevadm settle --timeout=10"

# Clear ZFS caches
log "Clearing ZFS caches"
run_cmd "rm -f /etc/zfs/zpool.cache*"
run_cmd "rm -rf /etc/zfs/zfs-list.cache*"
run_cmd "rm -rf /run/zfs/*"
run_cmd "rm -rf /var/lib/zfs/*"

ok "Kernel state refresh completed"

# 5. Verification
b "Verifying cleanup"
verification_failed=false

# Check that no pools remain
for pool in "$POOL_B" "$POOL_R"; do
    if zpool list "$pool" >/dev/null 2>&1; then
        warn "Pool $pool still exists after cleanup"
        verification_failed=true
    fi
done

# Check that no importable pools remain
while IFS= read -r pool; do
    if [[ "$pool" =~ ^[[:space:]]*pool:[[:space:]]*(.+)$ ]]; then
        pool_name="${BASH_REMATCH[1]}"
        if [[ "$pool_name" == "$POOL_B" || "$pool_name" == "$POOL_R" ]]; then
            warn "Pool $pool_name still importable after cleanup"
            verification_failed=true
        fi
    fi
done < <(zpool import 2>/dev/null || true)

# Check that ZFS signatures are gone
for part in "${DISK}"*; do
    if [ -b "$part" ]; then
        if blkid -p "$part" 2>/dev/null | grep -q zfs_member; then
            warn "ZFS signature still present on: $part"
            verification_failed=true
        fi
    fi
done

if [ "$verification_failed" = true ]; then
    die "Cleanup verification failed. Manual intervention may be required."
fi

ok "Verification passed - ZFS state successfully cleaned"

# 6. Summary
echo
b "Cleanup Summary"
echo "✓ All target ZFS pools removed"
echo "✓ Device signatures cleared"
echo "✓ Kernel state refreshed"
echo "✓ ZFS caches cleared"
echo
echo "The system is now ready for ZFS installation."
echo "You can run the installer: ./install-zfs-trixie.sh"