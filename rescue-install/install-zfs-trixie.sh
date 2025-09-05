#!/usr/bin/env bash
set -Eeuo pipefail

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
  TZ                Timezone (default: UTC)
  POOL_R            Root pool name (default: rpool)
  POOL_B            Boot pool name (default: bpool)
  ARC_MAX_MB        ZFS ARC max size in MB (default: 2048)
  ENCRYPT           Enable encryption (yes|no, default: no)
  FORCE             Skip confirmations (0|1, default: 1)
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

# --- cfg (override via .env) ---
[ -f .env ] && set -a && . ./.env && set +a

# Auto-detect disk if not set
auto_detect_disk() {
  local candidates
  candidates=$(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk" {print "/dev/"$1" "$2}' | sort -k2 -hr)
  
  if [ -n "$candidates" ]; then
    local selected_disk
    selected_disk=$(echo "$candidates" | head -1 | awk '{print $1}')
    [ "$DEBUG" = "1" ] && echo "[DEBUG] Available disks: $candidates" >&2
    [ "$DEBUG" = "1" ] && echo "[DEBUG] Auto-selected disk: $selected_disk" >&2
    echo "$selected_disk"
  else
    echo "/dev/sda"  # fallback
  fi
}

DISK="${DISK:-$(auto_detect_disk)}"
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

# --- utils ---
b() { printf '\033[1m%s\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }
ask(){ [ "$FORCE" = 1 ] && return 0; read -r -p "$1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]; }

trap 'die "line $LINENO"' ERR
[ "$(id -u)" -eq 0 ] || die "run as root"

# Enhanced disk validation
if [ ! -b "$DISK" ]; then
  die "disk $DISK missing. Available disks: $(lsblk -dn -o NAME,SIZE,TYPE | awk '$3=="disk" {print "/dev/"$1" ("$2")"}')"
fi

# Show disk info for confirmation
DISK_INFO=$(lsblk -dn -o NAME,SIZE,MODEL "$DISK" 2>/dev/null | tail -1)
[ "$DEBUG" = "1" ] && echo "[DEBUG] Selected disk: $DISK_INFO"

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

# --- 1) partition ---
b "Partitioning $DISK"
sgdisk -Z "$DISK"
if [ "$BOOTMODE" = uefi ]; then
  # Align partitions to 1MiB boundaries for optimal SSD performance
  sgdisk -a 2048 -n1:1M:+1G -t1:EF00 "$DISK"
  sgdisk -a 2048 -n2:0:+2G -t2:BF01 "$DISK" 
  sgdisk -a 2048 -n3:0:0 -t3:BF01 "$DISK"
  mkfs.vfat -F32 -n EFI "${DISK}1"
else
  sgdisk -a 2048 -n1:1M:+1M -t1:EF02 "$DISK"
  sgdisk -a 2048 -n2:0:+2G -t2:BF01 "$DISK" 
  sgdisk -a 2048 -n3:0:0 -t3:BF01 "$DISK"
fi
ok "Partitioned"

# --- 2) pools ---
b "Creating ZFS pools"
[ "$ENCRYPT" = yes ] && ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase) || ENC=()
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -o compatibility=grub2 -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
  -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
  -O mountpoint=none -O canmount=off "${ENC[@]}" "$POOL_R" "${DISK}3"
ok "Pools created"

# --- 3) datasets + temp mounts ---
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

# --- 4) debootstrap ---
b "Debootstrap trixie"
debootstrap trixie /mnt http://deb.debian.org/debian/
[ -x /mnt/bin/sh ] || die "bootstrap incomplete"
ok "Base system"

# --- 5) post-chroot payload (NO mountpoint flips here) ---
b "Prepare post-chroot"
cat >/mnt/root/post-chroot.sh <<'EOS'
set -Eeuo pipefail
trap 'echo "[FAIL] line $LINENO"; exit 1' ERR

# Environment variables will be passed from parent shell
# This eliminates the sed/perl injection vulnerability
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
apt-get -y install locales console-setup ca-certificates curl \
  linux-image-amd64 linux-headers-amd64 \
  zfs-dkms zfsutils-linux zfs-initramfs \
  openssh-server ssh-import-id sudo grub-common cloud-init

# locales before update-locale
grep -q "^en_US.UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen >/dev/null 2>&1 || true
command -v update-locale >/dev/null 2>&1 && update-locale LANG=en_US.UTF-8 || true

# ensure RW env + tmp
zfs set readonly=off "$RP/ROOT/debian" >/dev/null 2>&1 || true
zfs set readonly=off "$RP/var"         >/dev/null 2>&1 || true

mount -o remount,rw / || true
install -d -m1777 /var/tmp /tmp

# hostid + cache + bootfs
command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
zpool set bootfs="$RP/ROOT/debian" "$RP" || true

# import policy for initramfs (safe; no -f)
cat >/etc/default/zfs <<ZDF
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
ZPOOL_IMPORT_OPTS="-N"
ZPOOL_IMPORT_TIMEOUT="30"
ZFS_INITRD_POST_MODPROBE_SLEEP="2"
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
  grub-install "@DISK@"
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

# Hardened SSH key import with timeout and validation
if [ -n "$SSH_IMPORT_IDS" ]; then
  echo "[INFO] Importing SSH keys for root: $SSH_IMPORT_IDS"
  timeout 30 ssh-import-id $SSH_IMPORT_IDS || echo "[WARN] ssh-import-id failed or timed out for root"
fi

# Add direct SSH keys if provided
if [ -n "$AUTH_KEYS" ]; then
  echo "[INFO] Adding direct SSH keys for root"
  printf '%s\n' $AUTH_KEYS >>/root/.ssh/authorized_keys
fi

# Download SSH keys from URLs with timeout and validation
if [ -n "$AUTH_URLS" ]; then
  echo "[INFO] Downloading SSH keys from URLs for root"
  for u in $AUTH_URLS; do 
    if curl --connect-timeout 10 --max-time 30 -fsSL "$u" >>/root/.ssh/authorized_keys; then
      echo "[INFO] Successfully downloaded keys from $u"
    else
      echo "[WARN] Failed to download keys from $u"
    fi
  done
fi

if [ -n "$NEW_USER" ]; then
  echo "[INFO] Creating user: $NEW_USER"
  id "$NEW_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$NEW_USER"
  [ "$NEW_USER_SUDO" = "1" ] && usermod -aG sudo "$NEW_USER"
  install -d -m700 "/home/$NEW_USER/.ssh"
  : >"/home/$NEW_USER/.ssh/authorized_keys"; chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"

  # Hardened SSH key import for user
  if [ -n "$SSH_IMPORT_IDS" ]; then
    echo "[INFO] Importing SSH keys for $NEW_USER: $SSH_IMPORT_IDS"
    timeout 30 runuser -u "$NEW_USER" -- ssh-import-id $SSH_IMPORT_IDS || echo "[WARN] ssh-import-id failed or timed out for $NEW_USER"
  fi
  
  if [ -n "$AUTH_KEYS" ]; then
    echo "[INFO] Adding direct SSH keys for $NEW_USER"
    printf '%s\n' $AUTH_KEYS >>"/home/$NEW_USER/.ssh/authorized_keys"
  fi
  
  if [ -n "$AUTH_URLS" ]; then
    echo "[INFO] Downloading SSH keys from URLs for $NEW_USER"
    for u in $AUTH_URLS; do 
      if curl --connect-timeout 10 --max-time 30 -fsSL "$u" >>"/home/$NEW_USER/.ssh/authorized_keys"; then
        echo "[INFO] Successfully downloaded keys from $u for $NEW_USER"
      else
        echo "[WARN] Failed to download keys from $u for $NEW_USER"
      fi
    done
  fi
  
  # Ensure proper ownership
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
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

# Export all variables for secure environment passing
export HOSTNAME TZ DISK POOL_R POOL_B ARC_BYTES NEW_USER NEW_USER_SUDO
export SSH_IMPORT_IDS SSH_AUTHORIZED_KEYS SSH_AUTHORIZED_KEYS_URLS 
export PERMIT_ROOT_LOGIN PASSWORD_AUTH

# Calculate ARC bytes
export ARC_BYTES=$((ARC_MAX_MB*1024*1024))

ok "post-chroot prepared"

# --- 6) run post-chroot ---
b "Finalize in chroot"
for d in dev proc sys run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
mkdir -p /mnt/etc; [ -e /mnt/etc/resolv.conf ] || : >/mnt/etc/resolv.conf
mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
chroot /mnt /bin/bash /root/post-chroot.sh
chroot /mnt test -s /boot/grub/grub.cfg
chroot /mnt /bin/bash -lc 'command -v sshd && sshd -t'
ok "Chroot finalize OK"

# --- 7) teardown (unmount first, THEN set runtime mountpoints), export ---
b "Teardown + runtime mountpoints"
umount -l /mnt/etc/resolv.conf 2>/dev/null || true
for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done

# --- 7) teardown (unmount first, THEN set runtime mountpoints), export ---
b "Teardown + runtime mountpoints"
umount -l /mnt/etc/resolv.conf 2>/dev/null || true
for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done

# Enhanced cleanup with retries and process termination
for attempt in 1 2 3; do
  [ "$DEBUG" = "1" ] && echo "[DEBUG] Cleanup attempt $attempt"
  
  # Kill any processes using /mnt
  fuser -km /mnt 2>/dev/null || true
  sleep 2
  
  # Unmount datasets cleanly with retries
  if zfs list -H -o name -r "$POOL_R" 2>/dev/null | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null; then
    [ "$DEBUG" = "1" ] && echo "[DEBUG] Root pool unmounted successfully"
  fi
  
  if zfs list -H -o name -r "$POOL_B" 2>/dev/null | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null; then
    [ "$DEBUG" = "1" ] && echo "[DEBUG] Boot pool unmounted successfully"
  fi
  
  # Check if unmount was successful
  if ! mountpoint -q /mnt 2>/dev/null; then
    break
  fi
  
  [ "$attempt" -eq 3 ] && echo "[WARN] Some filesystems may still be mounted"
  sleep 2
done

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

echo "If initramfs prompts:  zpool import -N -R /root -d /dev/disk/by-id rpool && zfs mount -a && exit"
