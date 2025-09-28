#!/bin/bash

set -e

# Start with server install, then add desktop components
sudo apt update && sudo apt upgrade -y

# Install minimal desktop (lighter than ubuntu-desktop-minimal)
sudo apt install --no-install-recommends ubuntu-desktop-minimal -y

# Alternative to buntu-desktop-minimal, with XFCE:
# sudo apt install xfce4 xfce4-goodies lightdm -y

echo "Installing xRDP..."
sudo apt install -y xrdp
sudo systemctl enable xrdp
sudo adduser xrdp ssl-cert

echo "Installing Tailscale..."
curl -fsSL https://tailscale.com/install.sh | sh
sudo tailscale up --ssh

echo "Installing common dev tools..."
sudo apt install -y git curl wget build-essential \
  python3 python3-pip \
  nodejs npm 

### nvm
wget -q -O- https://raw.githubusercontent.com/nvm-sh/nvm/master/install.sh | bash

### vscode
# apt install -y code # If added MS repo for code or use Code-OSS

  
### Docker
# apt get -y docker.io docker-compose if not using compose CE + compose plugin
# echo "Adding user to docker group..."
# sudo usermod -aG docker $USER

### Fonts
# Nerd Fonts (includes icons/symbols)
sudo apt install -y fonts-firacode fonts-jetbrains-mono fonts-cascadia-code fonts-dejavu fonts-ubuntu

# Create fontconfig for better rendering
mkdir -p ~/.config/fontconfig
cat > ~/.config/fontconfig/fonts.conf << EOF
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


### Cleanup before reboot
# Restore networkd renderer in netplan
sudo sed -i 's/renderer: NetworkManager/renderer: networkd/g' /etc/netplan/*.yaml


echo "All done. Rebooting is recommended."
