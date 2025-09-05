#!/usr/bin/env bash
set -euo pipefail
[ -f .env ] && set -a && . ./.env && set +a

# --- cfg ---
DISK=${DISK:-/dev/sda}; HOSTNAME=${HOSTNAME:-mail1}; TZ=${TZ:-Europe/Stockholm}
POOL_R=${POOL_R:-rpool}; POOL_B=${POOL_B:-bpool}; ARC_MAX_MB=${ARC_MAX_MB:-2048}
ENCRYPT=${ENCRYPT:-no}; FORCE=${FORCE:-0}
NEW_USER=${NEW_USER:-}; NEW_USER_SUDO=${NEW_USER_SUDO:-1}
SSH_IMPORT_IDS=${SSH_IMPORT_IDS:-}; SSH_AUTHORIZED_KEYS=${SSH_AUTHORIZED_KEYS:-}
SSH_AUTHORIZED_KEYS_URLS=${SSH_AUTHORIZED_KEYS_URLS:-}
PERMIT_ROOT_LOGIN=${PERMIT_ROOT_LOGIN:-prohibit-password}; PASSWORD_AUTH=${PASSWORD_AUTH:-no}
# ----------

log(){ printf "\033[1;34m[INFO]\033[0m %s\n" "$*"; }
ok(){  printf "\033[1;32m[OK]\033[0m  %s\n" "$*"; }
die(){ printf "\033[1;31m[FAIL]\033[0m %s\n" "$*"; exit 1; }
ask(){ [ "$FORCE" = 1 ] && return 0; read -r -p "$1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]; }

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

# Check for existing pools that might need importing before proceeding
log "Checking for existing ZFS pools…"
if zpool import -d "$DISK" >/dev/null 2>&1; then
  # Pools exist on disk but aren't imported
  log "Found existing pools on $DISK"
  available_pools=$(zpool import -d "$DISK" 2>/dev/null | grep -E '^\s+pool:' | awk '{print $2}' || true)
  for pool in $available_pools; do
    if [[ "$pool" == "$POOL_R" || "$pool" == "$POOL_B" ]]; then
      log "Found existing target pool $pool, will handle during pool creation phase"
    fi
  done
fi

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

# Check if pools already exist and handle gracefully
if zpool list "$POOL_B" >/dev/null 2>&1; then
  log "Pool $POOL_B already exists, checking import status…"
  if ! zpool status "$POOL_B" >/dev/null 2>&1; then
    log "Importing existing pool $POOL_B with force…"
    zpool import -f -N -d "${DISK}2" "$POOL_B" || die "Failed to import existing pool $POOL_B"
  fi
else
  # Try to import from disk if it exists there but not in pool list
  if zpool import -d "${DISK}2" -N "$POOL_B" >/dev/null 2>&1 || zpool import -f -d "${DISK}2" -N "$POOL_B" >/dev/null 2>&1; then
    log "Imported existing pool $POOL_B from disk"
  else
    log "Creating new pool $POOL_B"
    zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
      -o compatibility=grub2 -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
      -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"
  fi
fi

if zpool list "$POOL_R" >/dev/null 2>&1; then
  log "Pool $POOL_R already exists, checking import status…"
  if ! zpool status "$POOL_R" >/dev/null 2>&1; then
    log "Importing existing pool $POOL_R with force…"
    zpool import -f -N -d "${DISK}3" "$POOL_R" || die "Failed to import existing pool $POOL_R"
  fi
else
  # Try to import from disk if it exists there but not in pool list
  if zpool import -d "${DISK}3" -N "$POOL_R" >/dev/null 2>&1 || zpool import -f -d "${DISK}3" -N "$POOL_R" >/dev/null 2>&1; then
    log "Imported existing pool $POOL_R from disk"
  else
    log "Creating new pool $POOL_R"
    zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
      -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
      -O mountpoint=none -O canmount=off "${ENC[@]}" "$POOL_R" "${DISK}3"
  fi
fi
ok "Pools ready"

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

# --- post-chroot payload ---
log "Prepare post-chroot…"
cat >/mnt/root/post-chroot.sh <<'EOS'
set -euo pipefail
trap 'echo "[FAIL] line $LINENO"; exit 1' ERR
HN="@HOSTNAME@"; TZ="@TZ@"; DISK="@DISK@"; RP="@POOL_R@"; BP="@POOL_B@"
ARC=@ARC@; NEW_USER='@NEW_USER@'; NEW_USER_SUDO='@NEW_USER_SUDO@'
SSH_IMPORT_IDS='@SSH_IMPORT_IDS@'; AUTH_KEYS='@AUTH_KEYS@'; AUTH_URLS='@AUTH_URLS@'
PERMIT='@PERMIT@'; PASSAUTH='@PASSAUTH@'

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
# Ensure consistent hostid to avoid import conflicts
command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
# If hostid is problematic, generate a new one
if [ ! -f /etc/hostid ] || [ "$(stat -c %s /etc/hostid)" -ne 4 ]; then
  zgenhostid >/dev/null 2>&1 || true
fi
zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
zpool set bootfs="$RP/ROOT/debian" "$RP" || true

# initramfs ZFS import: SAFE (no -f, readonly, path narrowed)
# Note: In case of hostid conflicts, allow force import in initramfs
cat >/etc/default/zfs <<ZDF
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
ZPOOL_IMPORT_OPTS="-N -o readonly=on"
ZPOOL_IMPORT_TIMEOUT="30"
ZFS_INITRD_POST_MODPROBE_SLEEP="3"
ZFS_INITRD_PRE_MOUNTROOT_SLEEP="3"
ZDF

# ARC cap
echo "options zfs zfs_arc_max=$((ARC))" >/etc/modprobe.d/zfs.conf

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
  grub-install "@DISK@"
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

# SSH
sed -i -E "s/^#?PasswordAuthentication .*/PasswordAuthentication ${PASSAUTH}/" /etc/ssh/sshd_config || true
grep -q '^PermitRootLogin' /etc/ssh/sshd_config && sed -i -E "s/^PermitRootLogin .*/PermitRootLogin ${PERMIT}/" /etc/ssh/sshd_config || echo "PermitRootLogin ${PERMIT}" >> /etc/ssh/sshd_config
install -d -m700 /root/.ssh; : >/root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
[ -n "$SSH_IMPORT_IDS" ] && ssh-import-id $SSH_IMPORT_IDS || true
[ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>/root/.ssh/authorized_keys
if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>/root/.ssh/authorized_keys || true; done; fi

if [ -n "$NEW_USER" ]; then
  id "$NEW_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$NEW_USER"
  [ "$NEW_USER_SUDO" = 1 ] && usermod -aG sudo "$NEW_USER"
  install -d -m700 "/home/$NEW_USER/.ssh"; touch "/home/$NEW_USER/.ssh/authorized_keys"; chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"; chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  [ -n "$SSH_IMPORT_IDS" ] && sudo -u "$NEW_USER" ssh-import-id $SSH_IMPORT_IDS || true
  [ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>"/home/$NEW_USER/.ssh/authorized_keys"
  if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>"/home/$NEW_USER/.ssh/authorized_keys" || true; done; fi
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

# inject vars
sed -i "s|@HOSTNAME@|$HOSTNAME|g; s|@TZ@|$TZ|g; s|@DISK@|$DISK|g; s|@POOL_R@|$POOL_R|g; s|@POOL_B@|$POOL_B|g" /mnt/root/post-chroot.sh
sed -i "s|@ARC@|$((ARC_MAX_MB*1024*1024))|g" /mnt/root/post-chroot.sh
sed -i "s|@NEW_USER@|$NEW_USER|g; s|@NEW_USER_SUDO@|$NEW_USER_SUDO|g" /mnt/root/post-chroot.sh
sed -i "s|@SSH_IMPORT_IDS@|$SSH_IMPORT_IDS|g" /mnt/root/post-chroot.sh
perl -0777 -pe 's/\@AUTH_KEYS\@/'"$(printf %s "$SSH_AUTHORIZED_KEYS" | sed 's/[\/&]/\\&/g')"'/g' -i /mnt/root/post-chroot.sh
sed -i "s|@AUTH_URLS@|$SSH_AUTHORIZED_KEYS_URLS|g; s|@PERMIT@|$PERMIT_ROOT_LOGIN|g; s|@PASSAUTH@|$PASSWORD_AUTH|g" /mnt/root/post-chroot.sh
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
