#!/bin/bash
# scripts/bootstrap.sh
# Minimal environment setup for Ubuntu/Debian/MacOS

set -e

# Essential tools to verify/install
TOOLS=(git curl wget tree htop fzf ripgrep bat jq)

# Create user directories
mkdir -p "$HOME/bin" "$HOME/src"

# Function to install tools on Linux
install_linux() {
  sudo apt update
  for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Installing $tool..."
      sudo apt install -y "$tool"
    else
      echo "$tool is already installed."
    fi
  done
}

# Function to install tools on MacOS
install_macos() {
  BREW_PREFIX="$HOME/.brew"
  BREW_BIN="$BREW_PREFIX/bin/brew"
  if ! command -v brew >/dev/null 2>&1 && [ ! -x "$BREW_BIN" ]; then
    echo "Installing Homebrew to $BREW_PREFIX..."
    git clone https://github.com/Homebrew/brew "$BREW_PREFIX"
    echo "export PATH=\"$BREW_PREFIX/bin:$PATH\"" > "$HOME/bin/brew-source.sh"
    echo "export HOMEBREW_PREFIX=\"$BREW_PREFIX\"" >> "$HOME/bin/brew-source.sh"
    chmod +x "$HOME/bin/brew-source.sh"
    echo "Run 'source ~/bin/brew-source.sh' to activate Homebrew in your shell."
  fi
  # Source Homebrew if installed locally
  if [ -x "$BREW_BIN" ]; then
    export PATH="$BREW_PREFIX/bin:$PATH"
  fi
  for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      echo "Installing $tool..."
      brew install "$tool"
    else
      echo "$tool is already installed."
    fi
  done
}

# Check for --docker flag
INSTALL_DOCKER=false
for arg in "$@"; do
  if [ "$arg" == "--docker" ]; then
    INSTALL_DOCKER=true
  fi
done

# Function to install Docker CE on Linux
install_docker_linux() {
  if command -v docker >/dev/null 2>&1; then
    echo "Docker is already installed."
    return
  fi
  echo "Installing Docker CE..."
  sudo apt update
  sudo apt install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
  echo \
    "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
    $(lsb_release -cs) stable" | \
    sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
  sudo apt update
  sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  echo "Docker CE installation complete."
}

# Detect OS and run appropriate installer
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  install_linux
  if [ "$INSTALL_DOCKER" = true ]; then
    install_docker_linux
  fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
  install_macos
  # On MacOS, recommend Docker Desktop
  if [ "$INSTALL_DOCKER" = true ]; then
    echo "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
  fi
else
  echo "Unsupported OS: $OSTYPE"
  exit 1
fi

# Symlink dotfiles (if present)
DOTFILES=(.bashrc .profile .gitconfig .vimrc)
for dotfile in "${DOTFILES[@]}"; do
  if [ -f "dotfiles/$dotfile" ]; then
    ln -sf "$PWD/dotfiles/$dotfile" "$HOME/$dotfile"
    echo "Symlinked $dotfile"
  fi
done

echo "Environment setup complete!"