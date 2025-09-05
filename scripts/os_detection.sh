#!/bin/bash
# scripts/os_detection.sh
# OS and version detection utilities for envsetup

# Global variables for OS information
OS_NAME=""
OS_VERSION=""
OS_CODENAME=""
OS_MAJOR_VERSION=""

# Detect OS distribution and version
detect_os() {
  if [[ "$OSTYPE" == "darwin"* ]]; then
    OS_NAME="macos"
    OS_VERSION=$(sw_vers -productVersion)
    OS_MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d. -f1)
    OS_CODENAME="macos"
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/os-release ]; then
      # Source the os-release file to get distribution info
      . /etc/os-release
      OS_NAME=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
      OS_VERSION="$VERSION_ID"
      OS_CODENAME="$VERSION_CODENAME"
      
      # Extract major version
      OS_MAJOR_VERSION=$(echo "$OS_VERSION" | cut -d. -f1)
      
      # Handle cases where VERSION_CODENAME might not be set
      if [ -z "$OS_CODENAME" ] && command -v lsb_release >/dev/null 2>&1; then
        OS_CODENAME=$(lsb_release -cs 2>/dev/null)
      fi
    else
      echo "Warning: Cannot detect Linux distribution"
      return 1
    fi
  else
    echo "Unsupported OS: $OSTYPE"
    return 1
  fi
  
  return 0
}

# Check if OS version is supported
is_supported_version() {
  case "$OS_NAME" in
    ubuntu)
      # Support Ubuntu 20.04+ (including 24.04+)
      if [ "$OS_MAJOR_VERSION" -ge 20 ]; then
        return 0
      fi
      ;;
    debian)
      # Support Debian 11+ (bullseye+, including bookworm=12, trixie=13)
      if [ "$OS_MAJOR_VERSION" -ge 11 ]; then
        return 0
      fi
      ;;
    macos)
      # Support macOS 10.15+ (Catalina and later)
      if [ "$OS_MAJOR_VERSION" -ge 10 ]; then
        return 0
      fi
      ;;
  esac
  return 1
}

# Get display name for OS version
get_os_display_name() {
  case "$OS_NAME" in
    ubuntu)
      echo "Ubuntu $OS_VERSION ($OS_CODENAME)"
      ;;
    debian)
      echo "Debian $OS_VERSION ($OS_CODENAME)"
      ;;
    macos)
      echo "macOS $OS_VERSION"
      ;;
    *)
      echo "Unknown OS"
      ;;
  esac
}

# Get package manager for the current OS
get_package_manager() {
  case "$OS_NAME" in
    ubuntu|debian)
      echo "apt"
      ;;
    macos)
      echo "brew"
      ;;
    *)
      echo "unknown"
      ;;
  esac
}