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
  echo "  - Ubuntu 20.04+ (including .10 releases)"
  echo "  - Debian 11+ (bullseye, bookworm, trixie, etc.)"
  echo "  - Fedora 35+"
  echo "  - macOS 10.15+"
  echo "Continuing anyway..."
fi

# Parse command line arguments for installation scenario
INSTALL_SCENARIO="developer-desktop"  # default
INSTALL_DOCKER=false
INSTALL_BIN_TOOL=false

for arg in "$@"; do
  case "$arg" in
    --scenario=*)
      INSTALL_SCENARIO="${arg#*=}"
      ;;
    --docker)
      INSTALL_DOCKER=true
      ;;
    --bin)
      INSTALL_BIN_TOOL=true
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --scenario=<type>  Installation scenario (default: developer-desktop)"
      echo "                     Options: developer-desktop, clean-desktop, development-server, production-server, docker-host"
      echo "  --docker           Install Docker CE"
      echo "  --bin              Install marcosnils/bin tool"
      echo "  --help             Show this help message"
      exit 0
      ;;
  esac
done

echo "Installation scenario: $INSTALL_SCENARIO"

# Essential tools to verify/install (base packages for all scenarios)
BASE_TOOLS=(tmux git curl wget jq)

# Additional tools based on installation scenario
case "$INSTALL_SCENARIO" in
  developer-desktop)
    TOOLS=(${BASE_TOOLS[@]} tree htop fzf ripgrep bat)
    ;;
  clean-desktop)
    TOOLS=(${BASE_TOOLS[@]})
    ;;
  development-server)
    TOOLS=(${BASE_TOOLS[@]} tree htop fzf ripgrep bat)
    ;;
  production-server)
    TOOLS=(${BASE_TOOLS[@]})
    ;;
  docker-host)
    TOOLS=(${BASE_TOOLS[@]} tree htop)
    # Docker host scenario automatically enables Docker installation
    INSTALL_DOCKER=true
    ;;
  *)
    echo "Unknown installation scenario: $INSTALL_SCENARIO"
    echo "Using default: developer-desktop"
    TOOLS=(${BASE_TOOLS[@]} tree htop fzf ripgrep bat)
    ;;
esac

echo "Installing tools: ${TOOLS[@]}"

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

# Function to install tools on Fedora
install_fedora() {
  echo "Updating package list..."
  sudo dnf check-update || true
  
  echo "Installing tools for $(get_os_display_name)..."
  for tool in "${TOOLS[@]}"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      if is_tool_available "$tool"; then
        package_name=$(get_package_name "$tool")
        echo "Installing $tool (package: $package_name)..."
        
        if sudo dnf install -y "$package_name"; then
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

# Function to install hypervisor guest agent
install_hypervisor_agent() {
  # Detect hypervisor
  detect_hypervisor
  
  if [ "$HYPERVISOR" = "none" ]; then
    echo "Running on physical hardware, skipping hypervisor agent installation."
    return 0
  fi
  
  echo "Detected hypervisor: $(get_hypervisor_name)"
  
  # Get the appropriate package name
  local agent_package
  agent_package=$(get_hypervisor_agent_package "$HYPERVISOR")
  
  if [ -z "$agent_package" ]; then
    echo "No hypervisor agent available for $HYPERVISOR on $(get_os_display_name)."
    return 0
  fi
  
  echo "Installing hypervisor agent: $agent_package..."
  
  case "$OS_NAME" in
    ubuntu|debian)
      if sudo apt install -y "$agent_package"; then
        echo "Hypervisor agent $agent_package installed successfully."
        
        # Enable and start services if applicable
        case "$HYPERVISOR" in
          vmware)
            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl enable --now open-vm-tools 2>/dev/null || true
            fi
            ;;
          virtualbox)
            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl enable --now virtualbox-guest-utils 2>/dev/null || true
            fi
            ;;
          kvm|qemu)
            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
            fi
            ;;
        esac
      else
        echo "Warning: Failed to install hypervisor agent $agent_package."
      fi
      ;;
    fedora)
      if sudo dnf install -y "$agent_package"; then
        echo "Hypervisor agent $agent_package installed successfully."
        
        # Enable and start services if applicable
        case "$HYPERVISOR" in
          vmware)
            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl enable --now vmtoolsd 2>/dev/null || true
            fi
            ;;
          kvm|qemu)
            if command -v systemctl >/dev/null 2>&1; then
              sudo systemctl enable --now qemu-guest-agent 2>/dev/null || true
            fi
            ;;
        esac
      else
        echo "Warning: Failed to install hypervisor agent $agent_package."
      fi
      ;;
  esac
}

# Function to install marcosnils/bin
install_bin_tool() {
  if command -v bin >/dev/null 2>&1; then
    echo "bin is already installed."
    return
  fi
  
  echo "Installing marcosnils/bin..."
  mkdir -p "$HOME/bin"
  
  # Download and install bin
  if curl -sSL https://raw.githubusercontent.com/marcosnils/bin/master/install.sh | bash -s -- -d "$HOME/bin"; then
    echo "bin installed successfully to ~/bin/"
    echo "Make sure ~/bin is in your PATH"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
      echo "Added ~/bin to PATH in .bashrc"
    fi
  else
    echo "Warning: Failed to install bin. Please install manually from https://github.com/marcosnils/bin"
  fi
}

# Check for --docker flag (legacy support)
for arg in "$@"; do
  if [ "$arg" == "--docker" ]; then
    INSTALL_DOCKER=true
  fi
done

# Function to install Docker CE on Linux
install_docker_linux() {
  if command -v docker >/dev/null 2>&1; then
    echo "Docker is already installed."
    
    # Check if user is in docker group
    if ! groups | grep -q docker; then
      echo "Adding current user to docker group..."
      sudo usermod -aG docker "$USER"
      echo "User $USER added to docker group."
      echo "Note: You need to log out and back in for group changes to take effect."
    else
      echo "User $USER is already in docker group."
    fi
    return
  fi
  
  echo "Installing Docker CE for $(get_os_display_name)..."
  
  case "$OS_NAME" in
    ubuntu|debian)
      sudo apt update
      sudo apt install -y ca-certificates curl gnupg
      sudo install -m 0755 -d /etc/apt/keyrings
      
      # Use appropriate Docker repository for the OS
      if [ "$OS_NAME" = "ubuntu" ]; then
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          $(lsb_release -cs) stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      else
        curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        echo \
          "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian \
          $(lsb_release -cs) stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
      fi
      
      sudo apt update
      if sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        echo "Docker CE installation complete."
        
        # Add current user to docker group for non-root access
        echo "Adding current user to docker group for non-root access..."
        sudo usermod -aG docker "$USER"
        echo "User $USER added to docker group."
        echo "Note: You need to log out and back in for group changes to take effect."
        echo "Or run: newgrp docker"
      else
        echo "Warning: Docker CE installation failed. Please install manually."
      fi
      ;;
    fedora)
      sudo dnf -y install dnf-plugins-core
      sudo dnf config-manager --add-repo https://download.docker.com/linux/fedora/docker-ce.repo
      if sudo dnf install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin; then
        echo "Docker CE installation complete."
        echo "Starting Docker service..."
        sudo systemctl start docker
        sudo systemctl enable docker
        
        # Add current user to docker group for non-root access
        echo "Adding current user to docker group for non-root access..."
        sudo usermod -aG docker "$USER"
        echo "User $USER added to docker group."
        echo "Note: You need to log out and back in for group changes to take effect."
        echo "Or run: newgrp docker"
      else
        echo "Warning: Docker CE installation failed. Please install manually."
      fi
      ;;
  esac
}

# Detect OS and run appropriate installer
echo "Running installer for $(get_os_display_name)..."
if [[ "$OS_NAME" == "ubuntu" ]] || [[ "$OS_NAME" == "debian" ]]; then
  install_linux
  # Install hypervisor agent for VMs
  install_hypervisor_agent
  if [ "$INSTALL_DOCKER" = true ]; then
    install_docker_linux
  fi
elif [[ "$OS_NAME" == "fedora" ]]; then
  install_fedora
  # Install hypervisor agent for VMs
  install_hypervisor_agent
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

# Install bin tool if requested
if [ "$INSTALL_BIN_TOOL" = true ]; then
  install_bin_tool
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