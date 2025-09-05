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

# Ubuntu package mappings
declare -A UBUNTU_20_PACKAGES=(
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

declare -A UBUNTU_22_PACKAGES=(
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

declare -A UBUNTU_24_PACKAGES=(
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

# Debian package mappings
declare -A DEBIAN_11_PACKAGES=(
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="batcat"  # Different package name in older Debian
  ["jq"]="jq"
)

declare -A DEBIAN_12_PACKAGES=(
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

declare -A DEBIAN_13_PACKAGES=(
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
      case "$OS_MAJOR_VERSION" in
        20)
          eval "package_name=\${UBUNTU_20_PACKAGES[\"$tool\"]}"
          ;;
        22)
          eval "package_name=\${UBUNTU_22_PACKAGES[\"$tool\"]}"
          ;;
        24|*)
          eval "package_name=\${UBUNTU_24_PACKAGES[\"$tool\"]}"
          ;;
      esac
      ;;
    debian)
      case "$OS_MAJOR_VERSION" in
        11)
          eval "package_name=\${DEBIAN_11_PACKAGES[\"$tool\"]}"
          ;;
        12)
          eval "package_name=\${DEBIAN_12_PACKAGES[\"$tool\"]}"
          ;;
        13|*)
          eval "package_name=\${DEBIAN_13_PACKAGES[\"$tool\"]}"
          ;;
      esac
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
      case "$OS_MAJOR_VERSION" in
        20)
          echo "${!UBUNTU_20_PACKAGES[@]}"
          ;;
        22)
          echo "${!UBUNTU_22_PACKAGES[@]}"
          ;;
        24|*)
          echo "${!UBUNTU_24_PACKAGES[@]}"
          ;;
      esac
      ;;
    debian)
      case "$OS_MAJOR_VERSION" in
        11)
          echo "${!DEBIAN_11_PACKAGES[@]}"
          ;;
        12)
          echo "${!DEBIAN_12_PACKAGES[@]}"
          ;;
        13|*)
          echo "${!DEBIAN_13_PACKAGES[@]}"
          ;;
      esac
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