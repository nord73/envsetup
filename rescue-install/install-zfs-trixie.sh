#!/usr/bin/env bash
# Debian 13 (trixie) ZFS-on-root — Contabo rescue -> bootable VM
# - BIOS/UEFI auto
# - Safe ZFS import on first boot (no -f), hostid baked
# - SSH enabled + keys via ssh-import-id / env
# - Cloud-init installed but not network-opinionated
# - Idempotent; re-runs OK

set -Eeuo pipefail
[ -f .env ] && set -a && . ./.env && set +a

# ---- cfg (overridable via .env) ---------------------------------------------
DISK="${DISK:-/dev/sda}"
HOSTNAME="${HOSTNAME:-mail1}"
TZ="${TZ:-UTC}"
POOL_R="${POOL_R:-rpool}"
POOL_B="${POOL_B:-bpool}"
ARC_MAX_MB="${ARC_MAX_MB:-2048}"   # ZFS ARC cap
ENCRYPT="${ENCRYPT:-no}"           # yes|no
FORCE="${FORCE:-0}"

# SSH bootstrap
NEW_USER="${NEW_USER:-}"           # e.g., ansible
NEW_USER_SUDO="${NEW_USER_SUDO:-1}"
SSH_IMPORT_IDS="${SSH_IMPORT_IDS:-}"             # e.g., "gh:user1 gh:user2"
SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"   # space/newline sep pubkeys
SSH_AUTHORIZED_KEYS_URLS="${SSH_AUTHORIZED_KEYS_URLS:-}" # URLs with pubkeys
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-prohibit-password}"  # yes|no|prohibit-password
PASSWORD_AUTH="${PASSWORD_AUTH:-no}"                            # yes|no
# ---------------------------------------------------------------------------

BOLD=$'\033[1m'; CLR=$'\033[0m'
log(){ echo "${BOLD}[INFO]${CLR} $*"; }
ok(){  echo "${BOLD}[OK ]${CLR}  $*"; }
warn(){echo "${BOLD}[WARN]${CLR} $*"; }
die(){ echo "${BOLD}[FAIL]${CLR} $*"; exit 1; }
ask(){ [ "$FORCE" = "1" ] && return 0; read -r -p "$1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]; }

[ "$(id -u)" -eq 0 ] || die "run as root"
[ -b "$DISK" ] || die "disk $DISK not found"

BOOTMODE=bios; [ -d /sys/firmware/efi ] && BOOTMODE=uefi
log "Rescue mode: $BOOTMODE"
log "This will WIPE $DISK and install Debian 13 on ZFS-root."
ask "Proceed on $DISK?" || die "aborted"

# --- rescue apt + dkms + zfs + debootstrap (avoid live initramfs writes) ----
source /etc/os-release; CODENAME=${VERSION_CODENAME:-bookworm}
cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-backports main contrib non-free non-free-firmware
EOF
export DEBIAN_FRONTEND=noninteractive
apt-get update -y

# divert update-initramfs in rescue (live medium has no space)
if ! dpkg-divert --list | grep -q '/usr/sbin/update-initramfs$'; then
  dpkg-divert --local --rename --add /usr/sbin/update-initramfs || true
  printf '#!/bin/sh\nexit 0\n' >/usr/sbin/update-initramfs; chmod +x /usr/sbin/update-initramfs
fi

apt-get install -y dkms build-essential "linux-headers-$(uname -r)" zfs-dkms zfsutils-linux \
                      debootstrap gdisk dosfstools || die "rescue pkgs failed"
modprobe zfs || die "zfs modprobe failed"
ok "Rescue prerequisites ready"

# --- blow partition table + layout ------------------------------------------
log "Partitioning $DISK…"
sgdisk -Z "$DISK"
if [ "$BOOTMODE" = uefi ]; then
  sgdisk -n1:1M:+1G -t1:EF00 "$DISK"     # ESP
  sgdisk -n2:0:+2G  -t2:BF01 "$DISK"     # bpool
  sgdisk -n3:0:0    -t3:BF01 "$DISK"     # rpool
  mkfs.vfat -F32 -n EFI "${DISK}1"
else
  sgdisk -n1:1M:+1M -t1:EF02 "$DISK"     # BIOS-boot
  sgdisk -n2:0:+2G  -t2:BF01 "$DISK"
  sgdisk -n3:0:0    -t3:BF01 "$DISK"
fi
ok "Disk partitioned"

# --- create pools ------------------------------------------------------------
log "Creating pools…"
[ "$ENCRYPT" = "yes" ] && ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase) || ENC=()
# bpool: GRUB-compatible
zpool create -f \
  -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -o compatibility=grub2 \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"

# rpool: ROOT
zpool create -f \
  -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
  -O compression=lz4 -O atime=off -O xattr=sa -O acltype=posixacl \
  -O mountpoint=none -O canmount=off "${ENC[@]}" "$POOL_R" "${DISK}3"
ok "Pools created"

# --- datasets + temporary mounts (idempotent) --------------------------------
ensure_ds(){ zfs list -H -o name "$1" >/dev/null 2>&1 || zfs create "${@:2}" "$1"; }
ensure_mount(){ local ds="$1" mp="$2"; zfs set mountpoint="$mp" "$ds"; [ "$(zfs get -H -o value mounted "$ds")" = yes ] || zfs mount "$ds"; }

log "Datasets…"
ensure_ds "$POOL_R/ROOT" -o canmount=off -o mountpoint=none
ensure_ds "$POOL_R/ROOT/debian"
ensure_ds "$POOL_B/BOOT" -o canmount=off -o mountpoint=none
ensure_ds "$POOL_B/BOOT/debian"

# temp mountpoints for install
ensure_mount "$POOL_R/ROOT/debian" /mnt
mkdir -p /mnt/boot
ensure_mount "$POOL_B/BOOT/debian" /mnt/boot

# app data (pre-create for mailcow move)
ensure_ds "$POOL_R/var"               -o mountpoint=/mnt/var
ensure_ds "$POOL_R/var/lib"           -o mountpoint=/mnt/var/lib
ensure_ds "$POOL_R/var/lib/mysql"     -o recordsize=16K -o logbias=latency -o primarycache=all -o mountpoint=/mnt/var/lib/mysql
ensure_ds "$POOL_R/var/vmail"         -o recordsize=16K -o mountpoint=/mnt/var/vmail
ensure_ds "$POOL_R/home"              -o mountpoint=/mnt/home
ensure_ds "$POOL_R/srv"               -o mountpoint=/mnt/srv
ok "Datasets mounted"

# --- bootstrap trixie --------------------------------------------------------
log "debootstrap trixie…"
debootstrap trixie /mnt http://deb.debian.org/debian/ || die "debootstrap failed"
[ -x /mnt/bin/sh ] || die "bootstrap incomplete"
ok "Base system ready"

# --- write post-chroot script ------------------------------------------------
log "Preparing post-chroot…"
cat > /mnt/root/post-chroot.sh <<'EOS'
set -Eeuo pipefail
trap 'echo "[FAIL] line $LINENO"; exit 1' ERR
HN="@HOSTNAME@"; TZ="@TZ@"; DISK="@DISK@"; RP="@POOL_R@"; BP="@POOL_B@"
ARC_BYTES=@ARC_BYTES@
NEW_USER='@NEW_USER@'; NEW_USER_SUDO='@NEW_USER_SUDO@'
SSH_IMPORT_IDS='@SSH_IMPORT_IDS@'
AUTH_KEYS='@AUTH_KEYS@'
AUTH_URLS='@AUTH_URLS@'
PERMIT='@PERMIT@'; PASSAUTH='@PASSAUTH@'

# dpkg/apt/log dirs (debootstrap sometimes lacks these)
install -d -m0755 /var/cache/apt/archives/partial /var/lib/apt/lists/partial /var/lib/dpkg/updates /var/log/apt
[ -s /var/lib/dpkg/status ] || :> /var/lib/dpkg/status

# basic identity
echo "$HN" >/etc/hostname
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf "127.0.0.1 localhost\n127.0.1.1 $HN\n" >/etc/hosts

# APT
cat >/etc/apt/sources.list <<SL
deb http://deb.debian.org/debian trixie main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security trixie-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian trixie-updates main contrib non-free non-free-firmware
SL
export DEBIAN_FRONTEND=noninteractive
apt-get -y update

# core packages (incl. locales *before* update-locale)
apt-get -y install locales console-setup ca-certificates curl \
  linux-image-amd64 linux-headers-amd64 \
  zfs-dkms zfsutils-linux zfs-initramfs \
  openssh-server ssh-import-id sudo \
  grub-common cloud-init

# locales
grep -q "^en_US.UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen >/dev/null 2>&1 || true
command -v update-locale >/dev/null 2>&1 && update-locale LANG=en_US.UTF-8 || true

# ensure RW + tmp
zfs set readonly=off "$RP/ROOT/debian" || true
zfs set readonly=off "$RP/var" || true
mount -o remount,rw / || true
install -d -m1777 /var/tmp /tmp

# hostid + zpool cache + bootfs (fix "previously in use")
command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
zpool set bootfs="$RP/ROOT/debian" "$RP" || true

# initramfs ZFS import: safe (no -f, no readonly); narrow scan path; short sleep
cat >/etc/default/zfs <<ZDF
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
ZPOOL_IMPORT_OPTS="-N"
ZPOOL_IMPORT_TIMEOUT="30"
ZFS_INITRD_POST_MODPROBE_SLEEP="2"
ZDF

# ARC cap
echo "options zfs zfs_arc_max=$ARC_BYTES" >/etc/modprobe.d/zfs.conf

# /etc/default/grub (ensure exists), set zfs root + small delay; preload zfs
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

# build initrd with /boot mounted
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

# set runtime mountpoints (ok if remount fails now; properties persist)
zfs set mountpoint=/      "$RP/ROOT/debian" || true
zfs set mountpoint=/boot  "$BP/BOOT/debian" || true
zfs set mountpoint=/var            "$RP/var" || true
zfs set mountpoint=/var/lib        "$RP/var/lib" || true
zfs set mountpoint=/var/lib/mysql  "$RP/var/lib/mysql" || true
zfs set mountpoint=/var/vmail      "$RP/var/vmail" || true
zfs set mountpoint=/home           "$RP/home" || true
zfs set mountpoint=/srv            "$RP/srv" || true

# SSH config via drop-in (no risky in-place sed)
install -d /etc/ssh/sshd_config.d
cat >/etc/ssh/sshd_config.d/99-bootstrap.conf <<EOF
PermitRootLogin ${PERMIT}
PasswordAuthentication ${PASSAUTH}
EOF
install -d -m700 /root/.ssh; touch /root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
[ -n "$SSH_IMPORT_IDS" ] && ssh-import-id $SSH_IMPORT_IDS || true
[ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>/root/.ssh/authorized_keys
if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>/root/.ssh/authorized_keys || true; done; fi

# optional user + keys
if [ -n "$NEW_USER" ]; then
  id "$NEW_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$NEW_USER"
  [ "$NEW_USER_SUDO" = "1" ] && usermod -aG sudo "$NEW_USER"
  install -d -m700 "/home/$NEW_USER/.ssh"
  touch "/home/$NEW_USER/.ssh/authorized_keys"; chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
  chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
  [ -n "$SSH_IMPORT_IDS" ] && sudo -u "$NEW_USER" ssh-import-id $SSH_IMPORT_IDS || true
  [ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>"/home/$NEW_USER/.ssh/authorized_keys"
  if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>"/home/$NEW_USER/.ssh/authorized_keys" || true; done; fi
fi

# cloud-init (datasource list only; leaves SSH we set)
mkdir -p /etc/cloud/cloud.cfg.d
echo 'datasource_list: [ConfigDrive, NoCloud, Ec2]' >/etc/cloud/cloud.cfg.d/90-datasources.cfg

# enable services (systemctl will print "ignoring" in chroot; symlinks still created)
systemctl enable ssh zfs-import-cache zfs-import.target zfs-mount >/dev/null 2>&1 || true
systemctl enable cloud-init cloud-config cloud-final cloud-init-local >/dev/null 2>&1 || true

# sanity
sshd -t
test -s /boot/grub/grub.cfg
ls -1 /boot/vmlinuz-* /boot/initrd.img-* >/dev/null
zpool get -H -o value bootfs "$RP" | grep -q "$RP/ROOT/debian"
echo "[OK] post-chroot done"
EOS

# inject vars
sed -i "s|@HOSTNAME@|$HOSTNAME|g; s|@TZ@|$TZ|g; s|@DISK@|$DISK|g; s|@POOL_R@|$POOL_R|g; s|@POOL_B@|$POOL_B|g" /mnt/root/post-chroot.sh
sed -i "s|@ARC_BYTES@|$((ARC_MAX_MB*1024*1024))|g" /mnt/root/post-chroot.sh
sed -i "s|@NEW_USER@|$NEW_USER|g; s|@NEW_USER_SUDO@|$NEW_USER_SUDO|g" /mnt/root/post-chroot.sh
sed -i "s|@SSH_IMPORT_IDS@|$SSH_IMPORT_IDS|g" /mnt/root/post-chroot.sh
perl -0777 -pe 's/\@AUTH_KEYS\@/'"$(printf %s "$SSH_AUTHORIZED_KEYS" | sed 's/[\/&]/\\&/g')"'/g' -i /mnt/root/post-chroot.sh
sed -i "s|@AUTH_URLS@|$SSH_AUTHORIZED_KEYS_URLS|g; s|@PERMIT@|$PERMIT_ROOT_LOGIN|g; s|@PASSAUTH@|$PASSWORD_AUTH|g" /mnt/root/post-chroot.sh
ok "post-chroot prepared"

# --- chroot finalize ---------------------------------------------------------
log "Finalize in chroot…"
for d in dev proc sys run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
mkdir -p /mnt/etc; [ -e /mnt/etc/resolv.conf ] || :> /mnt/etc/resolv.conf
mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
chroot /mnt /bin/bash /root/post-chroot.sh

# verify critical bits
chroot /mnt test -s /boot/grub/grub.cfg || die "GRUB cfg missing"
chroot /mnt command -v sshd >/dev/null || die "openssh-server missing"
ok "Chroot finalize OK"

# --- teardown/export (best-effort) -------------------------------------------
log "Teardown…"
umount -l /mnt/etc/resolv.conf 2>/dev/null || true
for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done
zfs list -H -o name -r "$POOL_R" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
zfs list -H -o name -r "$POOL_B" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
findmnt -R /mnt -o TARGET | tac | xargs -r -n1 umount -lf 2>/dev/null || true

# try to export; if busy it's OK (import is hostid-matched and no -f)
zpool export -f "$POOL_B" 2>/dev/null || true
zpool export -f "$POOL_R" 2>/dev/null || true

ok "Install complete. Reboot to disk."
echo "TIP: If initramfs prompts, run:  zpool import -N -R /root -d /dev/disk/by-id rpool && zfs mount -a && exit"
