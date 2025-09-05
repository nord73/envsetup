#!/usr/bin/env bash
# Debian 13 (trixie) ZFS-on-root on Contabo (rescue). BIOS/UEFI. Idempotent.

set -euo pipefail
[ -f .env ] && set -a && . ./.env && set +a

# ---------- CONFIG ----------
DISK="${DISK:-/dev/sda}"
HOSTNAME="${HOSTNAME:-mail1}"
TZ="${TZ:-Europe/Stockholm}"
POOL_R="${POOL_R:-rpool}"
POOL_B="${POOL_B:-bpool}"
ARC_MAX_MB="${ARC_MAX_MB:-2048}"
ENCRYPT="${ENCRYPT:-no}"             # yes|no
FORCE="${FORCE:-0}"

# SSH / user
NEW_USER="${NEW_USER:-}"             # e.g. ansible
NEW_USER_SUDO="${NEW_USER_SUDO:-1}"  # 1|0
SSH_IMPORT_IDS="${SSH_IMPORT_IDS:-}" # e.g. "gh:user1 gh:user2"
SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"
SSH_AUTHORIZED_KEYS_URLS="${SSH_AUTHORIZED_KEYS_URLS:-}"
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-prohibit-password}" # yes|no|prohibit-password
PASSWORD_AUTH="${PASSWORD_AUTH:-no}"                         # yes|no
# ---------------------------------

say(){ echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok(){  echo -e "\033[1;32m[OK]\033[0m  $*"; }
warn(){echo -e "\033[1;33m[WARN]\033[0m $*"; }
die(){ echo -e "\033[1;31m[FAIL]\033[0m $*"; exit 1; }
confirm(){ [ "$FORCE" = "1" ] && return 0; read -r -p "$1 [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]]; }

req(){ command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

BOOTLOADER=bios; [ -d /sys/firmware/efi ] && BOOTLOADER=uefi
[ "$(id -u)" -eq 0 ] || die "run as root"
[ -b "$DISK" ] || die "disk $DISK not found"

say "Rescue boot mode: $BOOTLOADER"
say "This will WIPE $DISK and install Debian 13 on ZFS-root."
confirm "Proceed on $DISK?" || die "aborted"

# ----- Rescue prereqs (fix live-initramfs breakage) -----
say "Installing rescue prerequisites…"
source /etc/os-release; CODENAME=${VERSION_CODENAME:-bookworm}
cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian ${CODENAME} main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${CODENAME}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${CODENAME}-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${CODENAME}-backports main contrib non-free non-free-firmware
EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Divert update-initramfs in rescue to avoid /run/live/medium writes
if ! dpkg-divert --list | grep -q '/usr/sbin/update-initramfs$'; then
  dpkg-divert --local --rename --add /usr/sbin/update-initramfs || true
fi
printf '#!/bin/sh\nexit 0\n' >/usr/sbin/update-initramfs
chmod +x /usr/sbin/update-initramfs

apt-get install -y dkms build-essential "linux-headers-$(uname -r)" || die "headers/dkms failed"
apt-get install -y zfs-dkms || die "zfs-dkms failed"
depmod -a
modprobe zfs || die "ZFS module not loaded"
apt-get install -y zfsutils-linux debootstrap gdisk dosfstools || die "rescue utils failed"
ok "Rescue prerequisites OK."

# ----- Clean up any leftover pools with the same names -----
for p in "$POOL_B" "$POOL_R"; do
  if zpool list -H -o name | grep -qx "$p"; then
    warn "Pool $p exists; destroying (you confirmed wipe)."
    zpool destroy -f "$p" || true
  fi
done

# ----- Partition disk -----
say "Partitioning $DISK…"
sgdisk -Z "$DISK"
if [ "$BOOTLOADER" = "uefi" ]; then
  sgdisk -n1:1M:+1G -t1:EF00 "$DISK"
  sgdisk -n2:0:+2G  -t2:BF01 "$DISK"
  sgdisk -n3:0:0    -t3:BF01 "$DISK"
  mkfs.vfat -F32 "${DISK}1"
else
  sgdisk -n1:1M:+1M -t1:EF02 "$DISK"  # BIOS-boot
  sgdisk -n2:0:+2G  -t2:BF01 "$DISK"
  sgdisk -n3:0:0    -t3:BF01 "$DISK"
fi
ok "Disk partitioned."

# ----- Create pools -----
say "Creating ZFS pools…"
ZFS_RPOOL_ENC=()
[ "$ENCRYPT" = "yes" ] && ZFS_RPOOL_ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase)

zpool create -f \
  -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -o compatibility=grub2 \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -O mountpoint=none -O canmount=off \
  "$POOL_B" "${DISK}2"

zpool create -f \
  -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -O mountpoint=none -O canmount=off \
  "${ZFS_RPOOL_ENC[@]}" \
  "$POOL_R" "${DISK}3"
ok "Pools created."

# ----- Datasets (idempotent) -----
ensure_ds(){ local ds="$1"; shift || true; zfs list -H -o name "$ds" >/dev/null 2>&1 || zfs create "$@" "$ds"; }

say "Creating datasets…"
ensure_ds "$POOL_R/ROOT"        -o canmount=off -o mountpoint=none
ensure_ds "$POOL_R/ROOT/debian"
ensure_ds "$POOL_B/BOOT"        -o canmount=off -o mountpoint=none
ensure_ds "$POOL_B/BOOT/debian"

# Temp mountpoints for install
zfs set mountpoint=/mnt      "$POOL_R/ROOT/debian"
zfs set mountpoint=/mnt/boot "$POOL_B/BOOT/debian"
zfs mount "$POOL_R/ROOT/debian"
mkdir -p /mnt/boot && zfs mount "$POOL_B/BOOT/debian"

# App datasets (mounted under /mnt/* for bootstrap)
ensure_ds "$POOL_R/var"                   -o mountpoint=/mnt/var
ensure_ds "$POOL_R/var/lib"               -o mountpoint=/mnt/var/lib
ensure_ds "$POOL_R/var/lib/mysql"         -o recordsize=16K -o logbias=latency -o primarycache=all -o mountpoint=/mnt/var/lib/mysql
ensure_ds "$POOL_R/var/vmail"             -o recordsize=16K -o mountpoint=/mnt/var/vmail
ensure_ds "$POOL_R/home"                  -o mountpoint=/mnt/home
ensure_ds "$POOL_R/srv"                   -o mountpoint=/mnt/srv

zfs get -H -o value mounted "$POOL_R/ROOT/debian" | grep -q yes || die "root not mounted"
zfs get -H -o value mounted "$POOL_B/BOOT/debian" | grep -q yes || die "boot not mounted"
ok "Datasets mounted."

# ----- Bootstrap Debian 13 -----
say "Bootstrapping Debian 13 (trixie)…"
debootstrap trixie /mnt http://deb.debian.org/debian/ || die "debootstrap failed"
[ -x /mnt/bin/sh ] || die "bootstrap incomplete"
ok "Base system ready."

# ----- Post-chroot -----
say "Preparing post-chroot…"
cat > /mnt/root/post-chroot.sh <<'EOS'
set -euo pipefail
trap 'echo "[FAIL] line $LINENO"; exit 1' ERR

HN="@HOSTNAME@"; TZ="@TZ@"; DISK="@DISK@"; RP="@POOL_R@"; BP="@POOL_B@"
ARC_MB=@ARC_MAX_MB@
NEW_USER='@NEW_USER@'; NEW_USER_SUDO='@NEW_USER_SUDO@'
SSH_IMPORT_IDS='@SSH_IMPORT_IDS@'
SSH_AUTHORIZED_KEYS='@SSH_AUTHORIZED_KEYS@'
SSH_AUTHORIZED_KEYS_URLS='@SSH_AUTHORIZED_KEYS_URLS@'
PERMIT_ROOT_LOGIN='@PERMIT_ROOT_LOGIN@'
PASSWORD_AUTH='@PASSWORD_AUTH@'

# In target?
findmnt -no SOURCE / | grep -q "${RP}/ROOT/debian" || { echo "Not in target root"; exit 1; }

# APT/dpkg dir hygiene (debootstrap sometimes lacks these)
install -d -m 0755 /var/cache/apt/archives/partial /var/lib/apt/lists/partial /var/lib/dpkg/updates /var/log/apt
[ -s /var/lib/dpkg/status ] || :> /var/lib/dpkg/status

echo "$HN" > /etc/hostname
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf '%s\n' "127.0.0.1 localhost" "127.0.1.1 $HN" > /etc/hosts

cat >/etc/apt/sources.list <<SL
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
SL
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# Locales first to silence LC_* noise
echo -e "en_US.UTF-8 UTF-8\nsv_SE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen >/dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8

apt-get install -y linux-image-amd64 linux-headers-amd64 \
  zfs-dkms zfsutils-linux zfs-initramfs \
  cloud-init openssh-server ssh-import-id sudo locales console-setup \
  ca-certificates curl

# Ensure tmp dirs + RW
zfs set readonly=off "$RP/ROOT/debian" || true
zfs set readonly=off "$RP/var" || true
mount -o remount,rw / || true
mkdir -p -m 1777 /var/tmp /tmp

# ZFS cache + hostid BEFORE initramfs
command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
zpool set bootfs="$RP/ROOT/debian" "$RP" || true

# Force import on boot to avoid "used by another system"
cat >/etc/default/zfs <<ZDF
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
ZPOOL_IMPORT_OPTS="-N -f"
ZPOOL_IMPORT_TIMEOUT="15"
ZFS_INITRD_POST_MODPROBE_SLEEP="2"
ZDF

# ARC cap
echo "options zfs zfs_arc_max=$((ARC_MB*1024*1024))" >/etc/modprobe.d/zfs.conf

# Build initrd while /boot is mounted
mountpoint -q /boot || zfs mount "$BP/BOOT/debian" || true
TMPDIR=/tmp update-initramfs -u

# GRUB
sed -ri "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=ZFS=$RP/ROOT/debian\"|" /etc/default/grub
grep -q '^GRUB_PRELOAD_MODULES' /etc/default/grub || echo 'GRUB_PRELOAD_MODULES="zfs"' >> /etc/default/grub

if [ -d /sys/firmware/efi ]; then
  apt-get install -y grub-efi-amd64 efibootmgr
  mkdir -p /boot/efi
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
else
  apt-get install -y grub-pc
  grub-install "@DISK@"
fi
update-grub
test -s /boot/grub/grub.cfg

# Flip runtime mountpoints for first boot (ignore live remount failures)
zfs set mountpoint=/      "$RP/ROOT/debian" || true
zfs set mountpoint=/boot  "$BP/BOOT/debian" || true
zfs set mountpoint=/var            "$RP/var" || true
zfs set mountpoint=/var/lib        "$RP/var/lib" || true
zfs set mountpoint=/var/lib/mysql  "$RP/var/lib/mysql" || true
zfs set mountpoint=/var/vmail      "$RP/var/vmail" || true
zfs set mountpoint=/home           "$RP/home" || true
zfs set mountpoint=/srv            "$RP/srv" || true

# SSH daemon + keys
sshd_cfg="/etc/ssh/sshd_config"
sed -i -E "s/^#?PasswordAuthentication .*/PasswordAuthentication ${PASSWORD_AUTH}/" "$sshd_cfg" || true
if grep -q '^PermitRootLogin' "$sshd_cfg"; then
  sed -i -E "s/^PermitRootLogin .*/PermitRootLogin ${PERMIT_ROOT_LOGIN}/" "$sshd_cfg"
else
  echo "PermitRootLogin ${PERMIT_ROOT_LOGIN}" >> "$sshd_cfg"
fi

mkdir -p /root/.ssh && chmod 700 /root/.ssh
touch /root/.ssh/authorized_keys && chmod 600 /root/.ssh/authorized_keys
[ -n "$SSH_IMPORT_IDS" ] && ssh-import-id $SSH_IMPORT_IDS || true
[ -n "$SSH_AUTHORIZED_KEYS" ] && printf '%s\n' $SSH_AUTHORIZED_KEYS >> /root/.ssh/authorized_keys
if [ -n "$SSH_AUTHORIZED_KEYS_URLS" ]; then
  for u in $SSH_AUTHORIZED_KEYS_URLS; do curl -fsSL "$u" >> /root/.ssh/authorized_keys || true; done
fi

if [ -n "$NEW_USER" ]; then
  id "$NEW_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$NEW_USER"
  [ "$NEW_USER_SUDO" = "1" ] && usermod -aG sudo "$NEW_USER"
  install -d -m 700 "/home/$NEW_USER/.ssh"
  touch "/home/$NEW_USER/.ssh/authorized_keys"
  chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  [ -n "$SSH_IMPORT_IDS" ] && sudo -u "$NEW_USER" ssh-import-id $SSH_IMPORT_IDS || true
  [ -n "$SSH_AUTHORIZED_KEYS" ] && printf '%s\n' $SSH_AUTHORIZED_KEYS >> "/home/$NEW_USER/.ssh/authorized_keys"
  if [ -n "$SSH_AUTHORIZED_KEYS_URLS" ]; then
    for u in $SSH_AUTHORIZED_KEYS_URLS; do curl -fsSL "$u" >> "/home/$NEW_USER/.ssh/authorized_keys" || true; done
  fi
fi

# cloud-init
mkdir -p /etc/cloud/cloud.cfg.d
echo 'datasource_list: [ConfigDrive, NoCloud, Ec2]' >/etc/cloud/cloud.cfg.d/90-datasources.cfg

systemctl enable ssh >/dev/null 2>&1 || true
systemctl enable zfs-import-cache zfs-mount zfs-import.target >/dev/null 2>&1 || true
systemctl enable cloud-init cloud-config cloud-final cloud-init-local >/dev/null 2>&1 || true
echo "[OK] post-chroot complete"
EOS

# Inject vars
sed -i "s|@HOSTNAME@|$HOSTNAME|g"              /mnt/root/post-chroot.sh
sed -i "s|@TZ@|$TZ|g"                          /mnt/root/post-chroot.sh
sed -i "s|@DISK@|$DISK|g"                      /mnt/root/post-chroot.sh
sed -i "s|@POOL_R@|$POOL_R|g"                  /mnt/root/post-chroot.sh
sed -i "s|@POOL_B@|$POOL_B|g"                  /mnt/root/post-chroot.sh
sed -i "s|@ARC_MAX_MB@|$ARC_MAX_MB|g"          /mnt/root/post-chroot.sh
sed -i "s|@NEW_USER@|$NEW_USER|g"              /mnt/root/post-chroot.sh
sed -i "s|@NEW_USER_SUDO@|$NEW_USER_SUDO|g"    /mnt/root/post-chroot.sh
sed -i "s|@SSH_IMPORT_IDS@|$SSH_IMPORT_IDS|g"  /mnt/root/post-chroot.sh
perl -0777 -pe 's/\@SSH_AUTHORIZED_KEYS\@/'"$(printf %s "$SSH_AUTHORIZED_KEYS" | sed 's/[\/&]/\\&/g')"'/g' -i /mnt/root/post-chroot.sh
sed -i "s|@SSH_AUTHORIZED_KEYS_URLS@|$SSH_AUTHORIZED_KEYS_URLS|g" /mnt/root/post-chroot.sh
sed -i "s|@PERMIT_ROOT_LOGIN@|$PERMIT_ROOT_LOGIN|g"  /mnt/root/post-chroot.sh
sed -i "s|@PASSWORD_AUTH@|$PASSWORD_AUTH|g"          /mnt/root/post-chroot.sh
ok "post-chroot prepared."

# ----- Enter chroot -----
say "Chrooting and finalizing…"
for d in dev proc sys run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
mkdir -p /mnt/etc; [ -e /mnt/etc/resolv.conf ] || :> /mnt/etc/resolv.conf
mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
chroot /mnt /bin/bash /root/post-chroot.sh

# Checks
chroot /mnt test -s /boot/grub/grub.cfg || die "GRUB cfg missing"
chroot /mnt command -v sshd >/dev/null 2>&1 || die "OpenSSH missing"
chroot /mnt zpool get -H -o value bootfs "$POOL_R" | grep -q "$POOL_R/ROOT/debian" || die "bootfs not set"
ok "Chroot finalize OK."

# ----- Teardown -----
say "Unmounting and exporting pools…"
cd /

# kill anything still in /mnt to avoid busy exports
if command -v lsof >/dev/null 2>&1; then
  lsof +f -- /mnt | awk 'NR>1{print $2}' | sort -u | xargs -r kill -9
fi

umount -l /mnt/etc/resolv.conf 2>/dev/null || true
for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done
# Unmount ZFS datasets (deepest-first)
zfs list -H -o name -r "$POOL_R" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
zfs list -H -o name -r "$POOL_B" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
findmnt -R /mnt -o TARGET | tac | xargs -r -n1 umount -lf

# Try exports; if still busy, warn (boot will succeed due to -f import in initramfs)
zpool export -f "$POOL_B" 2>/dev/null || warn "could not export $POOL_B (ok)"
zpool export -f "$POOL_R" 2>/dev/null || warn "could not export $POOL_R (ok)"

ok "Install complete. Reboot to disk."
