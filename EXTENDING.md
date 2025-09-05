# Example: Adding Support for New OS Versions
# This file demonstrates how to extend envsetup for future versions

## Adding Ubuntu 26.04 Support

### 1. Update package_mappings.sh

Add a new package mapping array:

```bash
declare -A UBUNTU_26_PACKAGES=(
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["tree"]="tree"
  ["htop"]="htop"
  ["fzf"]="fzf"
  ["ripgrep"]="ripgrep"
  ["bat"]="bat"
  ["jq"]="jq"
  # Add new tools here
  ["new-tool"]="new-package-name"
)
```

Update the get_package_name() function:

```bash
case "$OS_MAJOR_VERSION" in
  20) eval "package_name=\${UBUNTU_20_PACKAGES[\"$tool\"]}" ;;
  22) eval "package_name=\${UBUNTU_22_PACKAGES[\"$tool\"]}" ;;
  24) eval "package_name=\${UBUNTU_24_PACKAGES[\"$tool\"]}" ;;
  26|*) eval "package_name=\${UBUNTU_26_PACKAGES[\"$tool\"]}" ;;
esac
```

### 2. Update os_detection.sh (if needed)

If version support range changes:

```bash
is_supported_version() {
  case "$OS_NAME" in
    ubuntu)
      # Support Ubuntu 20.04+ (including 26.04+)
      if [ "$OS_MAJOR_VERSION" -ge 20 ]; then
        return 0
      fi
      ;;
    # ... other cases
  esac
  return 1
}
```

### 3. Test Changes

```bash
bash scripts/test_version_support.sh
```

## Adding Support for New Tools

### 1. Add to TOOLS array in bootstrap.sh:

```bash
TOOLS=(git curl wget tree htop fzf ripgrep bat jq newtool)
```

### 2. Add to all package mapping arrays:

```bash
# For each OS version array, add:
["newtool"]="actual-package-name"
```

### 3. Handle special cases if needed:

```bash
# In bootstrap.sh install_linux() function, add special handling:
if [ "$OS_NAME" = "debian" ] && [ "$OS_MAJOR_VERSION" = "11" ]; then
  # Handle special package naming for this version
  if command -v actualcommand >/dev/null 2>&1 && ! command -v newtool >/dev/null 2>&1; then
    echo "Creating newtool alias..."
    ln -sf "$(which actualcommand)" "$HOME/bin/newtool"
  fi
fi
```

## Future Considerations

1. **Package availability**: New OS versions may introduce or remove packages
2. **Repository changes**: Package sources may change between versions
3. **Dependency requirements**: New tools may have different dependencies
4. **Installation methods**: Some tools may require different installation approaches

## Testing Matrix

When adding new versions, test:
- Package installation
- Tool availability  
- Special cases (aliases, symlinks)
- Docker installation (if applicable)
- Error handling for missing packages