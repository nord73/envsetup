#!/bin/bash
# vm/setup-dev-vm.sh
# Enhanced Linux VM setup script with scenario support

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# Default values
SCENARIO="developer-desktop"
DESKTOP="xfce"
INSTALL_DOCKER=false
INSTALL_VSCODE=false
INSTALL_TAILSCALE=false
INSTALL_FONTS=false

# Help message
show_help() {
cat << EOF
Linux VM Development Environment Setup

USAGE:
    bash vm/setup-dev-vm.sh [OPTIONS]

OPTIONS:
    --scenario=<type>      Setup scenario (default: developer-desktop)
                          Options: headless, minimal-desktop, developer-desktop, remote-dev
    --desktop=<env>        Desktop environment (default: xfce)
                          Options: none, xfce, gnome, kde
    --docker               Install Docker CE
    --vscode               Install Visual Studio Code
    --tailscale            Install and configure Tailscale
    --no-fonts             Skip font installation
    --help                 Show this help message

SCENARIOS:
    headless              No GUI, minimal tools, SSH only
    minimal-desktop       Lightweight desktop with xRDP
    developer-desktop     Full development environment with GUI
    remote-dev            Headless with all dev tools (VS Code Remote ready)

DESKTOP ENVIRONMENTS:
    none                  No desktop (headless)
    xfce                  Lightweight, fast (recommended)
    gnome                 Modern Ubuntu desktop (heavier)
    kde                   Feature-rich Plasma desktop (heavier)

EXAMPLES:
    # Minimal desktop with XFCE
    bash vm/setup-dev-vm.sh --scenario=minimal-desktop --desktop=xfce

    # Full developer environment
    bash vm/setup-dev-vm.sh --scenario=developer-desktop --desktop=xfce --docker --vscode

    # Headless remote development server
    bash vm/setup-dev-vm.sh --scenario=remote-dev --docker --vscode

    # Minimal GNOME desktop
    bash vm/setup-dev-vm.sh --scenario=minimal-desktop --desktop=gnome

DOCUMENTATION:
    See VM_SETUP.md for comprehensive setup guide and best practices

EOF
}

# Parse arguments
for arg in "$@"; do
  case "$arg" in
    --scenario=*)
      SCENARIO="${arg#*=}"
      ;;
    --desktop=*)
      DESKTOP="${arg#*=}"
      ;;
    --docker)
      INSTALL_DOCKER=true
      ;;
    --vscode)
      INSTALL_VSCODE=true
      ;;
    --tailscale)
      INSTALL_TAILSCALE=true
      ;;
    --no-fonts)
      INSTALL_FONTS=false
      ;;
    --help)
      show_help
      exit 0
      ;;
    *)
      echo "Unknown option: $arg"
      echo "Use --help for usage information"
      exit 1
      ;;
  esac
done

# Validate scenario
case "$SCENARIO" in
  headless|minimal-desktop|developer-desktop|remote-dev)
    ;;
  *)
    echo "Error: Invalid scenario '$SCENARIO'"
    echo "Valid scenarios: headless, minimal-desktop, developer-desktop, remote-dev"
    exit 1
    ;;
esac

# Validate desktop environment
case "$DESKTOP" in
  none|xfce|gnome|kde)
    ;;
  *)
    echo "Error: Invalid desktop environment '$DESKTOP'"
    echo "Valid options: none, xfce, gnome, kde"
    exit 1
    ;;
esac

# Adjust settings based on scenario
case "$SCENARIO" in
  headless)
    DESKTOP="none"
    INSTALL_FONTS=false
    ;;
  minimal-desktop)
    if [ "$DESKTOP" = "none" ]; then
      DESKTOP="xfce"
    fi
    ;;
  developer-desktop)
    if [ "$DESKTOP" = "none" ]; then
      DESKTOP="xfce"
    fi
    INSTALL_VSCODE=true
    INSTALL_FONTS=true
    ;;
  remote-dev)
    DESKTOP="none"
    INSTALL_VSCODE=true
    INSTALL_FONTS=false
    ;;
esac

echo "=========================================="
echo "Linux VM Development Environment Setup"
echo "=========================================="
echo "Scenario: $SCENARIO"
echo "Desktop: $DESKTOP"
echo "Docker: $INSTALL_DOCKER"
echo "VS Code: $INSTALL_VSCODE"
echo "Tailscale: $INSTALL_TAILSCALE"
echo "Fonts: $INSTALL_FONTS"
echo "=========================================="
echo ""

# Update system
echo "==> Updating system packages..."
sudo apt update
sudo apt upgrade -y

# Install base development tools using envsetup bootstrap
echo "==> Installing base tools via envsetup bootstrap..."
if [ -f "$REPO_ROOT/scripts/bootstrap.sh" ]; then
  ENVSETUP_ARGS=""
  
  case "$SCENARIO" in
    headless|remote-dev)
      ENVSETUP_ARGS="--scenario=production-server"
      ;;
    minimal-desktop)
      ENVSETUP_ARGS="--scenario=clean-desktop"
      ;;
    developer-desktop)
      ENVSETUP_ARGS="--scenario=developer-desktop"
      ;;
  esac
  
  if [ "$INSTALL_DOCKER" = true ]; then
    ENVSETUP_ARGS="$ENVSETUP_ARGS --docker"
  fi
  
  bash "$REPO_ROOT/scripts/bootstrap.sh" $ENVSETUP_ARGS
else
  echo "Warning: bootstrap.sh not found, installing tools manually..."
  sudo apt install -y tmux git curl wget jq tree htop build-essential
fi

# Install desktop environment
if [ "$DESKTOP" != "none" ]; then
  echo "==> Installing $DESKTOP desktop environment..."
  
  case "$DESKTOP" in
    xfce)
      echo "Installing XFCE (lightweight)..."
      sudo apt install -y xfce4 xfce4-goodies lightdm
      ;;
    gnome)
      echo "Installing GNOME minimal..."
      sudo apt install --no-install-recommends -y ubuntu-desktop-minimal
      ;;
    kde)
      echo "Installing KDE Plasma..."
      sudo apt install -y kde-plasma-desktop
      ;;
  esac
  
  # Install xRDP for remote desktop access
  echo "==> Installing xRDP..."
  sudo apt install -y xrdp
  sudo systemctl enable xrdp
  sudo adduser xrdp ssl-cert 2>/dev/null || true
  
  echo ""
  echo "xRDP installed. You can connect via Remote Desktop to this VM's IP address."
  echo "Use your Linux username and password to login."
  echo ""
fi

# Install language runtimes and tools for developer scenarios
if [ "$SCENARIO" = "developer-desktop" ] || [ "$SCENARIO" = "remote-dev" ]; then
  echo "==> Installing development tools..."
  
  # Python
  sudo apt install -y python3 python3-pip python3-venv
  
  # Node.js via nvm
  if [ ! -d "$HOME/.nvm" ]; then
    echo "Installing nvm (Node Version Manager)..."
    NVM_VERSION="v0.40.1"  # Use specific version for reproducibility
    curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${NVM_VERSION}/install.sh" | bash
    export NVM_DIR="$HOME/.nvm"
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
  fi
fi

# Install VS Code
if [ "$INSTALL_VSCODE" = true ]; then
  echo "==> Installing Visual Studio Code..."
  
  # Install dependencies
  sudo apt install -y gnome-keyring
  
  # Download and install VS Code via official Microsoft repository (more secure)
  if ! command -v code >/dev/null 2>&1; then
    echo "Adding Microsoft repository..."
    wget -qO- https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor > /tmp/packages.microsoft.gpg
    sudo install -D -o root -g root -m 644 /tmp/packages.microsoft.gpg /etc/apt/keyrings/packages.microsoft.gpg
    sudo sh -c 'echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" > /etc/apt/sources.list.d/vscode.list'
    rm -f /tmp/packages.microsoft.gpg
    
    echo "Installing VS Code from Microsoft repository..."
    sudo apt update
    sudo apt install -y code
    echo "VS Code installed successfully."
  else
    echo "VS Code already installed."
  fi
fi

# Install fonts for better development experience
if [ "$INSTALL_FONTS" = true ]; then
  echo "==> Installing developer fonts..."
  sudo apt install -y \
    fonts-firacode \
    fonts-jetbrains-mono \
    fonts-cascadia-code \
    fonts-dejavu \
    fonts-ubuntu
  
  # Create fontconfig for better rendering
  mkdir -p ~/.config/fontconfig
  cat > ~/.config/fontconfig/fonts.conf << 'EOF'
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <match target="font">
    <edit name="antialias" mode="assign">
      <bool>true</bool>
    </edit>
    <edit name="hinting" mode="assign">
      <bool>true</bool>
    </edit>
    <edit name="hintstyle" mode="assign">
      <const>hintslight</const>
    </edit>
    <edit name="rgba" mode="assign">
      <const>rgb</const>
    </edit>
  </match>
</fontconfig>
EOF
  
  # Rebuild font cache
  fc-cache -fv
  echo "Fonts installed and configured."
fi

# Install Tailscale
if [ "$INSTALL_TAILSCALE" = true ]; then
  echo "==> Installing Tailscale..."
  if ! command -v tailscale >/dev/null 2>&1; then
    echo "Adding Tailscale repository..."
    
    # Detect distribution codename
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      DISTRO_CODENAME="${VERSION_CODENAME:-jammy}"
    else
      DISTRO_CODENAME="jammy"
    fi
    
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/${DISTRO_CODENAME}.noarmor.gpg | sudo tee /usr/share/keyrings/tailscale-archive-keyring.gpg >/dev/null
    curl -fsSL https://pkgs.tailscale.com/stable/ubuntu/${DISTRO_CODENAME}.tailscale-keyring.list | sudo tee /etc/apt/sources.list.d/tailscale.list
    sudo apt update
    sudo apt install -y tailscale
    echo ""
    echo "Tailscale installed. Run 'sudo tailscale up --ssh' to connect to your network."
    echo ""
  else
    echo "Tailscale already installed."
  fi
fi

# Restore networkd renderer if desktop was installed
if [ "$DESKTOP" != "none" ]; then
  echo "==> Restoring networkd renderer in netplan..."
  if ls /etc/netplan/*.yaml 1> /dev/null 2>&1; then
    sudo sed -i 's/renderer: NetworkManager/renderer: networkd/g' /etc/netplan/*.yaml 2>/dev/null || true
  fi
fi

# Print summary
echo ""
echo "=========================================="
echo "VM Setup Complete!"
echo "=========================================="
echo "Scenario: $SCENARIO"
echo "Desktop: $DESKTOP"

if [ "$DESKTOP" != "none" ]; then
  echo ""
  echo "Remote Desktop Access:"
  echo "  - Use Remote Desktop client (xRDP)"
  echo "  - Connect to: $(hostname -I | awk '{print $1}'):3389"
  echo "  - Username: $(whoami)"
fi

echo ""
echo "SSH Access:"
echo "  - ssh $(whoami)@$(hostname -I | awk '{print $1}')"

if [ "$INSTALL_TAILSCALE" = true ] && command -v tailscale >/dev/null 2>&1; then
  echo ""
  echo "Tailscale:"
  echo "  - Run: sudo tailscale up --ssh"
  echo "  - Then: ssh <tailscale-ip>"
fi

if [ "$INSTALL_VSCODE" = true ]; then
  echo ""
  echo "VS Code:"
  echo "  - Desktop: Launch 'Visual Studio Code' from menu"
  echo "  - Remote: Use 'Remote - SSH' extension"
fi

if [ "$INSTALL_DOCKER" = true ]; then
  echo ""
  echo "Docker:"
  echo "  - Logout and login for docker group to take effect"
  echo "  - Or run: newgrp docker"
fi

echo ""
echo "Next Steps:"
echo "  1. Reboot for all changes to take effect: sudo reboot"
if [ "$DESKTOP" != "none" ]; then
  echo "  2. Connect via Remote Desktop client"
fi
echo "  3. Configure your development environment"
echo ""
echo "For more information, see VM_SETUP.md"
echo "=========================================="
