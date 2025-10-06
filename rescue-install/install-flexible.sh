#!/usr/bin/env bash
set -Eeuo pipefail

# Enhanced rescue installer supporting:
# 1. Optional fixed-size root partition with specified filesystem
# 2. Support for Debian (bookworm+) and Ubuntu (24.04+)
# 3. Flexible partitioning schemes for ZFS + traditional filesystems

# --- cfg (override via .env) ---
[ -f .env ] && set -a && . ./.env && set +a

# Basic configuration
DISK="${DISK:-/dev/sda}"
HOSTNAME="${HOSTNAME:-host1}"
TZ="${TZ:-UTC}"
FORCE="${FORCE:-1}"

# Distribution configuration
DISTRO="${DISTRO:-auto}"  # auto, debian, ubuntu
CODENAME="${CODENAME:-auto}"  # auto, bookworm, trixie, noble, etc.

# Partitioning mode
PARTITION_MODE="${PARTITION_MODE:-full-zfs}"  # full-zfs, fixed-root-zfs
ROOT_SIZE="${ROOT_SIZE:-20G}"  # Size for root partition in fixed-root-zfs mode
ROOT_FS="${ROOT_FS:-ext4}"     # Filesystem for root partition: ext4, xfs, btrfs
BOOT_FS="${BOOT_FS:-}"         # Boot filesystem: auto (zfs for full-zfs, ext4 for fixed-root-zfs), zfs, ext4

# ZFS configuration
POOL_R="${POOL_R:-rpool}"
POOL_B="${POOL_B:-bpool}"
ARC_MAX_MB="${ARC_MAX_MB:-2048}"
ENCRYPT="${ENCRYPT:-no}"

# User configuration
NEW_USER="${NEW_USER:-}"
NEW_USER_SUDO="${NEW_USER_SUDO:-1}"
SSH_IMPORT_IDS="${SSH_IMPORT_IDS:-}"
SSH_AUTHORIZED_KEYS="${SSH_AUTHORIZED_KEYS:-}"
SSH_AUTHORIZED_KEYS_URLS="${SSH_AUTHORIZED_KEYS_URLS:-}"
PERMIT_ROOT_LOGIN="${PERMIT_ROOT_LOGIN:-prohibit-password}"
PASSWORD_AUTH="${PASSWORD_AUTH:-no}"

# --- utils ---
b() { printf '\033[1m%s\033[0m\n' "$*"; }
ok(){ printf '\033[1;32m[OK]\033[0m %s\n' "$*"; }
die(){ printf '\033[1;31m[FAIL]\033[0m %s\n' "$*"; exit 1; }
ask(){ [ "$FORCE" = 1 ] && return 0; read -r -p "$1 [y/N]: " a; [[ $a =~ ^[Yy]$ ]]; }

trap 'die "line $LINENO"' ERR
[ "$(id -u)" -eq 0 ] || die "run as root"
[ -b "$DISK" ] || die "disk $DISK missing"

# --- distribution detection ---
detect_distro() {
    if [ "$DISTRO" = "auto" ]; then
        if [ -f /etc/os-release ]; then
            source /etc/os-release
            case "$ID" in
                debian)
                    DISTRO="debian"
                    [ "$CODENAME" = "auto" ] && CODENAME="${VERSION_CODENAME:-bookworm}"
                    ;;
                ubuntu)
                    DISTRO="ubuntu"
                    [ "$CODENAME" = "auto" ] && CODENAME="${VERSION_CODENAME:-noble}"
                    ;;
                *)
                    die "Unsupported distribution: $ID"
                    ;;
            esac
        else
            die "Cannot detect distribution"
        fi
    fi
    
    # Validate combinations
    case "$DISTRO" in
        debian)
            case "$CODENAME" in
                bookworm|trixie) ;;
                *) die "Unsupported Debian codename: $CODENAME (supported: bookworm, trixie)" ;;
            esac
            ;;
        ubuntu)
            case "$CODENAME" in
                noble|oracular) ;;
                *) die "Unsupported Ubuntu codename: $CODENAME (supported: noble, oracular)" ;;
            esac
            ;;
        *)
            die "Unsupported distribution: $DISTRO (supported: debian, ubuntu)"
            ;;
    esac
}

# --- boot filesystem configuration ---
configure_boot_fs() {
    if [ "$BOOT_FS" = "" ]; then
        case "$PARTITION_MODE" in
            full-zfs)
                BOOT_FS="zfs"
                ;;
            fixed-root-zfs)
                BOOT_FS="ext4"
                ;;
            *)
                die "Unknown partition mode: $PARTITION_MODE"
                ;;
        esac
    fi
    
    # Validate boot filesystem choice
    case "$BOOT_FS" in
        zfs|ext4) ;;
        *) die "Unsupported boot filesystem: $BOOT_FS (supported: zfs, ext4)" ;;
    esac
}

# --- partitioning functions ---
create_partitions_full_zfs() {
    b "Creating full ZFS partitioning on $DISK"
    sgdisk -Z "$DISK"
    if [ "$BOOTMODE" = uefi ]; then
        sgdisk -n1:1M:+1G -t1:EF00 "$DISK"   # EFI System Partition
        sgdisk -n2:0:+2G -t2:BF01 "$DISK"    # Boot pool
        sgdisk -n3:0:0 -t3:BF01 "$DISK"      # Root pool
        mkfs.vfat -F32 -n EFI "${DISK}1"
    else
        sgdisk -n1:1M:+1M -t1:EF02 "$DISK"   # BIOS boot partition
        sgdisk -n2:0:+2G -t2:BF01 "$DISK"    # Boot pool
        sgdisk -n3:0:0 -t3:BF01 "$DISK"      # Root pool
    fi
}

create_partitions_fixed_root() {
    b "Creating fixed root + ZFS partitioning on $DISK (boot: $BOOT_FS)"
    sgdisk -Z "$DISK"
    if [ "$BOOTMODE" = uefi ]; then
        sgdisk -n1:1M:+1G -t1:EF00 "$DISK"      # EFI System Partition
        if [ "$BOOT_FS" = "zfs" ]; then
            sgdisk -n2:0:+2G -t2:BF01 "$DISK"       # Boot pool (ZFS)
        else
            sgdisk -n2:0:+2G -t2:8300 "$DISK"       # Boot partition (ext4)
        fi
        sgdisk -n3:0:+${ROOT_SIZE} -t3:8300 "$DISK"  # Root partition (traditional)
        sgdisk -n4:0:0 -t4:BF01 "$DISK"         # Remaining space for ZFS
        mkfs.vfat -F32 -n EFI "${DISK}1"
    else
        sgdisk -n1:1M:+1M -t1:EF02 "$DISK"      # BIOS boot partition
        if [ "$BOOT_FS" = "zfs" ]; then
            sgdisk -n2:0:+2G -t2:BF01 "$DISK"       # Boot pool (ZFS)
        else
            sgdisk -n2:0:+2G -t2:8300 "$DISK"       # Boot partition (ext4)
        fi
        sgdisk -n3:0:+${ROOT_SIZE} -t3:8300 "$DISK"  # Root partition (traditional)
        sgdisk -n4:0:0 -t4:BF01 "$DISK"         # Remaining space for ZFS
    fi
    
    # Create filesystem on boot partition (if ext4)
    if [ "$BOOT_FS" = "ext4" ]; then
        mkfs.ext4 -L boot "${DISK}2"
    fi
    
    # Create filesystem on root partition
    case "$ROOT_FS" in
        ext4)
            mkfs.ext4 -L root "${DISK}3"
            ;;
        xfs)
            mkfs.xfs -L root "${DISK}3"
            ;;
        btrfs)
            mkfs.btrfs -L root "${DISK}3"
            ;;
        *)
            die "Unsupported root filesystem: $ROOT_FS"
            ;;
    esac
}

# --- ZFS pool creation ---
create_zfs_pools_full() {
    b "Creating ZFS pools (full ZFS mode)"
    [ "$ENCRYPT" = yes ] && ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase) || ENC=()
    
    # Boot pool
    zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
        -o compatibility=grub2 -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
        -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"
    
    # Root pool
    zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
        -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
        -O mountpoint=none -O canmount=off "${ENC[@]}" "$POOL_R" "${DISK}3"
}

create_zfs_pools_fixed_root() {
    b "Creating ZFS pools (fixed root mode, boot: $BOOT_FS)"
    [ "$ENCRYPT" = yes ] && ENC=(-O encryption=aes-256-gcm -O keyformat=passphrase) || ENC=()
    
    # Boot pool (only if using ZFS for boot)
    if [ "$BOOT_FS" = "zfs" ]; then
        zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
            -o compatibility=grub2 -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
            -O mountpoint=none -O canmount=off "$POOL_B" "${DISK}2"
    fi
    
    # Data pool (on remaining space)
    zpool create -f -o ashift=12 -o autotrim=on -o cachefile=/etc/zfs/zpool.cache \
        -O atime=off -O xattr=sa -O acltype=posixacl -O compression=lz4 \
        -O mountpoint=none -O canmount=off "${ENC[@]}" "$POOL_R" "${DISK}4"
}

# --- dataset creation ---
create_datasets_full_zfs() {
    ensure_ds(){ zfs list -H -o name "$1" >/dev/null 2>&1 || zfs create "${@:2}" "$1"; }
    ensure_mount(){ local ds="$1" mp="$2"; zfs set mountpoint="$mp" "$ds"; [ "$(zfs get -H -o value mounted "$ds")" = yes ] || zfs mount "$ds"; }

    b "Creating ZFS datasets (full ZFS mode)"
    ensure_ds "$POOL_R/ROOT" -o canmount=off -o mountpoint=none
    ensure_ds "$POOL_R/ROOT/$DISTRO"
    ensure_ds "$POOL_B/BOOT" -o canmount=off -o mountpoint=none
    ensure_ds "$POOL_B/BOOT/$DISTRO"

    ensure_mount "$POOL_R/ROOT/$DISTRO" /mnt
    mkdir -p /mnt/boot
    ensure_mount "$POOL_B/BOOT/$DISTRO" /mnt/boot

    # Additional datasets
    ensure_ds "$POOL_R/var"               -o mountpoint=/mnt/var
    ensure_ds "$POOL_R/var/lib"           -o mountpoint=/mnt/var/lib
    ensure_ds "$POOL_R/var/lib/mysql"     -o recordsize=16K -o logbias=latency -o primarycache=all -o mountpoint=/mnt/var/lib/mysql
    ensure_ds "$POOL_R/var/vmail"         -o recordsize=16K -o mountpoint=/mnt/var/vmail
    ensure_ds "$POOL_R/home"              -o mountpoint=/mnt/home
    ensure_ds "$POOL_R/srv"               -o mountpoint=/mnt/srv
}

create_datasets_fixed_root() {
    ensure_ds(){ zfs list -H -o name "$1" >/dev/null 2>&1 || zfs create "${@:2}" "$1"; }
    ensure_mount(){ local ds="$1" mp="$2"; zfs set mountpoint="$mp" "$ds"; [ "$(zfs get -H -o value mounted "$ds")" = yes ] || zfs mount "$ds"; }

    b "Setting up filesystems (fixed root mode, boot: $BOOT_FS)"
    
    # Mount root partition
    mkdir -p /mnt
    mount "${DISK}3" /mnt
    
    # Handle boot filesystem based on type
    mkdir -p /mnt/boot
    if [ "$BOOT_FS" = "zfs" ]; then
        # Create and mount ZFS boot pool
        ensure_ds "$POOL_B/BOOT" -o canmount=off -o mountpoint=none
        ensure_ds "$POOL_B/BOOT/$DISTRO"
        ensure_mount "$POOL_B/BOOT/$DISTRO" /mnt/boot
    else
        # Mount ext4 boot partition
        mount "${DISK}2" /mnt/boot
    fi

    # Create ZFS datasets for data (mounted under /mnt for now)
    ensure_ds "$POOL_R/var"               -o mountpoint=/mnt/var
    ensure_ds "$POOL_R/var/lib"           -o mountpoint=/mnt/var/lib
    ensure_ds "$POOL_R/var/lib/mysql"     -o recordsize=16K -o logbias=latency -o primarycache=all -o mountpoint=/mnt/var/lib/mysql
    ensure_ds "$POOL_R/var/vmail"         -o recordsize=16K -o mountpoint=/mnt/var/vmail
    ensure_ds "$POOL_R/home"              -o mountpoint=/mnt/home
    ensure_ds "$POOL_R/srv"               -o mountpoint=/mnt/srv
}

# --- package sources ---
setup_package_sources() {
    b "Setting up package sources for $DISTRO $CODENAME"
    case "$DISTRO" in
        debian)
            cat >/etc/apt/sources.list <<EOF
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-backports main contrib non-free non-free-firmware
EOF
            ;;
        ubuntu)
            cat >/etc/apt/sources.list <<EOF
deb http://archive.ubuntu.com/ubuntu $CODENAME main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $CODENAME-security main restricted universe multiverse
EOF
            ;;
    esac
}

# --- main execution ---
main() {
    BOOTMODE=bios; [ -d /sys/firmware/efi ] && BOOTMODE=uefi
    
    detect_distro
    configure_boot_fs
    b "Detected: $DISTRO $CODENAME  •  Boot: $BOOTMODE  •  Mode: $PARTITION_MODE  •  Boot FS: $BOOT_FS"
    b "Will WIPE $DISK"
    ask "Proceed?" || die "aborted"

    # Install rescue dependencies
    setup_package_sources
    export DEBIAN_FRONTEND=noninteractive
    apt-get -y update
    dpkg-divert --local --rename --add /usr/sbin/update-initramfs >/dev/null 2>&1 || true
    printf '#!/bin/sh\nexit 0\n' >/usr/sbin/update-initramfs && chmod +x /usr/sbin/update-initramfs
    apt-get -y install dkms build-essential "linux-headers-$(uname -r)" zfs-dkms zfsutils-linux debootstrap gdisk dosfstools
    modprobe zfs || die "zfs modprobe failed"
    ok "Rescue prerequisites installed"

    # Partitioning and pool creation
    case "$PARTITION_MODE" in
        full-zfs)
            create_partitions_full_zfs
            create_zfs_pools_full
            create_datasets_full_zfs
            ;;
        fixed-root-zfs)
            create_partitions_fixed_root
            create_zfs_pools_fixed_root
            create_datasets_fixed_root
            ;;
        *)
            die "Unknown partition mode: $PARTITION_MODE"
            ;;
    esac
    ok "Partitioning and pools created"

    # System installation
    b "Installing base system"
    case "$DISTRO" in
        debian)
            debootstrap "$CODENAME" /mnt http://deb.debian.org/debian/
            ;;
        ubuntu)
            debootstrap "$CODENAME" /mnt http://archive.ubuntu.com/ubuntu/
            ;;
    esac
    [ -x /mnt/bin/sh ] || die "bootstrap incomplete"
    ok "Base system installed"

    # Generate post-chroot script
    generate_post_chroot_script
    ok "Post-chroot script prepared"

    # Execute post-chroot configuration
    b "Executing post-chroot configuration"
    for d in dev proc sys run; do mount --rbind "/$d" "/mnt/$d"; mount --make-rslave "/mnt/$d"; done
    mkdir -p /mnt/etc; [ -e /mnt/etc/resolv.conf ] || : >/mnt/etc/resolv.conf
    mount --bind /etc/resolv.conf /mnt/etc/resolv.conf
    chroot /mnt /bin/bash /root/post-chroot.sh
    ok "Post-chroot configuration completed"

    # Cleanup and finalize
    cleanup_and_finalize
    ok "Installation complete. Reboot when ready."
}

generate_post_chroot_script() {
    cat >/mnt/root/post-chroot.sh <<'EOS'
set -Eeuo pipefail
trap 'echo "[FAIL] line $LINENO"; exit 1' ERR

# Variables will be substituted by the main script
HN="@HOSTNAME@"; TZ="@TZ@"; DISK="@DISK@"; RP="@POOL_R@"; BP="@POOL_B@"
DISTRO="@DISTRO@"; CODENAME="@CODENAME@"; PARTITION_MODE="@PARTITION_MODE@"
ARC_BYTES=@ARC_BYTES@; ROOT_FS="@ROOT_FS@"; BOOT_FS="@BOOT_FS@"
NEW_USER='@NEW_USER@'; NEW_USER_SUDO='@NEW_USER_SUDO@'
SSH_IMPORT_IDS='@SSH_IMPORT_IDS@'; AUTH_KEYS='@AUTH_KEYS@'; AUTH_URLS='@AUTH_URLS@'
PERMIT='@PERMIT@'; PASSAUTH='@PASSAUTH@'

# Basic system setup
install -d -m0755 /var/cache/apt/archives/partial /var/lib/apt/lists/partial /var/lib/dpkg/updates /var/log/apt
[ -s /var/lib/dpkg/status ] || :> /var/lib/dpkg/status

echo "$HN" >/etc/hostname
ln -sf "/usr/share/zoneinfo/$TZ" /etc/localtime
printf "127.0.0.1 localhost\n127.0.1.1 $HN\n" >/etc/hosts

# Package sources
case "$DISTRO" in
    debian)
        cat >/etc/apt/sources.list <<SL
deb http://deb.debian.org/debian $CODENAME main contrib non-free non-free-firmware
deb http://security.debian.org/debian-security $CODENAME-security main contrib non-free non-free-firmware
deb http://deb.debian.org/debian $CODENAME-updates main contrib non-free non-free-firmware
SL
        ;;
    ubuntu)
        cat >/etc/apt/sources.list <<SL
deb http://archive.ubuntu.com/ubuntu $CODENAME main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-updates main restricted universe multiverse
deb http://archive.ubuntu.com/ubuntu $CODENAME-backports main restricted universe multiverse
deb http://security.ubuntu.com/ubuntu $CODENAME-security main restricted universe multiverse
SL
        ;;
esac

export DEBIAN_FRONTEND=noninteractive
apt-get -y update

# Install packages based on partition mode
if [ "$PARTITION_MODE" = "full-zfs" ]; then
    # Full ZFS installation
    apt-get -y install locales console-setup ca-certificates curl \
        linux-image-amd64 linux-headers-amd64 \
        zfs-dkms zfsutils-linux zfs-initramfs \
        openssh-server ssh-import-id sudo grub-common cloud-init
else
    # Fixed root + ZFS installation
    apt-get -y install locales console-setup ca-certificates curl \
        linux-image-amd64 linux-headers-amd64 \
        zfs-dkms zfsutils-linux \
        openssh-server ssh-import-id sudo grub-common cloud-init
fi

# Locales
grep -q "^en_US.UTF-8" /etc/locale.gen || echo "en_US.UTF-8 UTF-8" >>/etc/locale.gen
locale-gen >/dev/null 2>&1 || true
command -v update-locale >/dev/null 2>&1 && update-locale LANG=en_US.UTF-8 || true

# Filesystem setup based on partition mode
if [ "$PARTITION_MODE" = "full-zfs" ]; then
    # ZFS-specific setup
    zfs set readonly=off "$RP/ROOT/$DISTRO" || true
    zfs set readonly=off "$RP/var" || true
    
    command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
    zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
    zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
    zpool set bootfs="$RP/ROOT/$DISTRO" "$RP" || true
    
    # ZFS kernel module options
    echo "options zfs zfs_arc_max=$ARC_BYTES" >/etc/modprobe.d/zfs.conf
    
    # ZFS import configuration
    cat >/etc/default/zfs <<ZDF
ZPOOL_IMPORT_PATH="/dev/disk/by-id"
ZPOOL_IMPORT_OPTS="-N"
ZPOOL_IMPORT_TIMEOUT="30"
ZFS_INITRD_POST_MODPROBE_SLEEP="2"
ZDF
else
    # Traditional root filesystem setup
    mkdir -p /etc/default
    
    # Generate fstab for traditional root
    case "$ROOT_FS" in
        ext4|xfs|btrfs)
            echo "LABEL=root / $ROOT_FS defaults 0 1" >/etc/fstab
            ;;
    esac
    
    # Add boot partition to fstab if using ext4 boot
    if [ "$BOOT_FS" = "ext4" ]; then
        echo "LABEL=boot /boot ext4 defaults 0 2" >>/etc/fstab
    fi
    
    # ZFS setup for data pools only
    command -v zgenhostid >/dev/null 2>&1 && zgenhostid "$(hostid)" || true
    zpool set cachefile=/etc/zfs/zpool.cache "$RP" || true
    if [ "$BOOT_FS" = "zfs" ]; then
        zpool set cachefile=/etc/zfs/zpool.cache "$BP" || true
    fi
    
    echo "options zfs zfs_arc_max=$ARC_BYTES" >/etc/modprobe.d/zfs.conf
fi

mount -o remount,rw / || true
install -d -m1777 /var/tmp /tmp

# GRUB configuration
mkdir -p /etc/default
[ -f /etc/default/grub ] || cat >/etc/default/grub <<'G'
GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=Debian
GRUB_CMDLINE_LINUX=""
GRUB_CMDLINE_LINUX_DEFAULT="quiet"
G

if [ "$PARTITION_MODE" = "full-zfs" ]; then
    sed -ri "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=ZFS=$RP/ROOT/$DISTRO rootdelay=5\"|" /etc/default/grub
    grep -q '^GRUB_PRELOAD_MODULES' /etc/default/grub || echo 'GRUB_PRELOAD_MODULES="zfs"' >> /etc/default/grub
else
    sed -ri "s|^GRUB_CMDLINE_LINUX=.*|GRUB_CMDLINE_LINUX=\"root=LABEL=root rootdelay=5\"|" /etc/default/grub
fi

# Install and configure GRUB
if [ "$BOOT_FS" = "zfs" ]; then
    mountpoint -q /boot || zfs mount "$BP/BOOT/$DISTRO" || true
fi
if [ "$PARTITION_MODE" = "full-zfs" ]; then
    TMPDIR=/tmp update-initramfs -u
fi

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

# SSH and user configuration
install -d /etc/ssh/sshd_config.d
umask 077
cat >/etc/ssh/sshd_config.d/99-bootstrap.conf <<EOF
PermitRootLogin ${PERMIT}
PasswordAuthentication ${PASSAUTH}
EOF

install -d -m700 /root/.ssh; : >/root/.ssh/authorized_keys; chmod 600 /root/.ssh/authorized_keys
[ -n "$SSH_IMPORT_IDS" ] && ssh-import-id $SSH_IMPORT_IDS || true
[ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>/root/.ssh/authorized_keys
if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>/root/.ssh/authorized_keys || true; done; fi

if [ -n "$NEW_USER" ]; then
    id "$NEW_USER" >/dev/null 2>&1 || adduser --disabled-password --gecos "" "$NEW_USER"
    [ "$NEW_USER_SUDO" = "1" ] && usermod -aG sudo "$NEW_USER"
    install -d -m700 "/home/$NEW_USER/.ssh"
    : >"/home/$NEW_USER/.ssh/authorized_keys"; chmod 600 "/home/$NEW_USER/.ssh/authorized_keys"
    chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER/.ssh"
    [ -n "$SSH_IMPORT_IDS" ] && sudo -u "$NEW_USER" ssh-import-id $SSH_IMPORT_IDS || true
    [ -n "$AUTH_KEYS" ] && printf '%s\n' $AUTH_KEYS >>"/home/$NEW_USER/.ssh/authorized_keys"
    if [ -n "$AUTH_URLS" ]; then for u in $AUTH_URLS; do curl -fsSL "$u" >>"/home/$NEW_USER/.ssh/authorized_keys" || true; done; fi
fi

# Cloud-init configuration
mkdir -p /etc/cloud/cloud.cfg.d
echo 'datasource_list: [ConfigDrive, NoCloud, Ec2]' >/etc/cloud/cloud.cfg.d/90-datasources.cfg

# Enable services
systemctl enable ssh >/dev/null 2>&1 || true
systemctl enable cloud-init cloud-config cloud-final cloud-init-local >/dev/null 2>&1 || true
if [ "$PARTITION_MODE" = "full-zfs" ]; then
    systemctl enable zfs-import-cache zfs-import.target zfs-mount >/dev/null 2>&1 || true
else
    systemctl enable zfs-import-cache >/dev/null 2>&1 || true
fi

# Final checks
sshd -t
test -s /boot/grub/grub.cfg
ls -1 /boot/vmlinuz-* /boot/initrd.img-* >/dev/null

if [ "$PARTITION_MODE" = "full-zfs" ]; then
    zpool get -H -o value bootfs "$RP" | grep -q "$RP/ROOT/$DISTRO"
fi

echo "[OK] post-chroot configuration completed"
EOS

    # Substitute variables in the post-chroot script
    sed -i "s|@HOSTNAME@|$HOSTNAME|g; s|@TZ@|$TZ|g; s|@DISK@|$DISK|g" /mnt/root/post-chroot.sh
    sed -i "s|@POOL_R@|$POOL_R|g; s|@POOL_B@|$POOL_B|g" /mnt/root/post-chroot.sh
    sed -i "s|@DISTRO@|$DISTRO|g; s|@CODENAME@|$CODENAME|g" /mnt/root/post-chroot.sh
    sed -i "s|@PARTITION_MODE@|$PARTITION_MODE|g; s|@ROOT_FS@|$ROOT_FS|g; s|@BOOT_FS@|$BOOT_FS|g" /mnt/root/post-chroot.sh
    sed -i "s|@ARC_BYTES@|$((ARC_MAX_MB*1024*1024))|g" /mnt/root/post-chroot.sh
    sed -i "s|@NEW_USER@|$NEW_USER|g; s|@NEW_USER_SUDO@|$NEW_USER_SUDO|g" /mnt/root/post-chroot.sh
    sed -i "s|@SSH_IMPORT_IDS@|$SSH_IMPORT_IDS|g" /mnt/root/post-chroot.sh
    perl -0777 -pe 's/\@AUTH_KEYS\@/'"$(printf %s "$SSH_AUTHORIZED_KEYS" | sed 's/[\/&]/\\&/g')"'/g' -i /mnt/root/post-chroot.sh
    sed -i "s|@AUTH_URLS@|$SSH_AUTHORIZED_KEYS_URLS|g" /mnt/root/post-chroot.sh
    sed -i "s|@PERMIT@|$PERMIT_ROOT_LOGIN|g; s|@PASSAUTH@|$PASSWORD_AUTH|g" /mnt/root/post-chroot.sh
}

cleanup_and_finalize() {
    b "Cleanup and finalization"
    
    # Unmount bind mounts
    umount -l /mnt/etc/resolv.conf 2>/dev/null || true
    for m in /mnt/dev/pts /mnt/dev /mnt/proc /mnt/sys /mnt/run; do umount -l "$m" 2>/dev/null || true; done

    if [ "$PARTITION_MODE" = "full-zfs" ]; then
        # Full ZFS cleanup
        zfs list -H -o name -r "$POOL_R" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
        zfs list -H -o name -r "$POOL_B" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true

        # Set runtime mountpoints
        for spec in \
            "$POOL_R/ROOT/$DISTRO=/" \
            "$POOL_B/BOOT/$DISTRO=/boot" \
            "$POOL_R/var=/var" \
            "$POOL_R/var/lib=/var/lib" \
            "$POOL_R/var/lib/mysql=/var/lib/mysql" \
            "$POOL_R/var/vmail=/var/vmail" \
            "$POOL_R/home=/home" \
            "$POOL_R/srv=/srv"; do
            ds=${spec%%=*}; mp=${spec#*=}
            zfs set mountpoint="$mp" "$ds"
        done
    else
        # Fixed root cleanup
        umount /mnt 2>/dev/null || true
        zfs list -H -o name -r "$POOL_B" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true
        zfs list -H -o name -r "$POOL_R" | sort -r | xargs -r -n1 zfs unmount -f 2>/dev/null || true

        # Set runtime mountpoints for ZFS datasets
        for spec in \
            "$POOL_B/BOOT/$DISTRO=/boot" \
            "$POOL_R/var=/var" \
            "$POOL_R/var/lib=/var/lib" \
            "$POOL_R/var/lib/mysql=/var/lib/mysql" \
            "$POOL_R/var/vmail=/var/vmail" \
            "$POOL_R/home=/home" \
            "$POOL_R/srv=/srv"; do
            ds=${spec%%=*}; mp=${spec#*=}
            zfs set mountpoint="$mp" "$ds"
        done
    fi

    # Export pools
    zpool export -f "$POOL_B" 2>/dev/null || true
    zpool export -f "$POOL_R" 2>/dev/null || true
}

# Execute main function
main "$@"