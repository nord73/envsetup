#!/bin/bash

set -e

# Start with server install, then add desktop components
sudo apt update && sudo apt upgrade -y

# Install minimal desktop (lighter than ubuntu-desktop-minimal)
sudo apt install --no-install-recommends ubuntu-desktop-minimal -y

# Or even lighter with XFCE:
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
  docker.io docker-compose \
  nodejs npm \
  code # If you add MS repo for code or use Code-OSS

echo "Adding user to docker group..."
sudo usermod -aG docker $USER

echo "All done. Rebooting is recommended."
