#!/usr/bin/env bash
set -euo pipefail
[ -f .env ] && set -a && . ./.env && set +a

# DEBUG mode support
DEBUG="${DEBUG:-0}"
[ "$DEBUG" = "1" ] && set -x

# Show help if requested
if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  cat <<EOF
Debian 13 (trixie) ZFS-on-root installer for rescue environments

Usage: $0 [options]

Environment variables:
  DISK              Target disk (auto-detected if not set)
  HOSTNAME          System hostname (default: mail1)
  TZ                Timezone (default: Europe/Stockholm)
  POOL_R            Root pool name (default: rpool)
  POOL_B            Boot pool name (default: bpool)
  ARC_MAX_MB        ZFS ARC max size in MB (default: 2048)
  ENCRYPT           Enable encryption (yes|no, default: no)
  FORCE             Skip confirmations (0|1, default: 0)
  DEBUG             Enable debug mode (0|1, default: 0)
  
  NEW_USER          Create additional user
  NEW_USER_SUDO     Give sudo access (0|1, default: 1)
  SSH_IMPORT_IDS    SSH keys to import (e.g. "gh:username")
  SSH_AUTHORIZED_KEYS    Direct SSH public keys
  SSH_AUTHORIZED_KEYS_URLS    URLs to fetch SSH keys from
  PERMIT_ROOT_LOGIN SSH root login policy (default: prohibit-password)
  PASSWORD_AUTH     Enable password auth (yes|no, default: no)

Options:
  -h, --help        Show this help
  
Examples:
  # Basic install with auto-detected disk
  $0
  
  # Install with specific disk and user
  DISK=/dev/nvme0n1 NEW_USER=admin SSH_IMPORT_IDS="gh:myuser" $0
  
  # Install with debug mode
  DEBUG=1 FORCE=1 $0

EOF
  exit 0
fi

# Enhanced logging functions
debug() { [ "$DEBUG" = "1" ] && printf "\033[1;36m[DEBUG]\033[0m %s\n" "$*" >&2; }
log() { printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok() { printf "\033[1;32m[OK]\033[0m %s\n" "$*"; }
die() { printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }
ask() { [ "$FORCE" = 1 ] && return 0; read -r -p "$1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]; }

# Function to auto-detect disk if not specified
auto_detect_disk() {
    [ -n "${DISK:-}" ] && return 0
    
    debug "DISK not specified, attempting auto-detection..."
    
    # Get list of block devices, excluding loop devices, ram disks, etc.
    local disks
    disks=$(lsblk -dno NAME,SIZE,TYPE | awk '$3=="disk" && $1!~/^(loop|ram|sr)/ {print "/dev/" $1 " " $2}' | sort -k2 -hr)
    
    if [ -z "$disks" ]; then
        die "No suitable disks found for auto-detection"
    fi
    
    # Select the largest disk
    DISK=$(echo "$disks" | head -n1 | awk '{print $1}')
    local size
    size=$(echo "$disks" | head -n1 | awk '{print $2}')
    
    log "Auto-detected disk: $DISK (size: $size)"
    log "Available disks:"
    echo "$disks" | while IFS= read -r line; do echo "  $line"; done
}

# --- cfg ---
auto_detect_disk
DISK=${DISK:-/dev/sda}; HOSTNAME=${HOSTNAME:-mail1}; TZ=${TZ:-Europe/Stockholm}
POOL_R=${POOL_R:-rpool}; POOL_B=${POOL_B:-bpool}; ARC_MAX_MB=${ARC_MAX_MB:-2048}
ENCRYPT=${ENCRYPT:-no}; FORCE=${FORCE:-0}
NEW_USER=${NEW_USER:-}; NEW_USER_SUDO=${NEW_USER_SUDO:-1}
SSH_IMPORT_IDS=${SSH_IMPORT_IDS:-}; SSH_AUTHORIZED_KEYS=${SSH_AUTHORIZED_KEYS:-}
SSH_AUTHORIZED_KEYS_URLS=${SSH_AUTHORIZED_KEYS_URLS:-}
PERMIT_ROOT_LOGIN=${PERMIT_ROOT_LOGIN:-prohibit-password}; PASSWORD_AUTH=${PASSWORD_AUTH:-no}
# ----------

trap 'die "line $LINENO"' ERR
[ "$(id -u)" -eq 0 ] || die "run as root"
[ -b "$DISK" ] || die "disk $DISK missing"
BOOTMODE=bios; [ -d /sys/firmware/efi ] && BOOTMODE=uefi
log "Rescue mode: $BOOTMODE. Will WIPE $DISK."; ask "Proceed?" || die "aborted"

# --- rescue deps & divert update-initramfs ---
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
ok "Rescue ready"

# --- partition ---
log "Partitioning $DISK…"
sgdisk -Z "$DISK"
if [ "$BOOTMODE" = uefi ]; then
  sgdisk -n1:1M:+1G -t1:EF00 "$DISK"; sgdisk -n2:0:+2G -t2:BF01 "$DISK"; sgdisk -n3:0:0 -t3:BF01 "$DISK"
  mkfs.vfat -F32 "${DISK}1"
else
  sgdisk -n1:1M:+1M -t1:EF02 "$DISK"; sgdisk -n2:0:+2G -t2:BF01 "$DISK"; sgdisk -n3:0:0 -t3:BF01 "$DISK"
fi
ok "Partitioned"

# --- pools ---
log "Creating pools…"
[ "$ENCRYPT" = yes ] && ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase) || ENC=()
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -o compatibility=grub2 -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
  -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
  -O mountpoint=none -O canmount=off "${ENC[@]}" "$POOL_R" "${DISK}3"
ok "Pools created"

# --- datasets (idempotent) ---
ensure_ds(){ zfs list -H -o name "$1" >/dev/null 2>&1 || zfs create "${@:2}" "$1"; }
ensure_mount(){ local ds="$1" mp="$2"; zfs set mountpoint="$mp" "$ds"; [ "$(zfs get -H -o value mounted "$ds")" = yes ] || zfs mount "$ds"; }

log "Datasets…"
ensure_ds "$POOL_R/ROOT" -o canmount=off -o mountpoint=none
ensure_ds "$POOL_R/ROOT/debian"
ensure_ds "$POOL_B/BOOT" -o canmount=off -o mountpoint=none
ensure_ds "$POOL_B/BOOT/debian"

ensure_mount "$POOL_R/ROOT/debian" /mnt
mkdir -p /mnt/boot; ensure_mount "$POOL_B/BOOT/debian" /mnt/boot
ensure_ds "$POOL_R/var"             -o mountpoint=/mnt/var
ensure_ds "$POOL_R/var/lib"         -o mountpoint=/mnt/var/lib
ensure_ds "$POOL_R/var/lib/mysql"   -o recordsize=16K -o logbias=latency -o primarycache=all -o mountpoint=/mnt/var/lib/mysql
ensure_ds "$POOL_R/var/vmail"       -o recordsize=16K -o mountpoint=/mnt/var/vmail
ensure_ds "$POOL_R/home"            -o mountpoint=/mnt/home
ensure_ds "$POOL_R/srv"             -o mountpoint=/mnt/srv
ok "Datasets mounted"

# --- bootstrap trixie ---
log "debootstrap…"
debootstrap trixie /mnt http://deb.debian.org/debian/
[ -x /mnt/bin/sh ] || die "bootstrap incomplete"
ok "Base installed"

# --- post-chroot payload (SECURE VERSION - no sed/perl injection) ---
log "Prepare post-chroot…"
cat >/mnt/root/post-chroot.sh <<'EOS'
set -euo pipefail
trap 'echo "[FAIL] line $LINENO"; exit 1' ERR

# Environment variables are passed securely from parent process
HN="$HOSTNAME"; TZ="$TZ"; DISK="$DISK"; RP="$POOL_R"; BP="$POOL_B"
ARC="$ARC_MAX_BYTES"; NEW_USER="$NEW_USER"; NEW_USER_SUDO="$NEW_USER_SUDO"
SSH_IMPORT_IDS="$SSH_IMPORT_IDS"; SSH_AUTHORIZED_KEYS="$SSH_AUTHORIZED_KEYS"; SSH_AUTHORIZED_KEYS_URLS="$SSH_AUTHORIZED_KEYS_URLS"
PERMIT_ROOT_LOGIN="$PERMIT_ROOT_LOGIN"; PASSWORD_AUTH="$PASSWORD_AUTH"

install -d -m 0755 /var/cache/apt/archives/partial /var/lib/apt/lists/partial /var/lib/dpkg/updates /var/log/apt
[ -s /var/lib/dpkg/status ] || :> /var/lib/dpkg/status

echo "$HN" >/etc/hostname
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf "127.0.0.1 localhost\n127.0.1.1 $HN\n" >/etc/hosts

cat >/etc/apt/sources.list <<SL
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
SL
export DEBIAN_FRONTEND=noninteractive
apt-get -y update
apt-get -y install locales console-setup ca-certificates curl grub-common \
  linux-image-amd64 linux-headers-amd64 \
  zfs-dkms zfsutils-linux zfs-initramfs \
  cloud-init openssh-server ssh-import-id sudo

# locales
grep -q "^en_US.UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
grep -q "^sv_SE.UTF-8" /etc/locale.gen || echo "sv_SE.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen >/dev/null 2>&1 || true
command -v update-locale >/dev/null 2>&1 && update-locale LANG=en_US.UTF-8 || true

# ensure RW + tmp
zfs set readonly=off "$RP/ROOT/debian" || true
zfs set readonly=off "$RP/var" || true
mount -o remount,rw / || true
install -d -m1777 /var/tmp /tmp

# zpool cache/hostid/bootfs
command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
zpool set bootfs="$RP/ROOT/debian" "$RP" || true

# initramfs ZFS import: SAFE (no -f, readonly, path narrowed)
cat >/etc/default/zfs <<ZDF
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
ZPOOL_IMPORT_OPTS="-N -o readonly=on"
ZPOOL_IMPORT_TIMEOUT="30"
ZFS_INITRD_POST_MODPROBE_SLEEP="3"
ZDF

# ARC cap
echo "options zfs zfs_arc_max=$ARC" >/etc/modprobe.d/zfs.conf

# make sure /etc/default/grub exists, then set zfs root + a small delay
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

# build initrd (ensure /boot mounted)
mountpoint -q /boot || zfs mount "$BP/BOOT/debian" || true
TMPDIR=/tmp update-initramfs -u

# install GRUB
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

# flip mountpoints for runtime (ignore remount failures)
zfs set mountpoint=/      "$RP/ROOT/debian" || true
zfs set mountpoint=/boot  "$BP/BOOT/debian" || true
zfs set mountpoint=/var            "$RP/var" || true
zfs set mountpoint=/var/lib        "$RP/var/lib" || true
zfs set mountpoint=/var/lib/mysql  "$RP/var/lib/mysql" || true
zfs set mountpoint=/var/vmail      "$RP/var/vmail" || true
zfs set mountpoint=/home           "$RP/home" || true
zfs set mountpoint=/srv            "$RP/srv" || true

# SSH configuration with hardened key handling
sed -i -E "s/^#?PasswordAuthentication .*/PasswordAuthentication ${PASSWORD_AUTH}/" /etc/ssh/sshd_config || true
grep -q '^PermitRootLogin' /etc/ssh/sshd_config && sed -i -E "s/^PermitRootLogin .*/PermitRootLogin ${PERMIT_ROOT_LOGIN}/" /etc/ssh/sshd_config || echo "PermitRootLogin ${PERMIT_ROOT_LOGIN}" >> /etc/ssh/sshd_config
install -d -m700 /root/.ssh; : >/root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys

# Hardened SSH key import with timeout and validation
if [ -n "$SSH_IMPORT_IDS" ]; then
  for id in $SSH_IMPORT_IDS; do
    echo "Importing SSH keys for: $id"
    timeout 30 ssh-import-id "$id" || echo "Warning: Failed to import keys for $id"
  done
fi

# Direct key insertion (secure)
if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
  echo "$SSH_AUTHORIZED_KEYS" | while IFS= read -r key; do
    [ -n "$key" ] && echo "$key" >> /root/.ssh/authorized_keys
  done
fi

# URL-based key fetching with timeout and validation
if [ -n "$SSH_AUTHORIZED_KEYS_URLS" ]; then
  for url in $SSH_AUTHORIZED_KEYS_URLS; do
    echo "Fetching SSH keys from: $url"
    if timeout 30 curl -fsSL "$url" 2>/dev/null | grep -E '^ssh-(rsa|dss|ecdsa|ed25519)' >> /root/.ssh/authorized_keys; then
      echo "Successfully fetched keys from $url"
    else
      echo "Warning: Failed to fetch keys from $url"
    fi
  done
fi

# User account setup with proper SSH key handling
if [ -n "$NEW_USER" ]; then
  id "$NEW_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$NEW_USER"
  [ "$NEW_USER_SUDO" = 1 ] && usermod -aG sudo "$NEW_USER"
  install -d -m700 "/home/$NEW_USER/.ssh"; touch "/home/$NEW_USER/.ssh/authorized_keys"; chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"; chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  
  # SSH key import for user
  if [ -n "$SSH_IMPORT_IDS" ]; then
    for id in $SSH_IMPORT_IDS; do
      echo "Importing SSH keys for user $NEW_USER: $id"
      timeout 30 sudo -u "$NEW_USER" ssh-import-id "$id" || echo "Warning: Failed to import keys for user $NEW_USER: $id"
    done
  fi
  
  # Direct keys for user
  if [ -n "$SSH_AUTHORIZED_KEYS" ]; then
    echo "$SSH_AUTHORIZED_KEYS" | while IFS= read -r key; do
      [ -n "$key" ] && echo "$key" >> "/home/$NEW_USER/.ssh/authorized_keys"
    done
  fi
  
  # URL-based keys for user
  if [ -n "$SSH_AUTHORIZED_KEYS_URLS" ]; then
    for url in $SSH_AUTHORIZED_KEYS_URLS; do
      echo "Fetching SSH keys for user $NEW_USER from: $url"
      if timeout 30 curl -fsSL "$url" 2>/dev/null | grep -E '^ssh-(rsa|dss|ecdsa|ed25519)' >> "/home/$NEW_USER/.ssh/authorized_keys"; then
        echo "Successfully fetched keys for user $NEW_USER from $url"
      else
        echo "Warning: Failed to fetch keys for user $NEW_USER from $url"
      fi
    done
  fi
fi

mkdir -p /etc/cloud/cloud.cfg.d
echo 'datasource_list: [ConfigDrive, NoCloud, Ec2]' >/etc/cloud/cloud.cfg.d/90-datasources.cfg
systemctl enable ssh zfs-import-cache zfs-mount zfs-import.target cloud-init cloud-config cloud-final cloud-init-local >/dev/null 2>&1 || true

# checks
test -s /boot/grub/grub.cfg
ls -1 /boot/initrd.img-* /boot/vmlinuz-* >/dev/null
zpool get -H -o value bootfs "$RP" | grep -q "$RP/ROOT/debian"
command -v sshd >/dev/null && sshd -t
echo "[OK] post-chroot done"
EOS

# SECURITY: Export variables to chroot environment instead of sed/perl injection
export HOSTNAME TZ DISK POOL_R POOL_B NEW_USER NEW_USER_SUDO 
export SSH_IMPORT_IDS SSH_AUTHORIZED_KEYS SSH_AUTHORIZED_KEYS_URLS 
export PERMIT_ROOT_LOGIN PASSWORD_AUTH
export ARC_MAX_BYTES=$((ARC_MAX_MB*1024*1024))
ok "post-chroot prepared"

# --- chroot run + checks ---
log "Finalize in chroot…"
for d in dev proc sys run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
mkdir -p /mnt/etc; [ -e /mnt/etc/resolv.conf ] || :>/mnt/etc/resolv.conf; mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
chroot /mnt /bin/bash /root/post-chroot.sh
chroot /mnt test -s /boot/grub/grub.cfg
chroot /mnt zpool get -H -o value bootfs "$POOL_R" | grep -q "$POOL_R/ROOT/debian"
ok "Chroot finalize OK"

# --- teardown (best-effort) ---
log "Teardown…"
umount -l /mnt/etc/resolv.conf 2>/dev/null || true
for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done
zfs list -H -o name -r "$POOL_R" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
zfs list -H -o name -r "$POOL_B" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
findmnt -R /mnt -o TARGET | tac | xargs -r -n1 umount -lf 2>/dev/null || true
zpool export -f "$POOL_B" 2>/dev/null || true
zpool export -f "$POOL_R" 2>/dev/null || true
ok "Done. Reboot."