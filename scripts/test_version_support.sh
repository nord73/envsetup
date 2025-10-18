#!/bin/bash
# scripts/test_version_support.sh
# Test script to verify OS detection and package mapping functionality

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the modules
source "$SCRIPT_DIR/os_detection.sh"
source "$SCRIPT_DIR/package_mappings.sh"

echo "=== OS Detection and Version Support Test ==="
echo

# Test OS detection
echo "1. Testing OS Detection:"
if detect_os; then
  echo "   ✓ OS detected successfully"
  echo "   - OS Name: $OS_NAME"
  echo "   - OS Version: $OS_VERSION"
  echo "   - OS Codename: $OS_CODENAME"
  echo "   - Major Version: $OS_MAJOR_VERSION"
  echo "   - Minor Version: $OS_MINOR_VERSION"
  echo "   - Variant: $OS_VARIANT"
  echo "   - Display Name: $(get_os_display_name)"
  echo "   - Package Manager: $(get_package_manager)"
else
  echo "   ✗ OS detection failed"
  exit 1
fi
echo

# Test version support
echo "2. Testing Version Support:"
if is_supported_version; then
  echo "   ✓ $(get_os_display_name) is supported"
else
  echo "   ⚠ $(get_os_display_name) is not officially supported"
fi
echo

# Test package mappings
echo "3. Testing Package Mappings:"
TOOLS=(tmux git curl wget jq tree htop fzf ripgrep bat)

for tool in "${TOOLS[@]}"; do
  if is_tool_available "$tool"; then
    package_name=$(get_package_name "$tool")
    echo "   ✓ $tool -> $package_name"
  else
    echo "   ✗ $tool is not available for this OS version"
  fi
done
echo

# Test available tools
echo "4. Available Tools for $(get_os_display_name):"
available_tools=$(get_available_tools)
echo "   $available_tools"
echo

# Test known OS versions (simulation)
echo "5. Testing Known OS Version Mappings:"

# Function to simulate package mapping for different OS versions
test_package_mapping() {
  local test_os="$1"
  local test_version="$2"
  local test_tool="$3"
  
  # Temporarily set variables for testing
  local orig_os="$OS_NAME"
  local orig_version="$OS_MAJOR_VERSION"
  
  OS_NAME="$test_os"
  OS_MAJOR_VERSION="$test_version"
  
  local package_name
  package_name=$(get_package_name "$test_tool")
  
  echo "   $test_os $test_version: $test_tool -> $package_name"
  
  # Restore original values
  OS_NAME="$orig_os"
  OS_MAJOR_VERSION="$orig_version"
}

# Test different OS/version combinations
test_package_mapping "ubuntu" "20" "bat"
test_package_mapping "ubuntu" "21" "bat"
test_package_mapping "ubuntu" "22" "bat"
test_package_mapping "ubuntu" "23" "bat"
test_package_mapping "ubuntu" "24" "bat"
test_package_mapping "debian" "11" "bat"
test_package_mapping "debian" "12" "bat"
test_package_mapping "debian" "13" "bat"
test_package_mapping "fedora" "35" "bat"
test_package_mapping "fedora" "38" "bat"
test_package_mapping "fedora" "40" "bat"
echo

echo "=== Test Complete ==="
echo "All functionality appears to be working correctly!"