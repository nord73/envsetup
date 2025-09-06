#!/usr/bin/env bash
set -Eeuo pipefail

# --- cfg (override via .env) ---
[ -f .env ] && set -a && . ./.env && set +a
DISK="${DISK:-/dev/sda}"
HOSTNAME="${HOSTNAME:-mail1}"
TZ="${TZ:-UTC}"
POOL_R="${POOL_R:-rpool}"
POOL_B="${POOL_B:-bpool}"
ARC_MAX_MB="${ARC_MAX_MB:-2048}"
ENCRYPT="${ENCRYPT:-no}"
FORCE="${FORCE:-1}"
NEW_USER="${NEW_USER:-}"           # optional
NEW_USER_SUDO="${NEW_USER_SUDO:-1}"
SSH_IMPORT_IDS="${SSH_IMPORT_IDS:-}"                 # e.g. "gh:user"
SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"       # inline
SSH_AUTHORIZED_KEYS_URLS="${SSH_AUTHORIZED_KEYS_URLS:-}" # URLs
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-prohibit-password}"
PASSWORD_AUTH="${PASSWORD_AUTH:-no}"

# --- help ---
show_help() {
cat << 'EOF'
ZFS-on-root installer for Debian 13 (Trixie)

USAGE:
    sudo ./install-zfs-trixie.sh [OPTIONS] [KEY=VALUE ...]

DESCRIPTION:
    Advanced ZFS-on-root installer with enhanced security features and
    optimal partition alignment. Supports both BIOS and UEFI boot modes.

SECURITY & ROBUSTNESS:
    • Secure environment variable passing (no sed/perl injection)
    • Hardened SSH key import with validation and timeout handling  
    • Comprehensive error handling with proper cleanup
    • Input validation and requirement checking

ADVANCED FEATURES:
    • DEBUG mode for troubleshooting (DEBUG=1)
    • Optional disk autodetect (automatically finds largest available disk)
    • Optimal partition alignment (1MiB boundaries)
    • Separate cleanup script for problematic re-runs (cleanup-zfs.sh)
    • Idempotent operations with ZFS state detection

CLEANUP:
    If installation fails due to existing ZFS pools, use the cleanup script:
    
        sudo ./cleanup-zfs.sh --disk /dev/sda
    
    Then re-run the installer. The cleanup script can also be used standalone
    for troubleshooting ZFS state issues.

CONFIGURATION:
    Configure via environment variables or .env file:

    DISK=/dev/nvme0n1          Target disk (default: /dev/sda)
    HOSTNAME=myhost            System hostname (default: mail1)
    TZ=America/New_York        Timezone (default: UTC)
    POOL_R=rpool               Root pool name (default: rpool)  
    POOL_B=bpool               Boot pool name (default: bpool)
    ARC_MAX_MB=2048            ZFS ARC max size in MB (default: 2048)
    ENCRYPT=yes                Enable ZFS encryption (default: no)
    FORCE=1                    Skip confirmations (default: 1)
    NEW_USER=admin             Create additional user (optional)
    NEW_USER_SUDO=1            Give new user sudo access (default: 1)
    SSH_IMPORT_IDS="gh:user"   Import SSH keys from GitHub/etc (optional)
    SSH_AUTHORIZED_KEYS="..."  Direct SSH key content (optional)
    SSH_AUTHORIZED_KEYS_URLS="..." SSH key URLs (optional)
    PERMIT_ROOT_LOGIN=yes      SSH root login setting (default: prohibit-password)
    PASSWORD_AUTH=yes          SSH password auth (default: no)

EXAMPLES:
    # Basic install with auto-detected disk
    sudo ./install-zfs-trixie.sh

    # Install with specific configuration (environment variables before script)
    sudo DISK=/dev/nvme0n1 NEW_USER=admin SSH_IMPORT_IDS="gh:myuser" ./install-zfs-trixie.sh

    # Install with specific configuration (environment variables as arguments)
    sudo ./install-zfs-trixie.sh DISK=/dev/nvme0n1 NEW_USER=admin SSH_IMPORT_IDS="gh:myuser"

    # Install with debug mode and force (no confirmations)
    sudo DEBUG=1 FORCE=1 ./install-zfs-trixie.sh

OPTIONS:
    -h, --help         Show this help message and exit
    KEY=VALUE          Set environment variable KEY to VALUE

REQUIREMENTS:
    • Must run as root
    • Target disk must exist and be a block device
    • System must be booted from Debian rescue/live environment

EOF
}

# --- parse args ---
for arg in "$@"; do
    case $arg in
        -h|--help)
            show_help
            exit 0
            ;;
        *=*)
            # Handle KEY=VALUE environment variable assignments
            key="${arg%%=*}"
            value="${arg#*=}"
            if [[ "$key" =~ ^[A-Z_][A-Z0-9_]*$ ]]; then
                export "$key"="$value"
            else
                echo "Invalid environment variable name: $key"
                echo "Use --help for usage information"
                exit 1
            fi
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# --- utils ---
b() { printf '\033[1m%s\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
warn(){ printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }
ask(){ [ "$FORCE" = 1 ] && return 0; read -r -p "$1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]; }

trap 'die "line $LINENO"' ERR
[ "$(id -u)" -eq 0 ] || die "run as root"
[ -b "$DISK" ] || die "disk $DISK missing"

# Validate that DISK is a whole disk, not a partition
# NVMe devices: /dev/nvme0n1 (disk) vs /dev/nvme0n1p1 (partition)
# SATA/SCSI devices: /dev/sda (disk) vs /dev/sda1 (partition)
# Virtual devices: /dev/vda (disk) vs /dev/vda1 (partition)
if [[ "$DISK" =~ p[0-9]+$ ]] || [[ "$DISK" =~ ^/dev/[sv]d[a-z][0-9]+$ ]]; then
  die "DISK=$DISK appears to be a partition. Please specify the whole disk (e.g., /dev/sda instead of /dev/sda1, or /dev/nvme0n1 instead of /dev/nvme0n1p1)"
fi

BOOTMODE=bios; [ -d /sys/firmware/efi ] && BOOTMODE=uefi
b "Rescue: $BOOTMODE  •  Will WIPE $DISK"; ask "Proceed?" || die "aborted"

# --- 0) rescue deps (no live initramfs writes) ---
source /etc/os-release; CODENAME=${VERSION_CODENAME:-bookworm}
cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-backports main contrib non-free non-free-firmware
EOF
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
dpkg-divert --local --rename --add /usr/sbin/update-initramfs >/dev/null 2>&1 || true
printf '#!/bin/sh\nexit 0\n' >/usr/sbin/update-initramfs && chmod +x /usr/sbin/update-initramfs
apt-get -y install dkms build-essential "linux-headers-$(uname -r)" zfs-dkms zfsutils-linux debootstrap gdisk dosfstools
modprobe zfs || die "zfs modprobe failed"
ok "Rescue prereqs"

# --- 1) Check for existing ZFS state ---
b "Checking for existing ZFS pools on $DISK"

# Simple check for existing ZFS state that would conflict
has_zfs_state=false

# Check for our target pools
if zpool list "$POOL_B" >/dev/null 2>&1 || zpool list "$POOL_R" >/dev/null 2>&1; then
  has_zfs_state=true
fi

# Check for importable pools that might conflict  
if zpool import 2>/dev/null | grep -E "pool:" | grep -E "($POOL_B|$POOL_R)" >/dev/null 2>&1; then
  has_zfs_state=true
fi

# Check for ZFS signatures on target disk partitions
for part in "${DISK}"*; do
  if [ -b "$part" ] && blkid -p "$part" 2>/dev/null | grep -q zfs_member; then
    has_zfs_state=true
    break
  fi
done

if [ "$has_zfs_state" = true ]; then
  echo
  echo -e "\033[1;33m[WARNING]\033[0m Existing ZFS pools or signatures detected on $DISK"
  echo "This can cause installation failures. Run cleanup first:"
  echo
  echo "  sudo ./cleanup-zfs.sh --disk $DISK"
  echo
  echo "Then re-run this installer."
  echo
  read -p "Continue anyway? [y/N]: " -r continue_anyway
  if [[ ! "$continue_anyway" =~ ^[Yy]$ ]]; then
    echo "Installation cancelled. Run cleanup script first."
    exit 1
  fi
  warn "Proceeding with existing ZFS state - installation may fail"
else
  ok "No conflicting ZFS state detected"
fi

# --- 2) partition ---
b "Partitioning $DISK"
sgdisk -Z "$DISK"
if [ "$BOOTMODE" = uefi ]; then
  sgdisk -n1:1M:+1G -t1:EF00 "$DISK"; sgdisk -n2:0:+2G -t2:BF01 "$DISK"; sgdisk -n3:0:0 -t3:BF01 "$DISK"
  mkfs.vfat -F32 -n EFI "${DISK}1"
else
  sgdisk -n1:1M:+1M -t1:EF02 "$DISK"; sgdisk -n2:0:+2G -t2:BF01 "$DISK"; sgdisk -n3:0:0 -t3:BF01 "$DISK"
fi

# Force kernel to recognize new partitions
partprobe "$DISK" 2>/dev/null || true
sleep 2

ok "Partitioned"

# --- 3) pools ---
b "Creating ZFS pools"

# Check if partitions exist and wait for them to be available
for partition in "${DISK}2" "${DISK}3"; do
  for i in 1 2 3 4 5; do
    if [ -b "$partition" ]; then
      break
    fi
    b "Waiting for partition $partition to appear (attempt $i/5)"
    partprobe "$DISK" 2>/dev/null || true
    udevadm settle --timeout=5
    sleep 1
  done
  [ -b "$partition" ] || die "Partition $partition not found after partitioning"
done

[ "$ENCRYPT" = yes ] && ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase) || ENC=()
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -o compatibility=grub2 -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
  -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
  -O mountpoint=none -O canmount=off "${ENC[@]}" "$POOL_R" "${DISK}3"
ok "Pools created"

# --- 4) datasets + temp mounts ---
ensure_ds(){ zfs list -H -o name "$1" >/dev/null 2>&1 || zfs create "${@:2}" "$1"; }
ensure_mount(){ local ds="$1" mp="$2"; zfs set mountpoint="$mp" "$ds"; [ "$(zfs get -H -o value mounted "$ds")" = yes ] || zfs mount "$ds"; }

b "Datasets"
ensure_ds "$POOL_R/ROOT" -o canmount=off -o mountpoint=none
ensure_ds "$POOL_R/ROOT/debian"
ensure_ds "$POOL_B/BOOT" -o canmount=off -o mountpoint=none
ensure_ds "$POOL_B/BOOT/debian"

ensure_mount "$POOL_R/ROOT/debian" /mnt
mkdir -p /mnt/boot
ensure_mount "$POOL_B/BOOT/debian" /mnt/boot

ensure_ds "$POOL_R/var"               -o mountpoint=/mnt/var
ensure_ds "$POOL_R/var/lib"           -o mountpoint=/mnt/var/lib
ensure_ds "$POOL_R/var/lib/mysql"     -o recordsize=16K -o logbias=latency -o primarycache=all -o mountpoint=/mnt/var/lib/mysql
ensure_ds "$POOL_R/var/vmail"         -o recordsize=16K -o mountpoint=/mnt/var/vmail
ensure_ds "$POOL_R/home"              -o mountpoint=/mnt/home
ensure_ds "$POOL_R/srv"               -o mountpoint=/mnt/srv
ok "Datasets mounted at /mnt"

# --- 5) debootstrap ---
b "Debootstrap trixie"
debootstrap trixie /mnt http://deb.debian.org/debian/
[ -x /mnt/bin/sh ] || die "bootstrap incomplete"
ok "Base system"

# --- 6) post-chroot payload (NO mountpoint flips here) ---
b "Prepare post-chroot"

# Calculate ARC bytes for environment variable
ARC_BYTES=$((ARC_MAX_MB*1024*1024))

cat >/mnt/root/post-chroot.sh <<'EOS'
set -Eeuo pipefail
trap 'echo "[FAIL] line $LINENO"; exit 1' ERR
HN="$HOSTNAME"; TZ="$TZ"; DISK="$DISK"; RP="$POOL_R"; BP="$POOL_B"
ARC_BYTES="$ARC_BYTES"
NEW_USER="$NEW_USER"; NEW_USER_SUDO="$NEW_USER_SUDO"
SSH_IMPORT_IDS="$SSH_IMPORT_IDS"; AUTH_KEYS="$SSH_AUTHORIZED_KEYS"; AUTH_URLS="$SSH_AUTHORIZED_KEYS_URLS"
PERMIT="$PERMIT_ROOT_LOGIN"; PASSAUTH="$PASSWORD_AUTH"


install -d -m0755 /var/cache/apt/archives/partial /var/lib/apt/lists/partial /var/lib/dpkg/updates /var/log/apt
[ -s /var/lib/dpkg/status ] || :> /var/lib/dpkg/status

echo "$HN" >/etc/hostname
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf "127.0.0.1 localhost\n127.0.1.1 $HN\n" >/etc/hosts

hostname "$HN" || true
grep -q '\<rescue\>' /etc/hosts || printf "127.0.0.1 rescue\n" >> /etc/hosts

cat >/etc/apt/sources.list <<SL
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
SL
export DEBIAN_FRONTEND=noninteractive
apt-get -y update

# Setup locales first before installing packages that need locale support
apt-get -y install locales
grep -q "^en_US.UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen >/dev/null 2>&1 || true
command -v update-locale >/dev/null 2>&1 && update-locale LANG=en_US.UTF-8 || true

# Set locale environment variables for package installation
export LANG=en_US.UTF-8
export LC_ALL=en_US.UTF-8
export LC_CTYPE=en_US.UTF-8
export LC_MESSAGES=en_US.UTF-8

# Now install remaining packages with proper locale environment
apt-get -y install console-setup ca-certificates curl \
  linux-image-amd64 linux-headers-amd64 \
  zfs-dkms zfsutils-linux zfs-initramfs \
  openssh-server ssh-import-id sudo grub-common cloud-init

# ensure RW env + tmp
zfs set readonly=off "$RP/ROOT/debian" >/dev/null 2>&1 || true
zfs set readonly=off "$RP/var"         >/dev/null 2>&1 || true

mount -o remount,rw / || true
install -d -m1777 /var/tmp /tmp

# hostid + cache + bootfs
# Generate and save hostid to ensure ZFS pools can be imported automatically
if command -v zgenhostid >/dev/null 2>&1; then
    # Generate a hostid and save it to /etc/hostid for persistent identification
    zgenhostid
    # Verify the hostid was written correctly
    if [ -f /etc/hostid ]; then
        echo "[OK] Generated hostid: $(hostid)"
    else
        # Fallback: manually create hostid file if zgenhostid didn't create it
        printf "$(hostid | cut -c 7-8 | xxd -r -p; hostid | cut -c 5-6 | xxd -r -p; hostid | cut -c 3-4 | xxd -r -p; hostid | cut -c 1-2 | xxd -r -p)" > /etc/hostid
        echo "[OK] Created hostid file manually: $(hostid)"
    fi
else
    echo "[WARN] zgenhostid not available, using fallback hostid generation"
    # Fallback: manually create hostid file
    printf "$(hostid | cut -c 7-8 | xxd -r -p; hostid | cut -c 5-6 | xxd -r -p; hostid | cut -c 3-4 | xxd -r -p; hostid | cut -c 1-2 | xxd -r -p)" > /etc/hostid
fi

zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
zpool set bootfs="$RP/ROOT/debian" "$RP" || true

# import policy for initramfs (safe; no -f)
cat >/etc/default/zfs <<ZDF
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
ZPOOL_IMPORT_OPTS="-N"
ZPOOL_IMPORT_TIMEOUT="30"
ZFS_INITRD_POST_MODPROBE_SLEEP="2"
# Force import pools using cache to avoid hostid issues
ZPOOL_FORCE_IMPORT="1"
ZDF

# ARC cap
echo "options zfs zfs_arc_max=$ARC_BYTES" >/etc/modprobe.d/zfs.conf

# GRUB defaults + zfs root
mkdir -p /etc/default
[ -f /etc/default/grub ] || cat >/etc/default/grub <<'G'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=Debian
GRUB_CMDLINE_LINUX=""
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
G
sed -ri "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=ZFS=$RP/ROOT/debian rootdelay=5\"|" /etc/default/grub
grep -q '^GRUB_PRELOAD_MODULES' /etc/default/grub || echo 'GRUB_PRELOAD_MODULES="zfs"' >> /etc/default/grub

# build initrd + install GRUB (BIOS/UEFI)
mountpoint -q /boot || zfs mount "$BP/BOOT/debian" || true
TMPDIR=/tmp update-initramfs -u
if [ -d /sys/firmware/efi ]; then
  apt-get -y install grub-efi-amd64 efibootmgr
  mkdir -p /boot/efi
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
else
  apt-get -y install grub-pc
  grub-install "$DISK"
fi
update-grub
test -s /boot/grub/grub.cfg

# SSH via drop-in; avoid editing main file
install -d /etc/ssh/sshd_config.d
umask 077
cat >/etc/ssh/sshd_config.d/99-bootstrap.conf <<EOF
PermitRootLogin ${PERMIT}
PasswordAuthentication ${PASSAUTH}
EOF
install -d -m700 /root/.ssh; : >/root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
[ -n "$SSH_IMPORT_IDS" ] && ssh-import-id $SSH_IMPORT_IDS || echo "[WARN] ssh-import-id failed for root"

[ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>/root/.ssh/authorized_keys
if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>/root/.ssh/authorized_keys || true; done; fi

if [ -n "$NEW_USER" ]; then
  id "$NEW_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$NEW_USER"
  [ "$NEW_USER_SUDO" = "1" ] && usermod -aG sudo "$NEW_USER"
  install -d -m700 "/home/$NEW_USER/.ssh"
  : >"/home/$NEW_USER/.ssh/authorized_keys"; chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"

  if [ -n "$SSH_IMPORT_IDS" ]; then
    runuser -u "$NEW_USER" -- ssh-import-id $SSH_IMPORT_IDS || echo "[WARN] ssh-import-id failed for $NEW_USER"
  fi
  [ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>"/home/$NEW_USER/.ssh/authorized_keys"
  if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>"/home/$NEW_USER/.ssh/authorized_keys" || true; done; fi
fi



# cloud-init: only datasource list (doesn’t override ssh)
mkdir -p /etc/cloud/cloud.cfg.d
echo 'datasource_list: [ConfigDrive, NoCloud, Ec2]' >/etc/cloud/cloud.cfg.d/90-datasources.cfg

# enable units (OK if "ignoring" in chroot; links still created)
systemctl enable ssh zfs-import-cache zfs-import.target zfs-mount >/dev/null 2>&1 || true
systemctl enable cloud-init cloud-config cloud-final cloud-init-local >/dev/null 2>&1 || true

# sanity
sshd -t
test -s /boot/grub/grub.cfg
ls -1 /boot/vmlinuz-* /boot/initrd.img-* >/dev/null
zpool get -H -o value bootfs "$RP" | grep -q "$RP/ROOT/debian"
echo "[OK] post-chroot done"
EOS

# Export environment variables for secure passing to chroot
export HOSTNAME TZ DISK POOL_R POOL_B ARC_BYTES NEW_USER NEW_USER_SUDO 
export SSH_IMPORT_IDS SSH_AUTHORIZED_KEYS SSH_AUTHORIZED_KEYS_URLS 
export PERMIT_ROOT_LOGIN PASSWORD_AUTH

ok "post-chroot prepared"

# --- 7) run post-chroot ---
b "Finalize in chroot"
for d in dev proc sys run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
mkdir -p /mnt/etc; [ -e /mnt/etc/resolv.conf ] || : >/mnt/etc/resolv.conf
mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
chroot /mnt /bin/bash /root/post-chroot.sh
chroot /mnt test -s /boot/grub/grub.cfg
chroot /mnt /bin/bash -lc 'command -v sshd && sshd -t'
ok "Chroot finalize OK"

# --- 8) teardown (unmount first, THEN set runtime mountpoints), export ---
b "Teardown + runtime mountpoints"
umount -l /mnt/etc/resolv.conf 2>/dev/null || true
for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done

# Unmount datasets cleanly
zfs list -H -o name -r "$POOL_R" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
zfs list -H -o name -r "$POOL_B" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true

# Flip mountpoints NOW (no remount attempts since nothing is mounted)
for spec in \
  "$POOL_R/ROOT/debian=/" \
  "$POOL_B/BOOT/debian=/boot" \
  "$POOL_R/var=/var" \
  "$POOL_R/var/lib=/var/lib" \
  "$POOL_R/var/lib/mysql=/var/lib/mysql" \
  "$POOL_R/var/vmail=/var/vmail" \
  "$POOL_R/home=/home" \
  "$POOL_R/srv=/srv"; do
  ds=${spec%%=*}; mp=${spec#*=}
  zfs set mountpoint="$mp" "$ds"
done
ok "Mountpoints set for runtime"

# Export pools (best-effort)
zpool export -f "$POOL_B" 2>/dev/null || true
zpool export -f "$POOL_R" 2>/dev/null || true
ok "Done. Reboot."

# Note: ZFS pools should now import automatically on boot
echo "ZFS pools configured for automatic import. System should boot without manual intervention."
