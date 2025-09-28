#!/bin/bash

set -e

echo "Updating system..."
sudo apt update && sudo apt upgrade -y

echo "Installing XFCE desktop environment..."
sudo apt install -y xfce4 xfce4-goodies

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
