#!/bin/bash
# scripts/bootstrap.sh
# Minimal environment setup for Ubuntu/Debian/MacOS with multi-version support

set -e

# Get script directory for sourcing other scripts
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source OS detection and package mappings
source "$SCRIPT_DIR/os_detection.sh"
source "$SCRIPT_DIR/package_mappings.sh"

# Detect OS and version
echo "Detecting operating system..."
if ! detect_os; then
  echo "Failed to detect OS. Exiting."
  exit 1
fi

echo "Detected: $(get_os_display_name)"

# Check if OS version is supported
if ! is_supported_version; then
  echo "Warning: $(get_os_display_name) may not be fully supported."
  echo "Supported versions:"
  echo "  - Ubuntu 20.04+"
  echo "  - Debian 11+ (bullseye, bookworm, trixie, etc.)"
  echo "  - macOS 10.15+"
  echo "Continuing anyway..."
fi

# Essential tools to verify/install
TOOLS=(git curl wget tree htop fzf ripgrep bat jq)

# Create user directories
mkdir -p "$HOME/bin" "$HOME/src"

# Function to install tools on Linux (Ubuntu/Debian)
install_linux() {
  echo "Updating package list..."
  sudo apt update
  
  echo "Installing tools for $(get_os_display_name)..."
  for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      if is_tool_available "$tool"; then
        package_name=$(get_package_name "$tool")
        echo "Installing $tool (package: $package_name)..."
        
        if sudo apt install -y "$package_name"; then
          echo "$tool installed successfully."
        else
          echo "Warning: Failed to install $tool ($package_name). Skipping..."
        fi
      else
        echo "Warning: $tool is not available for $(get_os_display_name). Skipping..."
      fi
    else
      echo "$tool is already installed."
    fi
  done
  
  # Handle special cases for package naming differences
  if [ "$OS_NAME" = "debian" ] && [ "$OS_MAJOR_VERSION" = "11" ]; then
    # In Debian 11, bat is installed as batcat, create alias if needed
    if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
      echo "Creating bat alias for batcat..."
      mkdir -p "$HOME/bin"
      ln -sf "$(which batcat)" "$HOME/bin/bat"
      echo "Created bat -> batcat alias in ~/bin/"
    fi
  fi
}

# Function to install tools on MacOS
install_macos() {
  BREW_PREFIX="$HOME/.brew"
  BREW_BIN="$BREW_PREFIX/bin/brew"
  if ! command -v brew >/dev/null 2>&1 && [ ! -x "$BREW_BIN" ]; then
    echo "Installing Homebrew to $BREW_PREFIX..."
    git clone https://github.com/Homebrew/brew "$BREW_PREFIX"
    echo "export PATH=\"$BREW_PREFIX/bin:\$PATH\"" > "$HOME/bin/brew-source.sh"
    echo "export HOMEBREW_PREFIX=\"$BREW_PREFIX\"" >> "$HOME/bin/brew-source.sh"
    chmod +x "$HOME/bin/brew-source.sh"
    echo "Run 'source ~/bin/brew-source.sh' to activate Homebrew in your shell."
  fi
  # Source Homebrew if installed locally
  if [ -x "$BREW_BIN" ]; then
    export PATH="$BREW_PREFIX/bin:$PATH"
  fi
  
  echo "Installing tools for $(get_os_display_name)..."
  for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      if is_tool_available "$tool"; then
        package_name=$(get_package_name "$tool")
        echo "Installing $tool (package: $package_name)..."
        
        if brew install "$package_name"; then
          echo "$tool installed successfully."
        else
          echo "Warning: Failed to install $tool ($package_name). Skipping..."
        fi
      else
        echo "Warning: $tool is not available for $(get_os_display_name). Skipping..."
      fi
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
  
  echo "Installing Docker CE for $(get_os_display_name)..."
  sudo apt update
  sudo apt install -y ca-certificates curl gnupg
  sudo install -m 0755 -d /etc/apt/keyrings
  
  # Use appropriate Docker repository for the OS
  case "$OS_NAME" in
    ubuntu)
      curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
        $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      ;;
    debian)
      curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
      echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
        $(lsb_release -cs) stable" | \
        sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      ;;
  esac
  
  sudo apt update
  if sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
    echo "Docker CE installation complete."
  else
    echo "Warning: Docker CE installation failed. Please install manually."
  fi
}

# Detect OS and run appropriate installer
echo "Running installer for $(get_os_display_name)..."
if [[ "$OS_NAME" == "ubuntu" ]] || [[ "$OS_NAME" == "debian" ]]; then
  install_linux
  if [ "$INSTALL_DOCKER" = true ]; then
    install_docker_linux
  fi
elif [[ "$OS_NAME" == "macos" ]]; then
  install_macos
  # On MacOS, recommend Docker Desktop
  if [ "$INSTALL_DOCKER" = true ]; then
    echo "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
  fi
else
  echo "Unsupported OS: $(get_os_display_name)"
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