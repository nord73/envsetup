#!/bin/bash
# scripts/package_mappings.sh
# Package name mappings for different OS versions
#
# NOTE: This script is compatible with Bash 3.2+ (including macOS default Bash)
# It uses functions with case statements instead of associative arrays

# Source OS detection if not already loaded
if [ -z "$OS_NAME" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/os_detection.sh"
  detect_os
fi

# Package mapping functions using case statements (Bash 3.2 compatible)
# These replace the associative arrays that require Bash 4+

# Get package name for Ubuntu (generic, works for all versions 20.04+)
_get_ubuntu_package() {
  local tool="$1"
  case "$tool" in
    tmux) echo "tmux" ;;
    git) echo "git" ;;
    curl) echo "curl" ;;
    wget) echo "wget" ;;
    jq) echo "jq" ;;
    tree) echo "tree" ;;
    htop) echo "htop" ;;
    fzf) echo "fzf" ;;
    ripgrep) echo "ripgrep" ;;
    bat) echo "bat" ;;
    *) echo "" ;;
  esac
}

# Get package name for Ubuntu 20.04 (same as generic for now)
_get_ubuntu_20_package() {
  local tool="$1"
  _get_ubuntu_package "$tool"
}

# Get package name for Debian 11 (Bullseye has different bat package name)
_get_debian_11_package() {
  local tool="$1"
  case "$tool" in
    tmux) echo "tmux" ;;
    git) echo "git" ;;
    curl) echo "curl" ;;
    wget) echo "wget" ;;
    jq) echo "jq" ;;
    tree) echo "tree" ;;
    htop) echo "htop" ;;
    fzf) echo "fzf" ;;
    ripgrep) echo "ripgrep" ;;
    bat) echo "batcat" ;;  # Different package name in Debian 11
    *) echo "" ;;
  esac
}

# Get package name for Debian 12+ (Bookworm and later)
_get_debian_package() {
  local tool="$1"
  case "$tool" in
    tmux) echo "tmux" ;;
    git) echo "git" ;;
    curl) echo "curl" ;;
    wget) echo "wget" ;;
    jq) echo "jq" ;;
    tree) echo "tree" ;;
    htop) echo "htop" ;;
    fzf) echo "fzf" ;;
    ripgrep) echo "ripgrep" ;;
    bat) echo "bat" ;;
    *) echo "" ;;
  esac
}

# Get package name for Fedora
_get_fedora_package() {
  local tool="$1"
  case "$tool" in
    tmux) echo "tmux" ;;
    git) echo "git" ;;
    curl) echo "curl" ;;
    wget) echo "wget" ;;
    jq) echo "jq" ;;
    tree) echo "tree" ;;
    htop) echo "htop" ;;
    fzf) echo "fzf" ;;
    ripgrep) echo "ripgrep" ;;
    bat) echo "bat" ;;
    *) echo "" ;;
  esac
}

# Get package name for macOS (Homebrew)
_get_macos_package() {
  local tool="$1"
  case "$tool" in
    git) echo "git" ;;
    curl) echo "curl" ;;
    wget) echo "wget" ;;
    tree) echo "tree" ;;
    htop) echo "htop" ;;
    fzf) echo "fzf" ;;
    ripgrep) echo "ripgrep" ;;
    bat) echo "bat" ;;
    jq) echo "jq" ;;
    *) echo "" ;;
  esac
}

# Get all available tools for a given OS
_get_available_tools_list() {
  local os_name="$1"
  local os_version="$2"
  
  case "$os_name" in
    ubuntu)
      # All Ubuntu versions support the same tools
      echo "tmux git curl wget jq tree htop fzf ripgrep bat"
      ;;
    debian)
      # All Debian versions support the same tools
      echo "tmux git curl wget jq tree htop fzf ripgrep bat"
      ;;
    fedora)
      echo "tmux git curl wget jq tree htop fzf ripgrep bat"
      ;;
    macos)
      echo "git curl wget tree htop fzf ripgrep bat jq"
      ;;
    *)
      echo ""
      ;;
  esac
}

# Get hypervisor agent package for Ubuntu/Debian
_get_hypervisor_agent_ubuntu_debian() {
  local hypervisor="$1"
  case "$hypervisor" in
    vmware) echo "open-vm-tools" ;;
    virtualbox) echo "virtualbox-guest-utils" ;;
    hyperv) echo "hyperv-daemons" ;;
    kvm) echo "qemu-guest-agent" ;;
    qemu) echo "qemu-guest-agent" ;;
    xen) echo "xen-guest-agent" ;;
    *) echo "" ;;
  esac
}

# Get hypervisor agent package for Fedora
_get_hypervisor_agent_fedora() {
  local hypervisor="$1"
  case "$hypervisor" in
    vmware) echo "open-vm-tools" ;;
    virtualbox) echo "virtualbox-guest-additions" ;;
    hyperv) echo "hyperv-daemons" ;;
    kvm) echo "qemu-guest-agent" ;;
    qemu) echo "qemu-guest-agent" ;;
    xen) echo "xen-guest-agent" ;;
    *) echo "" ;;
  esac
}

# Get the actual package name for a tool on the current OS
get_package_name() {
  local tool="$1"
  local package_name=""
  
  case "$OS_NAME" in
    ubuntu)
      # For Ubuntu 20.x, use specific mappings if available, otherwise use generic
      if [ "$OS_MAJOR_VERSION" = "20" ]; then
        package_name=$(_get_ubuntu_20_package "$tool")
      fi
      # If not found or for other versions, use generic Ubuntu mappings
      if [ -z "$package_name" ]; then
        package_name=$(_get_ubuntu_package "$tool")
      fi
      ;;
    debian)
      # Debian 11 has special package names
      if [ "$OS_MAJOR_VERSION" = "11" ]; then
        package_name=$(_get_debian_11_package "$tool")
      else
        # Debian 12+ uses generic mappings
        package_name=$(_get_debian_package "$tool")
      fi
      ;;
    fedora)
      package_name=$(_get_fedora_package "$tool")
      ;;
    macos)
      package_name=$(_get_macos_package "$tool")
      ;;
  esac
  
  # Fallback to the tool name itself if no mapping found
  if [ -z "$package_name" ]; then
    package_name="$tool"
  fi
  
  echo "$package_name"
}

# Get all available tools for the current OS version
get_available_tools() {
  _get_available_tools_list "$OS_NAME" "$OS_MAJOR_VERSION"
}

# Check if a tool is available for the current OS version
is_tool_available() {
  local tool="$1"
  local available_tools
  available_tools=$(get_available_tools)
  
  for available_tool in $available_tools; do
    if [ "$available_tool" = "$tool" ]; then
      return 0
    fi
  done
  return 1
}

# Get hypervisor agent package name for current OS and hypervisor
get_hypervisor_agent_package() {
  local hypervisor="$1"
  local package_name=""
  
  case "$OS_NAME" in
    ubuntu|debian)
      package_name=$(_get_hypervisor_agent_ubuntu_debian "$hypervisor")
      ;;
    fedora)
      package_name=$(_get_hypervisor_agent_fedora "$hypervisor")
      ;;
  esac
  
  echo "$package_name"
}