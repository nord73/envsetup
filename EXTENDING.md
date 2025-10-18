# Extending envsetup
# This file demonstrates how to extend envsetup for new OS versions, scenarios, and tools

## Adding Support for New Operating Systems

### Adding a New OS Distribution (e.g., Rocky Linux)

#### 1. Update os_detection.sh

Add detection logic:

```bash
detect_os() {
  # ... existing code ...
  elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
    if [ -f /etc/os-release ]; then
      . /etc/os-release
      OS_NAME=$(echo "$ID" | tr '[:upper:]' '[:lower:]')
      # ... detection continues
    fi
  fi
}

# Add to is_supported_version():
is_supported_version() {
  case "$OS_NAME" in
    # ... existing cases ...
    rocky)
      if [ "$OS_MAJOR_VERSION" -ge 8 ]; then
        return 0
      fi
      ;;
  esac
}

# Add to get_package_manager():
get_package_manager() {
  case "$OS_NAME" in
    # ... existing cases ...
    rocky)
      echo "dnf"
      ;;
  esac
}
```

#### 2. Update package_mappings.sh

Add package mappings:

```bash
declare -A ROCKY_PACKAGES=(
  ["tmux"]="tmux"
  ["git"]="git"
  ["curl"]="curl"
  ["wget"]="wget"
  ["jq"]="jq"
  # ... other tools
)

# Update get_package_name():
get_package_name() {
  case "$OS_NAME" in
    # ... existing cases ...
    rocky)
      eval "package_name=\${ROCKY_PACKAGES[\"$tool\"]}"
      ;;
  esac
}
```

#### 3. Update bootstrap.sh

Add installer function if needed:

```bash
# If using dnf (similar to Fedora), reuse install_fedora
# Otherwise create new installer:
install_rocky() {
  echo "Updating package list..."
  sudo dnf check-update || true
  
  # ... similar to install_fedora
}

# Update main installer logic:
echo "Running installer for $(get_os_display_name)..."
if [[ "$OS_NAME" == "rocky" ]]; then
  install_rocky
  # ...
fi
```

## Adding New Installation Scenarios

### Example: Adding "CI Runner" Scenario

#### In bootstrap.sh:

```bash
case "$INSTALL_SCENARIO" in
  # ... existing scenarios ...
  ci-runner)
    TOOLS=(${BASE_TOOLS[@]} docker buildah podman)
    ;;
esac
```

### Example: Adding "Data Science" Scenario

```bash
case "$INSTALL_SCENARIO" in
  # ... existing scenarios ...
  data-science)
    TOOLS=(${BASE_TOOLS[@]} tree htop fzf ripgrep bat python3 python3-pip jupyter)
    ;;
esac
```

## Adding Support for New Tools

### 1. Add to appropriate tool list in bootstrap.sh

```bash
BASE_TOOLS=(tmux git curl wget jq newtool)  # For all scenarios

# OR for specific scenarios:
case "$INSTALL_SCENARIO" in
  developer-desktop)
    TOOLS=(${BASE_TOOLS[@]} tree htop fzf ripgrep bat newtool)
    ;;
esac
```

### 2. Add to all package mapping arrays in package_mappings.sh

```bash
declare -A UBUNTU_PACKAGES=(
  # ... existing tools ...
  ["newtool"]="newtool-package"
)

declare -A DEBIAN_PACKAGES=(
  # ... existing tools ...
  ["newtool"]="newtool-package"
)

declare -A FEDORA_PACKAGES=(
  # ... existing tools ...
  ["newtool"]="newtool"
)
```

### 3. Handle special cases if needed

```bash
# In bootstrap.sh, after tool installation:
# Handle special cases for package naming differences
if [ "$OS_NAME" = "debian" ] && [ "$OS_MAJOR_VERSION" = "11" ]; then
  if command -v newtool-actual >/dev/null 2>&1 && ! command -v newtool >/dev/null 2>&1; then
    echo "Creating newtool alias..."
    mkdir -p "$HOME/bin"
    ln -sf "$(which newtool-actual)" "$HOME/bin/newtool"
  fi
fi
```

## Adding Ubuntu Interim Release Support

Ubuntu interim releases (20.10, 21.10, 22.10, etc.) are **automatically supported** through the generic `UBUNTU_PACKAGES` mapping. Only add version-specific mappings if package names differ:

```bash
# Only needed if package names are different in this version
declare -A UBUNTU_23_PACKAGES=(
  ["special-tool"]="different-package-name"
)

# Update get_package_name() only if needed:
if [ "$OS_MAJOR_VERSION" = "23" ]; then
  eval "package_name=\${UBUNTU_23_PACKAGES[\"$tool\"]}"
fi
```

## Future Considerations

1. **Package availability**: New OS versions may introduce or remove packages
2. **Repository changes**: Package sources may change between versions  
3. **Dependency requirements**: New tools may have different dependencies
4. **Installation methods**: Some tools may require different installation approaches
5. **OS variants**: Desktop vs Server vs Minimal installations may have different base packages
6. **Interim releases**: Ubuntu .10 releases may have different package availability than LTS

## Testing New Extensions

### Testing Matrix

When adding new versions or tools, test:
- [ ] Package installation on target OS
- [ ] Tool availability and functionality
- [ ] Special cases (aliases, symlinks)
- [ ] Docker installation (if applicable)
- [ ] Error handling for missing packages
- [ ] All installation scenarios
- [ ] OS variant detection

### Manual Testing

```bash
# Test OS detection
bash scripts/test_version_support.sh

# Test package installation for each scenario
bash scripts/bootstrap.sh --scenario=developer-desktop
bash scripts/bootstrap.sh --scenario=clean-desktop
bash scripts/bootstrap.sh --scenario=development-server
bash scripts/bootstrap.sh --scenario=production-server

# Test with optional components
bash scripts/bootstrap.sh --docker --bin
```

### Automated Testing

Create test cases in `scripts/test_version_support.sh` for new functionality:

```bash
# Test new OS detection
test_rocky_detection() {
  # Mock /etc/os-release for Rocky Linux
  # Verify detection works correctly
}

# Test new scenario
test_ci_runner_scenario() {
  # Verify correct tools are selected
}
```

## Common Patterns

### Package Name Variations

When a tool has different package names across distributions:

```bash
# In package_mappings.sh
declare -A UBUNTU_PACKAGES=(["tool"]="ubuntu-package-name")
declare -A FEDORA_PACKAGES=(["tool"]="fedora-package-name")
declare -A DEBIAN_11_PACKAGES=(["tool"]="debian11-package-name")
```

### Post-Installation Configuration

When a tool needs special setup after installation:

```bash
# In bootstrap.sh, after tool installation loop
if command -v tool >/dev/null 2>&1; then
  echo "Configuring tool..."
  # Run configuration commands
fi
```

### Custom Installation Sources

For tools not in standard repos:

```bash
install_custom_tool() {
  echo "Installing custom-tool from source..."
  
  case "$OS_NAME" in
    ubuntu|debian)
      # Add PPA or download .deb
      ;;
    fedora)
      # Add COPR or download .rpm
      ;;
  esac
}
```