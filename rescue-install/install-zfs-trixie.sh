#!/usr/bin/env bash
# Debian 13 (trixie) ZFS-on-root (Contabo rescue). With SSH key import.
set -euo pipefail
[ -f .env ] && set -a && . ./.env && set +a

# --- CONFIG ---
DISK="${DISK:-/dev/sda}"
HOSTNAME="${HOSTNAME:-mail1}"
TZ="${TZ:-Europe/Stockholm}"
POOL_R="${POOL_R:-rpool}"
POOL_B="${POOL_B:-bpool}"
ARC_MAX_MB="${ARC_MAX_MB:-2048}"
ENCRYPT="${ENCRYPT:-no}"                          # yes|no
CI_DATASOURCES="${CI_DATASOURCES:-[ConfigDrive,NoCloud,Ec2]}"
FORCE="${FORCE:-0}"

# SSH bootstrap
NEW_USER="${NEW_USER:-}"                           # e.g. ansible
NEW_USER_SUDO="${NEW_USER_SUDO:-1}"                # 1|0
SSH_IMPORT_IDS="${SSH_IMPORT_IDS:-}"               # e.g. "gh:YourGitHub gh:Other"
SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"     # inline pubkeys
SSH_AUTHORIZED_KEYS_URLS="${SSH_AUTHORIZED_KEYS_URLS:-}"  # URLs to pubkey lists
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-prohibit-password}"  # yes|no|prohibit-password
PASSWORD_AUTH="${PASSWORD_AUTH:-no}"               # yes|no
# -------------

say(){ echo -e "\033[1;34m[INFO]\033[0m $*"; }
ok(){  echo -e "\033[1;32m[OK]\033[0m  $*"; }
die(){ echo -e "\033[1;31m[FAIL]\033[0m $*"; exit 1; }
confirm(){ [ "$FORCE" = "1" ] && return 0; read -r -p "$1 [y/N]: " a; [[ "$a" =~ ^[Yy]$ ]]; }

# Preflight
[ "$(id -u)" -eq 0 ] || die "Run as root."
[ -b "$DISK" ] || die "Disk $DISK not found."
BOOTLOADER=bios; [ -d /sys/firmware/efi ] && BOOTLOADER=uefi
say "Boot mode (rescue): $BOOTLOADER"
say "About to WIPE $DISK and install Debian 13 (trixie) on ZFS-root."
confirm "Proceed on $DISK?" || die "Aborted."

# --- Rescue prereqs (with initramfs diversion) ---
say "Installing rescue prerequisites…"
export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true
source /etc/os-release; CODENAME=${VERSION_CODENAME:-bookworm}
cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian ${CODENAME} main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security ${CODENAME}-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${CODENAME}-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian ${CODENAME}-backports main contrib non-free non-free-firmware
EOF
apt-get update -y

# Hard divert: prevent live image from writing initrd to /run/live/medium
if ! dpkg-divert --list | grep -q '/usr/sbin/update-initramfs$'; then
  dpkg-divert --local --rename --add /usr/sbin/update-initramfs || true
fi
printf '#!/bin/sh\nexit 0\n' >/usr/sbin/update-initramfs
chmod +x /usr/sbin/update-initramfs

# Build ZFS for running kernel, THEN load it
apt-get install -y dkms build-essential "linux-headers-$(uname -r)" || die "Headers/DKMS failed"
apt-get install -y zfs-dkms || die "zfs-dkms failed"
depmod -a
modprobe zfs || true  # module should now exist
apt-get install -y zfsutils-linux debootstrap gdisk dosfstools || die "rescue utils failed"
modprobe zfs || die "ZFS module not loaded in rescue"
ok "Rescue prereqs ready."

# --- Partition ---
say "Partitioning $DISK…"
sgdisk -Z "$DISK"
if [ "$BOOTLOADER" = "uefi" ]; then
  sgdisk -n1:1M:+1G -t1:EF00 "$DISK" || die "EFI part failed"
  sgdisk -n2:0:+2G  -t2:BF01 "$DISK" || die "bpool part failed"
  sgdisk -n3:0:0    -t3:BF01 "$DISK" || die "rpool part failed"
  mkfs.vfat -F32 "${DISK}1"
else
  sgdisk -n1:1M:+1M -t1:EF02 "$DISK" || die "BIOS part failed"
  sgdisk -n2:0:+2G  -t2:BF01 "$DISK" || die "bpool part failed"
  sgdisk -n3:0:0    -t3:BF01 "$DISK" || die "rpool part failed"
fi
ok "Disk partitioned."

# --- Pools ---
say "Creating ZFS pools…"
ZFS_RPOOL_ENC=()
[ "$ENCRYPT" = "yes" ] && ZFS_RPOOL_ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase)
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -o compatibility=grub2 -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"
zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -O mountpoint=none -O canmount=off "${ZFS_RPOOL_ENC[@]}" "$POOL_R" "${DISK}3"
ok "Pools created."

# ----- Datasets (idempotent) -----
ensure_ds() {  # usage: ensure_ds <dataset> [zfs create options...]
  local ds="$1"; shift || true
  zfs list -H -o name "$ds" >/dev/null 2>&1 || zfs create "$@" "$ds"
}

ensure_ds "$POOL_R/ROOT"        -o canmount=off -o mountpoint=none
ensure_ds "$POOL_R/ROOT/debian"
ensure_ds "$POOL_B/BOOT"        -o canmount=off -o mountpoint=none
ensure_ds "$POOL_B/BOOT/debian"

ensure_ds "$POOL_R/var"                     -o mountpoint=/mnt/var
ensure_ds "$POOL_R/var/lib"                 -o mountpoint=/mnt/var/lib
ensure_ds "$POOL_R/var/lib/mysql"           -o recordsize=16K -o logbias=latency -o primarycache=all -o mountpoint=/mnt/var/lib/mysql
ensure_ds "$POOL_R/var/vmail"               -o recordsize=16K -o mountpoint=/mnt/var/vmail
ensure_ds "$POOL_R/home"                    -o mountpoint=/mnt/home
ensure_ds "$POOL_R/srv"                     -o mountpoint=/mnt/srv

# ----- Mount roots (idempotent) -----
ensure_mount() { # usage: ensure_mount <dataset> <mountpoint>
  local ds="$1" mp="$2"
  zfs set mountpoint="$mp" "$ds"
  if [ "$(zfs get -H -o value mounted "$ds")" != "yes" ]; then
    zfs mount "$ds"
  fi
}

ensure_mount "$POOL_R/ROOT/debian" /mnt
mkdir -p /mnt/boot
ensure_mount "$POOL_B/BOOT/debian" /mnt/boot

# sanity
zfs get -H -o value mounted "$POOL_R/ROOT/debian" | grep -q yes || die "root not mounted"
zfs get -H -o value mounted "$POOL_B/BOOT/debian" | grep -q yes || die "boot not mounted"

# --- Bootstrap Trixie ---
say "Bootstrapping Debian 13 (trixie)…"
debootstrap trixie /mnt http://deb.debian.org/debian/ || die "debootstrap failed"
[ -x /mnt/bin/sh ] || die "bootstrap incomplete"
ok "Base system ready."

# --- Post-chroot prep ---
say "Preparing post-chroot…"
cat > /mnt/root/post-chroot.sh <<'EOS'
set -euo pipefail
HN="@HOSTNAME@"; TZ="@TZ@"; DISK="@DISK@"; RP="@POOL_R@"; BP="@POOL_B@"
ARC_MB=@ARC_MAX_MB@; CI_LIST='@CI_DATASOURCES@'
NEW_USER='@NEW_USER@'; NEW_USER_SUDO='@NEW_USER_SUDO@'
SSH_IMPORT_IDS='@SSH_IMPORT_IDS@'
SSH_AUTHORIZED_KEYS='@SSH_AUTHORIZED_KEYS@'
SSH_AUTHORIZED_KEYS_URLS='@SSH_AUTHORIZED_KEYS_URLS@'
PERMIT_ROOT_LOGIN='@PERMIT_ROOT_LOGIN@'; PASSWORD_AUTH='@PASSWORD_AUTH@'

findmnt -no SOURCE / | grep -q "${RP}/ROOT/debian" || { echo "Not in target root"; exit 1; }

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
apt-get install -y \
  linux-image-amd64 linux-headers-amd64 \
  zfs-dkms zfsutils-linux zfs-initramfs \
  cloud-init openssh-server ssh-import-id sudo locales console-setup \
  ca-certificates curl

echo -e "en_US.UTF-8 UTF-8\nsv_SE.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen >/dev/null 2>&1 || true
update-locale LANG=en_US.UTF-8

# Runtime mountpoints
zfs set mountpoint=/      "$RP/ROOT/debian"
zfs set mountpoint=/boot  "$BP/BOOT/debian"
zfs set mountpoint=/var            "$RP/var"
zfs set mountpoint=/var/lib        "$RP/var/lib"
zfs set mountpoint=/var/lib/mysql  "$RP/var/lib/mysql"
zfs set mountpoint=/var/vmail      "$RP/var/vmail"
zfs set mountpoint=/home           "$RP/home"
zfs set mountpoint=/srv            "$RP/srv"

command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true

echo "options zfs zfs_arc_max=$((ARC_MB*1024*1024))" >/etc/modprobe.d/zfs.conf

# ensure writable + temp dirs
zfs set readonly=off @POOL_R@/ROOT/debian || true
zfs set readonly=off @POOL_R@/var || true
mount -o remount,rw / || true
mkdir -p -m 1777 /var/tmp /tmp
chmod 1777 /var/tmp /tmp
# guarantee /boot is mounted while generating initrd
mountpoint -q /boot || zfs mount @POOL_B@/BOOT/debian || true
TMPDIR=/tmp update-initramfs -u

sed -ri "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=ZFS=$RP/ROOT/debian\"|" /etc/default/grub
grep -q '^GRUB_PRELOAD_MODULES' /etc/default/grub || echo 'GRUB_PRELOAD_MODULES="zfs"' >> /etc/default/grub

if [ -d /sys/firmware/efi ]; then
  apt-get install -y grub-efi-amd64 efibootmgr
  [ -b "@DISK@1" ] && EFI_UUID=$(blkid -s UUID -o value "@DISK@1" || true) || true
  if [ -n "${EFI_UUID:-}" ]; then
    grep -q '/boot/efi' /etc/fstab || echo "UUID=$EFI_UUID /boot/efi vfat umask=0077 0 1" >> /etc/fstab
    mkdir -p /boot/efi
  fi
  grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
else
  apt-get install -y grub-pc
  grub-install "@DISK@"
fi
update-grub
test -s /boot/grub/grub.cfg

# SSH hardening + keys
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

mkdir -p /etc/cloud/cloud.cfg.d
printf "datasource_list: %s\n" "$CI_LIST" >/etc/cloud/cloud.cfg.d/90-datasources.cfg

if [ -n "$NEW_USER" ] || [ -n "$SSH_IMPORT_IDS" ]; then
  cat >/etc/cloud/cloud.cfg.d/91-users.cfg <<CIU
users:
  - default
CIU
  if [ -n "$NEW_USER" ]; then
cat >>/etc/cloud/cloud.cfg.d/91-users.cfg <<CIU
  - name: $NEW_USER
    lock_passwd: true
    groups: [sudo]
    sudo: ALL=(ALL) NOPASSWD:ALL
CIU
  fi
  if [ -n "$SSH_IMPORT_IDS" ]; then
    echo "ssh_import_id:" >>/etc/cloud/cloud.cfg.d/91-users.cfg
    for id in $SSH_IMPORT_IDS; do echo "  - \"$id\"" >>/etc/cloud/cloud.cfg.d/91-users.cfg; done
  fi
fi

# Enable services (symlinks ok in chroot)
systemctl enable ssh >/dev/null 2>&1 || true
systemctl enable zfs-import-cache zfs-mount zfs-import.target >/dev/null 2>&1 || true
systemctl enable cloud-init cloud-config cloud-final cloud-init-local >/dev/null 2>&1 || true
echo "[OK] post-chroot complete"
EOS

# inject vars
sed -i "s|@HOSTNAME@|$HOSTNAME|g"              /mnt/root/post-chroot.sh
sed -i "s|@TZ@|$TZ|g"                          /mnt/root/post-chroot.sh
sed -i "s|@DISK@|$DISK|g"                      /mnt/root/post-chroot.sh
sed -i "s|@POOL_R@|$POOL_R|g"                  /mnt/root/post-chroot.sh
sed -i "s|@POOL_B@|$POOL_B|g"                  /mnt/root/post-chroot.sh
sed -i "s|@ARC_MAX_MB@|$ARC_MAX_MB|g"          /mnt/root/post-chroot.sh
sed -i "s|@CI_DATASOURCES@|$CI_DATASOURCES|g"  /mnt/root/post-chroot.sh
sed -i "s|@NEW_USER@|$NEW_USER|g"              /mnt/root/post-chroot.sh
sed -i "s|@NEW_USER_SUDO@|$NEW_USER_SUDO|g"    /mnt/root/post-chroot.sh
sed -i "s|@SSH_IMPORT_IDS@|$SSH_IMPORT_IDS|g"  /mnt/root/post-chroot.sh
perl -0777 -pe 's/\@SSH_AUTHORIZED_KEYS\@/'"$(printf %s "$SSH_AUTHORIZED_KEYS" | sed 's/[\/&]/\\&/g')"'/g' -i /mnt/root/post-chroot.sh
sed -i "s|@SSH_AUTHORIZED_KEYS_URLS@|$SSH_AUTHORIZED_KEYS_URLS|g" /mnt/root/post-chroot.sh
sed -i "s|@PERMIT_ROOT_LOGIN@|$PERMIT_ROOT_LOGIN|g"  /mnt/root/post-chroot.sh
sed -i "s|@PASSWORD_AUTH@|$PASSWORD_AUTH|g"          /mnt/root/post-chroot.sh
ok "post-chroot prepared."

# --- Chroot finalize ---
say "Chrooting and finalizing…"
for d in dev proc sys run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
mkdir -p /mnt/etc; [ -e /mnt/etc/resolv.conf ] || :> /mnt/etc/resolv.conf
mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
chroot /mnt /bin/bash /root/post-chroot.sh

# Checks
chroot /mnt test -s /boot/grub/grub.cfg || die "GRUB cfg missing"
chroot /mnt command -v sshd >/dev/null 2>&1 || die "OpenSSH missing"
[ -n "$NEW_USER" ] && chroot /mnt id "$NEW_USER" >/dev/null 2>&1 || true
ok "Chroot finalize OK."

# --- Teardown ---
say "Unmounting and exporting pools…"
cd /
lsof +f -- /mnt | awk 'NR>1{print $2}' | sort -u | xargs -r kill -9
umount -l /mnt/etc/resolv.conf 2>/dev/null || true
for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done
for ds in "$POOL_R/var/lib/mysql" "$POOL_R/var/lib" "$POOL_R/var/vmail" "$POOL_R/var" "$POOL_R/home" "$POOL_R/srv" "$POOL_B/BOOT/debian" "$POOL_R/ROOT/debian"; do
  zfs unmount -f "$ds" 2>/dev/null || true
done
findmnt -R /mnt -o TARGET | tac | xargs -r -n1 umount -lf
zpool export -f "$POOL_B"
zpool export -f "$POOL_R"
ok "Install complete. Reboot to Debian 13 (trixie) on ZFS-root."
