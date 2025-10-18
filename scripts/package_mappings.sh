#!/bin/bash
# scripts/package_mappings.sh
# Package name mappings for different OS versions

# Source OS detection if not already loaded
if [ -z "$OS_NAME" ]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  source "$SCRIPT_DIR/os_detection.sh"
  detect_os
fi

# Define package mappings for different OS versions
# Format: declare -A OS_VERSION_PACKAGES=(["package_alias"]="actual_package_name")

# Ubuntu package mappings (works for all versions 20.04+, including .10 releases)
# Most packages have consistent names across Ubuntu versions
declare -A UBUNTU_PACKAGES=(
  ["tmux"]="tmux"
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["jq"]="jq"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="bat"
)

# Ubuntu 20.04 specific packages (override if needed)
declare -A UBUNTU_20_PACKAGES=(
  ["tmux"]="tmux"
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["jq"]="jq"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="bat"
)

# Debian 11 package mappings (Bullseye has different bat package name)
declare -A DEBIAN_11_PACKAGES=(
  ["tmux"]="tmux"
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["jq"]="jq"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="batcat"  # Different package name in Debian 11
)

# Debian 12+ package mappings
declare -A DEBIAN_PACKAGES=(
  ["tmux"]="tmux"
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["jq"]="jq"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="bat"
)

# Fedora package mappings
declare -A FEDORA_PACKAGES=(
  ["tmux"]="tmux"
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["jq"]="jq"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="bat"
)

# macOS package mappings (Homebrew)
declare -A MACOS_PACKAGES=(
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="bat"
  ["jq"]="jq"
)

# Get the actual package name for a tool on the current OS
get_package_name() {
  local tool="$1"
  local package_name=""
  
  case "$OS_NAME" in
    ubuntu)
      # For Ubuntu 20.x, use specific mappings if available, otherwise use generic
      if [ "$OS_MAJOR_VERSION" = "20" ]; then
        eval "package_name=\${UBUNTU_20_PACKAGES[\"$tool\"]}"
      fi
      # If not found or for other versions, use generic Ubuntu mappings
      if [ -z "$package_name" ]; then
        eval "package_name=\${UBUNTU_PACKAGES[\"$tool\"]}"
      fi
      ;;
    debian)
      # Debian 11 has special package names
      if [ "$OS_MAJOR_VERSION" = "11" ]; then
        eval "package_name=\${DEBIAN_11_PACKAGES[\"$tool\"]}"
      else
        # Debian 12+ uses generic mappings
        eval "package_name=\${DEBIAN_PACKAGES[\"$tool\"]}"
      fi
      ;;
    fedora)
      eval "package_name=\${FEDORA_PACKAGES[\"$tool\"]}"
      ;;
    macos)
      eval "package_name=\${MACOS_PACKAGES[\"$tool\"]}"
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
  case "$OS_NAME" in
    ubuntu)
      if [ "$OS_MAJOR_VERSION" = "20" ]; then
        echo "${!UBUNTU_20_PACKAGES[@]}"
      else
        echo "${!UBUNTU_PACKAGES[@]}"
      fi
      ;;
    debian)
      if [ "$OS_MAJOR_VERSION" = "11" ]; then
        echo "${!DEBIAN_11_PACKAGES[@]}"
      else
        echo "${!DEBIAN_PACKAGES[@]}"
      fi
      ;;
    fedora)
      echo "${!FEDORA_PACKAGES[@]}"
      ;;
    macos)
      echo "${!MACOS_PACKAGES[@]}"
      ;;
  esac
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