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
INSTALL_MACOS_APPS=false
INSTALL_MAS_APPS=false
INSTALL_LINUX_PACKAGES=false
INSTALL_FLATPAK_APPS=false
INSTALL_TAILSCALE=false

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
    --apps)
      INSTALL_MACOS_APPS=true
      ;;
    --mas)
      INSTALL_MAS_APPS=true
      ;;
    --packages)
      INSTALL_LINUX_PACKAGES=true
      ;;
    --flatpak)
      INSTALL_FLATPAK_APPS=true
      ;;
    --tailscale)
      INSTALL_TAILSCALE=true
      ;;
    --help)
      echo "Usage: $0 [OPTIONS]"
      echo ""
      echo "Options:"
      echo "  --scenario=<type>  Installation scenario (default: developer-desktop)"
      echo "                     Options: developer-desktop, clean-desktop, development-server, server, production-server, docker-host"
      echo "  --docker           Install Docker CE"
      echo "  --bin              Install marcosnils/bin tool"
      echo "  --apps             Install macOS applications from macos-apps.txt (Homebrew Cask)"
      echo "  --mas              Install macOS App Store applications from mas-apps.txt"
      echo "  --packages         Install Linux packages from linux-packages.txt (Ubuntu/Debian/Fedora)"
      echo "  --flatpak          Install Flatpak applications from flatpak-apps.txt"
      echo "  --tailscale        Install Tailscale VPN (macOS/Linux)"
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
  server)
    TOOLS=(${BASE_TOOLS[@]} tree htop)
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

# Function to check if Xcode Command Line Tools are installed
check_xcode_clt() {
  xcode-select -p >/dev/null 2>&1
}

# Function to check if Xcode license has been accepted
check_xcode_license() {
  # Try to run xcodebuild to check license status
  # If license hasn't been accepted, it will fail with specific error
  if ! check_xcode_clt; then
    return 2  # CLT not installed, can't check license
  fi
  
  # Check if xcodebuild exists and can be run
  # Note: Some minimal Xcode CLT installations may not include xcodebuild.
  # This is acceptable for Homebrew as it primarily needs compilers (clang, make)
  # which are available even without xcodebuild.
  if ! command -v xcodebuild >/dev/null 2>&1; then
    return 0  # xcodebuild not available, assume OK for Homebrew usage
  fi
  
  # Run xcodebuild -license check
  xcodebuild -license check >/dev/null 2>&1
}

# Function to ensure Xcode Command Line Tools are ready for Homebrew
ensure_xcode_ready() {
  echo "Checking Xcode Command Line Tools..."
  
  if ! check_xcode_clt; then
    echo ""
    echo "=========================================="
    echo "⚠️  Xcode Command Line Tools Not Found"
    echo "=========================================="
    echo ""
    echo "Xcode Command Line Tools are required for Homebrew to compile"
    echo "packages from source. Some packages may fail to install without them."
    echo ""
    echo "To install Xcode Command Line Tools, run:"
    echo "  xcode-select --install"
    echo ""
    echo "Then follow the prompts to complete the installation."
    echo ""
    echo "After installation, run this script again."
    echo "=========================================="
    echo ""
    read -p "Continue without Xcode CLT? Some packages may fail. (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
      echo "Installation cancelled. Please install Xcode Command Line Tools first."
      exit 1
    fi
    echo "Continuing... Note: Some packages may fail to install."
    # CLT not installed, but user chose to continue
  fi
  
  echo "✓ Xcode Command Line Tools are installed at: $(xcode-select -p)"
  
  # Check license status
  local license_status
  check_xcode_license
  license_status=$?
  
  if [ $license_status -eq 1 ]; then
    echo ""
    echo "⚠️  Xcode license has not been accepted. Accepting it now..."
    echo ""
    if sudo xcodebuild -license accept; then
      echo "✓ Xcode license accepted successfully"
    else
      echo "Error: Failed to accept Xcode license. Please run manually:"
      echo "  sudo xcodebuild -license accept"
      exit 1
    fi
  else
    echo "✓ Xcode license has been accepted"
  fi
  return 0
}

# Function to install tools on MacOS
install_macos() {
  BREW_PREFIX="$HOME/.brew"
  BREW_BIN="$BREW_PREFIX/bin/brew"
  
  # Check for existing Homebrew installation (system-wide)
  if command -v brew >/dev/null 2>&1; then
    echo "Using existing Homebrew installation at $(which brew)"
  elif [ -x "$BREW_BIN" ]; then
    echo "Using existing Homebrew installation at $BREW_PREFIX"
    export PATH="$BREW_PREFIX/bin:$PATH"
  else
    # Install Homebrew to user-local directory
    echo "Installing Homebrew to $BREW_PREFIX (user-local, non-root)..."
    git clone https://github.com/Homebrew/brew "$BREW_PREFIX"
    
    # Create brew-source.sh activation script
    cat > "$HOME/bin/brew-source.sh" << 'BREWEOF'
#!/bin/bash
# Activate user-local Homebrew installation
export PATH="$HOME/.brew/bin:$PATH"
export HOMEBREW_PREFIX="$HOME/.brew"
BREWEOF
    chmod +x "$HOME/bin/brew-source.sh"
    
    echo ""
    echo "=========================================="
    echo "Homebrew installed to $BREW_PREFIX"
    echo ""
    echo "To activate Homebrew, run:"
    echo "  source ~/bin/brew-source.sh"
    echo ""
    echo "Or add to your shell profile (~/.bashrc, ~/.zshrc, etc.):"
    echo "  source ~/bin/brew-source.sh"
    echo "=========================================="
    echo ""
    
    # Source for current session
    export PATH="$BREW_PREFIX/bin:$PATH"
    export HOMEBREW_PREFIX="$BREW_PREFIX"
  fi
  
  # Ensure Xcode Command Line Tools are ready before installing packages
  ensure_xcode_ready
  
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

# Function to create uninstall helper script for macOS apps
create_uninstall_helper() {
  local uninstall_script="$HOME/bin/uninstall-app.sh"
  
  cat > "$uninstall_script" << 'UNINSTALLEOF'
#!/bin/bash
# uninstall-app.sh
# Helper script to uninstall macOS apps without sudo
# This script manually removes apps and their components without requiring sudo

set -e

if [ $# -eq 0 ]; then
  echo "Usage: $0 <app-name>"
  echo ""
  echo "Uninstalls a macOS application installed via Homebrew Cask without requiring sudo."
  echo ""
  echo "Examples:"
  echo "  $0 visual-studio-code"
  echo "  $0 iterm2"
  echo "  $0 docker"
  echo ""
  echo "This script:"
  echo "  1. Stops and removes user-level LaunchAgents"
  echo "  2. Removes the app from ~/Applications or /Applications"
  echo "  3. Cleans up Homebrew's tracking database"
  echo ""
  echo "Note: Apps in /Applications may require sudo to remove"
  exit 1
fi

APP_NAME="$1"

echo "Uninstalling $APP_NAME..."

# Get the app display name from Homebrew
# Try to get it reliably, with fallback to the app name if it fails
APP_DISPLAY_NAME=""
if command -v brew >/dev/null 2>&1; then
  # First try: use brew info to get the cask name
  APP_DISPLAY_NAME=$(brew info --cask "$APP_NAME" 2>/dev/null | head -1 | awk '{print $1}' | sed 's/://') || true
fi

if [ -z "$APP_DISPLAY_NAME" ]; then
  # Fallback: use the provided app name
  echo "Warning: Could not find app info from Homebrew. Proceeding with manual cleanup..."
  APP_DISPLAY_NAME="$APP_NAME"
fi

# Find the .app bundle in ~/Applications or /Applications
APP_BUNDLE=$(find "$HOME/Applications" -maxdepth 1 \( -iname "*${APP_DISPLAY_NAME}*.app" -o -iname "*${APP_NAME}*.app" \) 2>/dev/null | head -1)

if [ -z "$APP_BUNDLE" ]; then
  # Check system Applications directory
  APP_BUNDLE=$(find "/Applications" -maxdepth 1 \( -iname "*${APP_DISPLAY_NAME}*.app" -o -iname "*${APP_NAME}*.app" \) 2>/dev/null | head -1)
  if [ -n "$APP_BUNDLE" ]; then
    echo "Found app bundle in system Applications: $APP_BUNDLE"
    echo "Note: This app is in /Applications (system) and may require sudo to remove."
  else
    echo "Warning: Could not find app bundle in ~/Applications or /Applications"
  fi
else
  echo "Found app bundle: $APP_BUNDLE"
fi

# Stop and remove LaunchAgents associated with the app
echo "Checking for LaunchAgents..."
LAUNCH_AGENTS_DIR="$HOME/Library/LaunchAgents"
if [ -d "$LAUNCH_AGENTS_DIR" ]; then
  # Common LaunchAgent patterns for the app
  # Properly quote the command substitution to prevent word splitting
  pattern_without_dash="$(echo "$APP_NAME" | sed 's/-//g')"
  for pattern in "$APP_NAME" "$APP_DISPLAY_NAME" "$pattern_without_dash"; do
    # Use nullglob-like behavior by checking if glob matches any files
    shopt -s nullglob 2>/dev/null || true  # Enable nullglob if available (bash 4+)
    plist_files=("$LAUNCH_AGENTS_DIR"/*"$pattern"*.plist)
    shopt -u nullglob 2>/dev/null || true  # Disable nullglob
    
    for plist in "${plist_files[@]}"; do
      # Additional check to ensure the file exists (for bash 3.2 compatibility)
      if [ -f "$plist" ]; then
        echo "Found LaunchAgent: $plist"
        # Try to unload it (may fail if not loaded, which is OK)
        launchctl unload "$plist" 2>/dev/null || echo "  (LaunchAgent not loaded or already unloaded)"
        # Remove the plist file
        rm -f "$plist"
        echo "  ✓ Removed LaunchAgent"
      fi
    done
  done
fi

# Remove the app bundle
if [ -n "$APP_BUNDLE" ] && [ -d "$APP_BUNDLE" ]; then
  echo "Removing app bundle..."
  
  # Check if the app is in /Applications (system) which may require sudo
  if [[ "$APP_BUNDLE" == "/Applications/"* ]]; then
    echo "Warning: App is in system /Applications directory."
    echo "Attempting to remove without sudo first..."
    if rm -rf "$APP_BUNDLE" 2>/dev/null; then
      echo "✓ Removed $APP_BUNDLE"
    else
      echo "⚠ Could not remove app from /Applications without sudo."
      echo "To remove manually, run: sudo rm -rf \"$APP_BUNDLE\""
    fi
  else
    # App is in ~/Applications, safe to remove without sudo
    rm -rf "$APP_BUNDLE"
    echo "✓ Removed $APP_BUNDLE"
  fi
fi

# Clean up Homebrew's tracking
echo "Cleaning up Homebrew database..."
if brew list --cask "$APP_NAME" >/dev/null 2>&1; then
  # Try with --zap first (removes all app data), fall back to without if it fails
  if ! brew uninstall --cask --force --zap "$APP_NAME" 2>/dev/null; then
    # --zap might not be supported or might fail, try without it
    brew uninstall --cask --force "$APP_NAME" 2>/dev/null || {
      echo "Warning: Homebrew cleanup failed. The app may still be tracked by Homebrew."
      echo "You can try manually with: brew uninstall --cask --force $APP_NAME"
    }
  fi
fi

echo ""
echo "=========================================="
echo "✓ $APP_NAME uninstalled successfully"
echo "=========================================="
echo ""
echo "Note: This script removes the app and user-level components."
echo "If the app had system-level components (LaunchDaemons, kernel extensions, etc.),"
echo "those may still remain and would require sudo to remove."
UNINSTALLEOF

  chmod +x "$uninstall_script"
  echo "Created uninstall helper script: $uninstall_script"
}

# Function to install macOS applications via Homebrew Cask
install_macos_apps() {
  local apps_file="macos-apps.txt"
  
  if [ ! -f "$apps_file" ]; then
    echo "No $apps_file found. Skipping macOS app installation."
    echo "Create $apps_file with app names (one per line) to install GUI applications."
    return 0
  fi
  
  # Create user-local Applications directory
  mkdir -p "$HOME/Applications"
  
  # Set Homebrew Cask options for user-local installation
  export HOMEBREW_CASK_OPTS="--appdir=$HOME/Applications --no-quarantine"
  
  echo "Installing macOS applications from $apps_file..."
  echo "Applications will be installed to ~/Applications (user-local, no sudo required)"
  
  while IFS= read -r app || [ -n "$app" ]; do
    # Skip empty lines and comments
    [[ -z "$app" || "$app" =~ ^[[:space:]]*# ]] && continue
    
    # Strip inline comments and trim whitespace
    app=$(echo "$app" | sed 's/#.*//' | xargs)
    
    echo "Installing $app via Homebrew Cask..."
    
    # Check if app is already installed
    if brew list --cask "$app" >/dev/null 2>&1; then
      # App is tracked by Homebrew, but check if it's in the right location
      # Get the app display name to find the .app bundle
      app_display_name=$(brew info --cask "$app" 2>/dev/null | grep -E "^==> Name:" | sed 's/^==> Name: //' | head -1)
      if [ -z "$app_display_name" ]; then
        app_display_name="$app"
      fi
      
      # Check common app naming patterns in ~/Applications
      app_in_user_dir=false
      for pattern in "$app_display_name" "$(echo "$app_display_name" | sed 's/-/ /g')" "$(echo "$app" | sed 's/-/ /g')"; do
        if find "$HOME/Applications" -maxdepth 1 -iname "*${pattern}*.app" 2>/dev/null | grep -q .; then
          app_in_user_dir=true
          break
        fi
      done
      
      if [ "$app_in_user_dir" = true ]; then
        echo "$app is already installed in ~/Applications."
      else
        # App is installed but not in ~/Applications - likely in /Applications
        echo "$app is installed but not in ~/Applications. Reinstalling to user directory..."
        
        # First, uninstall without removing the app from /Applications (just Homebrew tracking)
        if brew uninstall --cask "$app" 2>/dev/null; then
          echo "Unlinked $app from Homebrew."
        else
          echo "Warning: Failed to unlink $app from Homebrew. Attempting fresh install..."
        fi
        
        # Now install to ~/Applications
        if brew install --cask "$app"; then
          echo "✓ $app reinstalled successfully to ~/Applications."
          echo "Note: The old version in /Applications should be removed manually if present."
        else
          echo "⚠ Failed to reinstall $app."
        fi
      fi
    else
      # App not installed, install it fresh
      if brew install --cask "$app"; then
        echo "✓ $app installed successfully."
      else
        echo "⚠ Failed to install $app."
      fi
    fi
  done < "$apps_file"
  
  echo ""
  echo "=========================================="
  echo "macOS app installation complete."
  echo "Applications are installed to ~/Applications"
  echo ""
  echo "Note: Some apps may require sudo to uninstall via Homebrew"
  echo "due to LaunchAgents or other system components."
  echo "For sudo-free uninstallation, see: ~/bin/uninstall-app.sh"
  echo "=========================================="
  
  # Create uninstall helper script
  create_uninstall_helper
}

# Function to install macOS App Store applications via mas
install_mas_apps() {
  local mas_file="mas-apps.txt"
  
  # Check if mas is installed
  if ! command -v mas >/dev/null 2>&1; then
    echo "Installing mas-cli for Mac App Store installations..."
    if brew install mas; then
      echo "mas-cli installed successfully."
    else
      echo "Failed to install mas-cli. Skipping App Store installations."
      return 1
    fi
  fi
  
  if [ ! -f "$mas_file" ]; then
    echo "No $mas_file found. Skipping Mac App Store app installation."
    echo "Create $mas_file with App Store IDs (one per line) to install apps."
    echo "Find IDs with: mas search 'App Name'"
    return 0
  fi
  
  echo "Installing Mac App Store applications from $mas_file..."
  
  while IFS= read -r app_id || [ -n "$app_id" ]; do
    # Skip empty lines and comments
    [[ -z "$app_id" || "$app_id" =~ ^[[:space:]]*# ]] && continue
    
    # Trim whitespace and extract just the ID
    app_id=$(echo "$app_id" | awk '{print $1}' | xargs)
    
    echo "Installing App Store app ID: $app_id..."
    if mas install "$app_id" 2>/dev/null; then
      echo "✓ App $app_id installed successfully."
    else
      echo "⚠ Failed to install app $app_id (may already be installed or require sign-in)."
    fi
  done < "$mas_file"
  
  echo "Mac App Store app installation complete."
}

# Function to install Linux packages via system package manager
install_linux_packages() {
  local packages_file="linux-packages.txt"
  
  if [ ! -f "$packages_file" ]; then
    echo "No $packages_file found. Skipping Linux package installation."
    echo "Create $packages_file with package names (one per line) to install additional packages."
    return 0
  fi
  
  echo "Installing Linux packages from $packages_file..."
  
  # Determine package manager
  local pkg_manager
  case "$OS_NAME" in
    ubuntu|debian)
      pkg_manager="apt"
      echo "Updating package list..."
      sudo apt update
      ;;
    fedora)
      pkg_manager="dnf"
      echo "Updating package list..."
      sudo dnf check-update || true
      ;;
    *)
      echo "Unsupported OS for Linux package installation: $OS_NAME"
      return 1
      ;;
  esac
  
  while IFS= read -r package || [ -n "$package" ]; do
    # Skip empty lines and comments
    [[ -z "$package" || "$package" =~ ^[[:space:]]*# ]] && continue
    
    # Strip inline comments and trim whitespace
    package=$(echo "$package" | sed 's/#.*//' | xargs)
    
    echo "Installing $package via $pkg_manager..."
    case "$pkg_manager" in
      apt)
        if sudo apt install -y "$package" 2>/dev/null; then
          echo "✓ $package installed successfully."
        else
          echo "⚠ Failed to install $package (may already be installed or not found in repositories)."
        fi
        ;;
      dnf)
        if sudo dnf install -y "$package" 2>/dev/null; then
          echo "✓ $package installed successfully."
        else
          echo "⚠ Failed to install $package (may already be installed or not found in repositories)."
        fi
        ;;
    esac
  done < "$packages_file"
  
  echo "Linux package installation complete."
}

# Function to install Flatpak applications
install_flatpak_apps() {
  local flatpak_file="flatpak-apps.txt"
  
  # Check if flatpak is installed
  if ! command -v flatpak >/dev/null 2>&1; then
    echo "Flatpak is not installed. Installing flatpak..."
    
    case "$OS_NAME" in
      ubuntu|debian)
        if sudo apt install -y flatpak; then
          echo "Flatpak installed successfully."
        else
          echo "Failed to install Flatpak. Skipping Flatpak app installations."
          return 1
        fi
        ;;
      fedora)
        if sudo dnf install -y flatpak; then
          echo "Flatpak installed successfully."
        else
          echo "Failed to install Flatpak. Skipping Flatpak app installations."
          return 1
        fi
        ;;
      *)
        echo "Cannot install Flatpak on $OS_NAME. Skipping Flatpak app installations."
        return 1
        ;;
    esac
  fi
  
  # Check if Flathub is configured
  if ! flatpak remotes | grep -q flathub; then
    echo "Adding Flathub repository..."
    if flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo; then
      echo "Flathub repository added successfully."
    else
      echo "Warning: Failed to add Flathub repository."
    fi
  fi
  
  if [ ! -f "$flatpak_file" ]; then
    echo "No $flatpak_file found. Skipping Flatpak app installation."
    echo "Create $flatpak_file with Flatpak app IDs (one per line) to install apps."
    echo "Find app IDs at https://flathub.org/"
    return 0
  fi
  
  echo "Installing Flatpak applications from $flatpak_file..."
  
  while IFS= read -r app_id || [ -n "$app_id" ]; do
    # Skip empty lines and comments
    [[ -z "$app_id" || "$app_id" =~ ^[[:space:]]*# ]] && continue
    
    # Strip inline comments and trim whitespace
    app_id=$(echo "$app_id" | sed 's/#.*//' | xargs)
    
    echo "Installing Flatpak app: $app_id..."
    if flatpak install -y flathub "$app_id" 2>/dev/null; then
      echo "✓ $app_id installed successfully."
    else
      echo "⚠ Failed to install $app_id (may already be installed or not found on Flathub)."
    fi
  done < "$flatpak_file"
  
  echo "Flatpak app installation complete."
}

# Function to install Tailscale on macOS
install_tailscale_macos() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale is already installed."
    return 0
  fi
  
  echo "Installing Tailscale via Homebrew Cask..."
  echo "Note: Tailscale installation requires sudo for the privileged helper."
  
  if brew install --cask tailscale; then
    echo "✓ Tailscale installed successfully."
    echo ""
    echo "=========================================="
    echo "Tailscale Setup"
    echo "=========================================="
    echo "To start using Tailscale:"
    echo "  1. Launch Tailscale from Applications"
    echo "  2. Sign in with your Tailscale account"
    echo "  3. Or run: open -a Tailscale"
    echo ""
    echo "For command-line usage:"
    echo "  sudo tailscale up    # Connect to your network"
    echo "  tailscale status     # Check connection status"
    echo "=========================================="
  else
    echo "⚠ Failed to install Tailscale."
    return 1
  fi
}

# Function to install Tailscale on Linux
install_tailscale_linux() {
  if command -v tailscale >/dev/null 2>&1; then
    echo "Tailscale is already installed."
    return 0
  fi
  
  echo "Installing Tailscale..."
  
  case "$OS_NAME" in
    ubuntu|debian)
      echo "Adding Tailscale repository..."
      
      # Detect distribution codename
      local DISTRO_CODENAME
      if [ -f /etc/os-release ]; then
        . /etc/os-release
        DISTRO_CODENAME="${VERSION_CODENAME}"
      fi
      
      # If we still don't have a codename, try lsb_release
      if [ -z "$DISTRO_CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
        DISTRO_CODENAME=$(lsb_release -cs)
      fi
      
      # Last resort: use OS_VERSION_CODENAME from os_detection.sh
      if [ -z "$DISTRO_CODENAME" ]; then
        DISTRO_CODENAME="${OS_VERSION_CODENAME:-jammy}"
      fi
      
      echo "Using distribution codename: $DISTRO_CODENAME"
      
      # Add Tailscale's GPG key and repository with error handling
      if ! curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${DISTRO_CODENAME}.noarmor.gpg" -o /tmp/tailscale-keyring.gpg; then
        echo "⚠ Failed to download Tailscale GPG key."
        return 1
      fi
      
      if ! sudo install -m 644 /tmp/tailscale-keyring.gpg /usr/share/keyrings/tailscale-archive-keyring.gpg; then
        echo "⚠ Failed to install Tailscale GPG key."
        rm -f /tmp/tailscale-keyring.gpg
        return 1
      fi
      rm -f /tmp/tailscale-keyring.gpg
      
      if ! curl -fsSL "https://pkgs.tailscale.com/stable/ubuntu/${DISTRO_CODENAME}.tailscale-keyring.list" -o /tmp/tailscale.list; then
        echo "⚠ Failed to download Tailscale repository list."
        return 1
      fi
      
      if ! sudo install -m 644 /tmp/tailscale.list /etc/apt/sources.list.d/tailscale.list; then
        echo "⚠ Failed to install Tailscale repository list."
        rm -f /tmp/tailscale.list
        return 1
      fi
      rm -f /tmp/tailscale.list
      
      sudo apt update
      if sudo apt install -y tailscale; then
        echo "✓ Tailscale installed successfully."
        echo ""
        echo "=========================================="
        echo "Tailscale Setup"
        echo "=========================================="
        echo "To start using Tailscale:"
        echo "  sudo tailscale up       # Connect to your network"
        echo "  sudo tailscale up --ssh # Connect with SSH enabled"
        echo "  tailscale status        # Check connection status"
        echo "=========================================="
      else
        echo "⚠ Failed to install Tailscale."
        return 1
      fi
      ;;
    fedora)
      echo "Adding Tailscale repository..."
      
      # Add Tailscale's Fedora repository with error handling
      if ! sudo dnf config-manager --add-repo https://pkgs.tailscale.com/stable/fedora/tailscale.repo; then
        echo "⚠ Failed to add Tailscale repository."
        return 1
      fi
      
      if sudo dnf install -y tailscale; then
        echo "✓ Tailscale installed successfully."
        
        # Enable and start the service
        if command -v systemctl >/dev/null 2>&1; then
          sudo systemctl enable --now tailscaled
        fi
        
        echo ""
        echo "=========================================="
        echo "Tailscale Setup"
        echo "=========================================="
        echo "To start using Tailscale:"
        echo "  sudo tailscale up       # Connect to your network"
        echo "  sudo tailscale up --ssh # Connect with SSH enabled"
        echo "  tailscale status        # Check connection status"
        echo "=========================================="
      else
        echo "⚠ Failed to install Tailscale."
        return 1
      fi
      ;;
    *)
      echo "Tailscale installation not supported for $OS_NAME."
      echo "Please visit https://tailscale.com/download for manual installation."
      return 1
      ;;
  esac
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
  
  # Detect OS and architecture
  local os_type arch_type binary_name
  
  case "$(uname -s)" in
    Darwin*)
      os_type="darwin"
      ;;
    Linux*)
      os_type="linux"
      ;;
    *)
      echo "Warning: Unsupported OS for bin installation. Please install manually from https://github.com/marcosnils/bin"
      return 1
      ;;
  esac
  
  case "$(uname -m)" in
    x86_64|amd64)
      arch_type="amd64"
      ;;
    arm64|aarch64)
      arch_type="arm64"
      ;;
    *)
      echo "Warning: Unsupported architecture for bin installation. Please install manually from https://github.com/marcosnils/bin"
      return 1
      ;;
  esac
  
  # Get latest release version by following the redirect from /releases/latest
  local latest_version
  latest_version=$(curl -sI https://github.com/marcosnils/bin/releases/latest | grep -i "^location:" | sed 's|.*/tag/||' | tr -d '\r\n')
  
  # Validate version format (should start with 'v' followed by digits)
  if [ -z "$latest_version" ] || ! echo "$latest_version" | grep -qE '^v[0-9]+\.[0-9]+'; then
    echo "Warning: Failed to get valid bin version. Please install manually from https://github.com/marcosnils/bin"
    return 1
  fi
  
  binary_name="bin_${latest_version#v}_${os_type}_${arch_type}"
  local download_url="https://github.com/marcosnils/bin/releases/download/${latest_version}/${binary_name}"
  
  echo "Downloading bin ${latest_version} for ${os_type}_${arch_type}..."
  
  # Download and install bin
  local temp_file
  temp_file=$(mktemp) || temp_file="$HOME/bin/bin.tmp"
  
  if curl -sSL "$download_url" -o "$temp_file"; then
    # Verify the downloaded file is an executable binary
    if ! file "$temp_file" | grep -qE "(executable|Mach-O)"; then
      echo "Warning: Downloaded file is not a valid executable. Installation failed."
      rm -f "$temp_file"
      return 1
    fi
    
    mv "$temp_file" "$HOME/bin/bin"
    chmod +x "$HOME/bin/bin"
    echo "bin installed successfully to ~/bin/"
    echo "Make sure ~/bin is in your PATH"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/bin:"* ]]; then
      echo 'export PATH="$HOME/bin:$PATH"' >> "$HOME/.bashrc"
      echo "Added ~/bin to PATH in .bashrc"
    fi
  else
    echo "Warning: Failed to install bin. Please install manually from https://github.com/marcosnils/bin"
    rm -f "$temp_file"
    return 1
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
  
  # Install additional Linux packages if requested
  if [ "$INSTALL_LINUX_PACKAGES" = true ]; then
    install_linux_packages
  fi
  
  # Install Flatpak apps if requested
  if [ "$INSTALL_FLATPAK_APPS" = true ]; then
    install_flatpak_apps
  fi
  
  # Install Tailscale if requested
  if [ "$INSTALL_TAILSCALE" = true ]; then
    install_tailscale_linux
  fi
elif [[ "$OS_NAME" == "fedora" ]]; then
  install_fedora
  # Install hypervisor agent for VMs
  install_hypervisor_agent
  if [ "$INSTALL_DOCKER" = true ]; then
    install_docker_linux
  fi
  
  # Install additional Linux packages if requested
  if [ "$INSTALL_LINUX_PACKAGES" = true ]; then
    install_linux_packages
  fi
  
  # Install Flatpak apps if requested
  if [ "$INSTALL_FLATPAK_APPS" = true ]; then
    install_flatpak_apps
  fi
  
  # Install Tailscale if requested
  if [ "$INSTALL_TAILSCALE" = true ]; then
    install_tailscale_linux
  fi
elif [[ "$OS_NAME" == "macos" ]]; then
  install_macos
  
  # Install macOS apps if requested
  if [ "$INSTALL_MACOS_APPS" = true ]; then
    install_macos_apps
  fi
  
  # Install Mac App Store apps if requested
  if [ "$INSTALL_MAS_APPS" = true ]; then
    install_mas_apps
  fi
  
  # On MacOS, recommend Docker Desktop
  if [ "$INSTALL_DOCKER" = true ]; then
    echo "Please install Docker Desktop from https://www.docker.com/products/docker-desktop/"
  fi
  
  # Install Tailscale if requested
  if [ "$INSTALL_TAILSCALE" = true ]; then
    install_tailscale_macos
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