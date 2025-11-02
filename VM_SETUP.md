# Linux Virtual Machine Setup Guide

This guide provides comprehensive instructions for setting up Linux development VMs using envsetup, with support for various scenarios and desktop environments.

## Table of Contents

- [Overview](#overview)
- [Setup Scenarios](#setup-scenarios)
- [Desktop Environment Options](#desktop-environment-options)
- [Remote Access Setup](#remote-access-setup)
- [VM Optimization](#vm-optimization)
- [Network Configuration](#network-configuration)
- [Best Practices](#best-practices)
- [Troubleshooting](#troubleshooting)

---

## Overview

The `vm/setup-dev-vm.sh` script helps you quickly set up a Linux development VM with:

- **Multiple scenarios**: Headless server, minimal desktop, full desktop, developer workstation
- **Desktop environment choices**: GNOME (minimal), XFCE, KDE, or none (headless)
- **Remote access**: xRDP for graphical access, SSH for command line
- **Development tools**: Git, build tools, optional Docker, VS Code, etc.
- **Automatic integration**: Uses envsetup bootstrap.sh for consistency

---

## Setup Scenarios

The VM setup script supports multiple scenarios for different use cases:

### Scenario 1: Headless Server (Minimal)

**Use case:** Lightweight server, CLI-only development, Docker host

**Installation:**
```bash
cd ~/src/envsetup
bash vm/setup-dev-vm.sh --scenario=headless
```

**Includes:**
- Base tools (tmux, git, curl, wget, jq)
- SSH server (OpenSSH)
- Optional: Docker, development tools
- No GUI or desktop environment

**Resource Requirements:**
- RAM: 2GB minimum
- CPU: 1-2 cores
- Disk: 20GB minimum

**Access Methods:**
- SSH only
- Console access via VM platform

### Scenario 2: Minimal Desktop

**Use case:** Lightweight graphical environment, remote desktop access

**Installation:**
```bash
cd ~/src/envsetup
bash vm/setup-dev-vm.sh --scenario=minimal-desktop --desktop=xfce
```

**Includes:**
- Base system tools
- Lightweight desktop (XFCE by default)
- xRDP for remote access
- Basic applications (terminal, file manager, text editor)
- SSH server

**Resource Requirements:**
- RAM: 3-4GB minimum
- CPU: 2 cores
- Disk: 25GB minimum

### Scenario 3: Developer Desktop

**Use case:** Full-featured development environment with GUI

**Installation:**
```bash
cd ~/src/envsetup
bash vm/setup-dev-vm.sh --scenario=developer-desktop --desktop=xfce
```

**Includes:**
- All base and development tools
- Desktop environment (XFCE, GNOME, or KDE)
- VS Code
- Docker CE
- Development fonts
- Browser (not installed by default; install separately as needed)
- xRDP for remote access

**Resource Requirements:**
- RAM: 8GB recommended
- CPU: 4 cores recommended
- Disk: 50GB recommended

### Scenario 4: Remote Development Server

**Use case:** Headless server for remote development (VS Code Remote, SSH)

**Installation:**
```bash
cd ~/src/envsetup
bash vm/setup-dev-vm.sh --scenario=remote-dev
```

**Includes:**
- All development tools
- Docker
- No desktop environment
- SSH server
- Optimized for VS Code Remote Development

**Resource Requirements:**
- RAM: 4-8GB
- CPU: 2-4 cores
- Disk: 30GB minimum

---

## Desktop Environment Options

Choose the desktop environment that best fits your needs:

### XFCE (Default, Recommended)

**Advantages:**
- ✓ Lightweight and fast
- ✓ Low resource usage
- ✓ Stable and mature
- ✓ Familiar layout
- ✓ Customizable

**Installation:**
```bash
bash vm/setup-dev-vm.sh --scenario=minimal-desktop --desktop=xfce
```

**Resources:**
- RAM: ~500MB idle
- Best for: General use, older hardware, performance

### GNOME Minimal

**Advantages:**
- ✓ Modern interface
- ✓ Good integration with Ubuntu
- ✓ Touch-friendly
- ⚠ Higher resource usage

**Installation:**
```bash
bash vm/setup-dev-vm.sh --scenario=minimal-desktop --desktop=gnome
```

**Resources:**
- RAM: ~1GB idle
- Best for: Modern look, Ubuntu consistency

### KDE Plasma

**Advantages:**
- ✓ Highly customizable
- ✓ Feature-rich
- ✓ Modern and polished
- ⚠ Higher resource usage

**Installation:**
```bash
bash vm/setup-dev-vm.sh --scenario=minimal-desktop --desktop=kde
```

**Resources:**
- RAM: ~800MB idle
- Best for: Customization enthusiasts, feature-rich environment

### No Desktop (Headless)

**Advantages:**
- ✓ Minimal resource usage
- ✓ Fastest performance
- ✓ Best for servers

**Installation:**
```bash
bash vm/setup-dev-vm.sh --scenario=headless
```

**Resources:**
- RAM: ~200MB idle
- Best for: Servers, Docker hosts, CLI-only development

---

## Remote Access Setup

### xRDP (Remote Desktop Protocol)

xRDP allows Windows/macOS Remote Desktop clients to connect to your Linux VM.

**Included in:** Desktop scenarios

**Connection:**
```
Windows: mstsc.exe or "Remote Desktop Connection"
macOS: Microsoft Remote Desktop (from App Store)
Linux: Remmina, Vinagre, or rdesktop
```

**Connection Details:**
- Address: VM IP address
- Port: 3389 (default)
- Username: Your VM username
- Password: Your VM password

**Features:**
- ✓ Full desktop access
- ✓ Clipboard sharing
- ✓ File transfer (depending on client)
- ✓ Multi-monitor support (client dependent)

**Troubleshooting xRDP:**
```bash
# Check xRDP status
sudo systemctl status xrdp

# Restart xRDP
sudo systemctl restart xrdp

# Check logs
sudo journalctl -u xrdp -f
```

### SSH Access

SSH is included in all scenarios for command-line access.

**Connection:**
```bash
ssh username@vm-ip-address
```

**Setup SSH Keys (Recommended):**
```bash
# On your host machine
ssh-keygen -t ed25519 -C "your.email@example.com"

# Copy to VM
ssh-copy-id username@vm-ip-address

# Or manually
cat ~/.ssh/id_ed25519.pub | ssh username@vm-ip-address "mkdir -p ~/.ssh && cat >> ~/.ssh/authorized_keys"
```

**SSH Config (on host):**
```bash
# Add to ~/.ssh/config
Host dev-vm
    HostName vm-ip-address
    User username
    IdentityFile ~/.ssh/id_ed25519
    ForwardAgent yes
    
# Then connect with:
ssh dev-vm
```

### VS Code Remote Development

**Installation:**
1. Install "Remote - SSH" extension in VS Code
2. Configure SSH connection (as above)
3. Connect to VM via VS Code

**Benefits:**
- ✓ Full VS Code features on remote VM
- ✓ Local-like experience
- ✓ Terminal integrated
- ✓ Extensions run on VM

### Tailscale (Optional Secure Access)

Tailscale provides secure, encrypted access to your VM from anywhere.

**Included in:** Developer Desktop scenario (optional)

**Setup:**
```bash
# Install Tailscale
curl -fsSL https://tailscale.com/install.sh | sh

# Connect to your Tailscale network
sudo tailscale up --ssh

# Get VM's Tailscale IP
tailscale ip -4
```

**Benefits:**
- ✓ Access VM from anywhere securely
- ✓ No port forwarding needed
- ✓ Built-in SSH
- ✓ Free for personal use

---

## VM Optimization

### Guest Additions/Tools

Install the appropriate guest additions for your hypervisor:

#### VMware Tools (Open VM Tools)

**Auto-installed by envsetup when VMware detected**

**Manual installation:**
```bash
sudo apt install open-vm-tools open-vm-tools-desktop
```

**Features:**
- Time synchronization
- Clipboard sharing
- Drag-and-drop files
- Automatic display resolution
- Shared folders

#### VirtualBox Guest Additions

**Installation:**
```bash
# Install dependencies
sudo apt install build-essential dkms linux-headers-$(uname -r)

# Insert Guest Additions CD (Devices → Insert Guest Additions CD)
sudo mount /dev/cdrom /mnt
sudo /mnt/VBoxLinuxAdditions.run

# Reboot
sudo reboot
```

**Features:**
- Shared folders
- Clipboard sharing
- Drag-and-drop
- Better video support
- Time synchronization

#### Hyper-V Integration Services

**Auto-installed on modern Ubuntu**

**Verify:**
```bash
lsmod | grep hv_
```

**Features:**
- Time synchronization
- Heartbeat
- KVP (Key-Value Pair) exchange
- VSS (Volume Shadow Copy)

#### KVM/QEMU (SPICE/QXL)

**Installation:**
```bash
sudo apt install spice-vdagent qemu-guest-agent
```

**Features:**
- Clipboard sharing
- Better graphics performance
- Time synchronization

### Performance Tuning

**Disable unnecessary services:**
```bash
# Disable Bluetooth (if not needed)
sudo systemctl disable bluetooth

# Disable printer services (if not needed)
sudo systemctl disable cups cups-browsed

# Disable ModemManager (if not needed)
sudo systemctl disable ModemManager
```

**Optimize swap:**
```bash
# Reduce swappiness (less aggressive swap usage)
echo "vm.swappiness=10" | sudo tee -a /etc/sysctl.conf
sudo sysctl -p
```

**Enable TRIM for SSD (VirtualBox):**
```bash
# On host (VirtualBox)
VBoxManage storageattach "VM Name" --storagectl "SATA" --port 0 --device 0 --nonrotational on --discard on
```

### Resource Allocation

**Adjust resources based on usage:**

```bash
# Check current usage
htop  # or top

# Memory
free -h

# Disk
df -h
```

**Recommendations:**
- Start conservative, increase if needed
- Monitor actual usage over time
- Desktop VMs: allocate at least 4GB RAM
- Developer VMs: 8GB+ RAM recommended
- Enable dynamic memory if supported

---

## Network Configuration

### Network Modes

#### NAT (Default)
- ✓ Easy setup, works everywhere
- ✓ VM has internet access
- ⚠ VM not directly accessible from host network
- Use for: Basic development, isolated VMs

**Access VM from host (port forwarding):**
```bash
# VirtualBox example: Forward SSH
VBoxManage modifyvm "VM Name" --natpf1 "ssh,tcp,,2222,,22"
# Connect: ssh -p 2222 username@localhost
```

#### Bridged
- ✓ VM gets IP on host network
- ✓ Accessible from other machines
- ⚠ Requires DHCP or static IP setup
- Use for: Accessible development server, remote testing

#### Host-Only
- ✓ VM and host can communicate
- ✗ No internet access (without additional config)
- Use for: Isolated testing, lab environments

### Static IP Configuration

**For bridged networking:**

```bash
# Edit netplan configuration
sudo nano /etc/netplan/01-netcfg.yaml
```

```yaml
network:
  version: 2
  ethernets:
    ens33:  # Your interface name (check with: ip a)
      dhcp4: no
      addresses:
        - 192.168.1.100/24
      gateway4: 192.168.1.1
      nameservers:
        addresses: [8.8.8.8, 8.8.4.4]
```

```bash
# Apply configuration
sudo netplan apply
```

---

## Best Practices

### Snapshots

**Take snapshots at key points:**
1. ✓ After base OS installation
2. ✓ After envsetup installation
3. ✓ Before major changes
4. ✓ After successful configurations

**Snapshot strategy:**
```
base-install      → Clean OS
post-envsetup     → Base tools installed
desktop-configured → Desktop + tools ready
project-ready     → All development tools configured
```

### VM Organization

**Naming convention:**
```
ubuntu-22.04-dev-desktop
ubuntu-24.04-docker-headless
debian-12-minimal-xfce
```

**Documentation:**
- Keep notes on what's installed
- Document custom configurations
- Save envsetup app lists in version control

### Updates and Maintenance

**Regular updates:**
```bash
# System updates
sudo apt update && sudo apt upgrade -y

# Homebrew (if using envsetup with user-local brew)
brew update && brew upgrade

# Cleanup
sudo apt autoremove -y
sudo apt autoclean
```

**Monthly maintenance:**
1. Update system packages
2. Clear old kernels: `sudo apt autoremove`
3. Check disk usage: `df -h`
4. Review and update snapshots

### Cloning and Templates

**Create a template VM:**
1. Set up base configuration
2. Run: `sudo apt clean && history -c`
3. Shut down VM
4. Clone or export as template
5. Use template for new VMs

**Clean before cloning:**
```bash
# Remove machine-specific data
sudo rm /etc/machine-id
sudo rm /var/lib/dbus/machine-id
sudo touch /etc/machine-id
sudo chmod 444 /etc/machine-id

# Clean history
history -c
rm ~/.bash_history

# Shutdown
sudo shutdown -h now
```

---

## Troubleshooting

### xRDP Issues

**Black screen or session fails:**
```bash
# Edit xRDP startwm.sh
sudo nano /etc/xrdp/startwm.sh

# Add before the last line:
unset DBUS_SESSION_BUS_ADDRESS
unset XDG_RUNTIME_DIR

# Restart xRDP
sudo systemctl restart xrdp
```

**Port already in use:**
```bash
# Check what's using port 3389
sudo lsof -i :3389

# Change xRDP port if needed
sudo nano /etc/xrdp/xrdp.ini
# Change: port=3390
sudo systemctl restart xrdp
```

### Network Issues

**No internet connection:**
```bash
# Check interface
ip a

# Check default route
ip route

# Test DNS
nslookup google.com

# Restart networking
sudo systemctl restart systemd-networkd
```

**Cannot connect to VM:**
```bash
# Check firewall
sudo ufw status

# Allow SSH
sudo ufw allow 22/tcp

# Allow xRDP
sudo ufw allow 3389/tcp

# Enable firewall
sudo ufw enable
```

### Performance Issues

**VM is slow:**
1. Check resource allocation (increase RAM/CPU)
2. Install guest additions/tools
3. Disable unnecessary services
4. Use lighter desktop environment (XFCE instead of GNOME)
5. Enable 3D acceleration
6. Check host machine resources

**High disk usage:**
```bash
# Find large files/directories
du -sh /* | sort -h
ncdu /  # Interactive disk usage analyzer
```

### Display Issues

**Low resolution or can't change resolution:**
```bash
# Install guest additions (see VM Optimization section)

# For VirtualBox
sudo apt install virtualbox-guest-utils virtualbox-guest-x11

# Reboot
sudo reboot
```

**Shared clipboard not working:**
```bash
# VMware
sudo apt install open-vm-tools-desktop

# VirtualBox
sudo apt install virtualbox-guest-utils

# Restart VM
```

### Development Tools Issues

**VS Code won't start:**
```bash
# Install dependencies
sudo apt install libxss1 libasound2

# Check if running
ps aux | grep code

# Try from terminal to see errors
code
```

**Docker permission denied:**
```bash
# Add user to docker group
sudo usermod -aG docker $USER

# Logout and login again (or run)
newgrp docker

# Verify
docker run hello-world
```

---

## Quick Reference

### Common Commands

```bash
# VM Setup
cd ~/src/envsetup
bash vm/setup-dev-vm.sh --scenario=developer-desktop --desktop=xfce

# Check VM info
hostnamectl
lsb_release -a

# Network info
ip a
ip route

# Service management
sudo systemctl status xrdp
sudo systemctl restart xrdp
sudo systemctl status ssh

# System info
htop
df -h
free -h

# Updates
sudo apt update && sudo apt upgrade -y
```

### Resource URLs

- **Ubuntu ISO**: https://ubuntu.com/download/server
- **Debian ISO**: https://www.debian.org/distrib/
- **VirtualBox**: https://www.virtualbox.org/
- **VMware Workstation Player**: https://www.vmware.com/products/workstation-player.html
- **Tailscale**: https://tailscale.com/
- **Microsoft Remote Desktop (macOS)**: Mac App Store

---

## Summary

**Key Recommendations:**

1. **Start with headless or minimal desktop** for faster setup and better performance
2. **Install guest additions/tools** immediately for better integration
3. **Use snapshots** at key milestones
4. **Choose XFCE** for best balance of features and performance
5. **Use SSH keys** instead of passwords
6. **Configure Tailscale** for secure remote access
7. **Take regular backups** of important VMs
8. **Monitor resource usage** and adjust allocation as needed

With these practices, you can maintain efficient, reproducible Linux development VMs that are easy to rebuild and manage.
