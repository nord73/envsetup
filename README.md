# envsetup

A minimal, user-local environment setup toolkit for new computers, users, VMs, and remote VPS with **multi-version support** for Ubuntu, Debian, and macOS.
This repo helps bootstrap a clean development environment with essential tools, dotfiles, and language runtimes, avoiding unnecessary system-wide installations.

## Supported Operating Systems

### Ubuntu
- **Ubuntu 20.04+** (Focal and later)
- **Ubuntu 22.04+** (Jammy and later) 
- **Ubuntu 24.04+** (Noble and later)

### Debian
- **Debian 11+** (Bullseye and later)
- **Debian 12** (Bookworm)
- **Debian 13** (Trixie)

### macOS
- **macOS 10.15+** (Catalina and later)

The toolkit automatically detects your OS version and adapts package installation accordingly, handling version-specific differences like package names and repository configurations.

---

## Features

- **Bootstrap scripts** for verifying and installing essential tools.
- **Dotfiles management** for shell and editor configuration.
- **User-local installs** (no global contamination).
- **Optional language runtimes** (Python, Node.js, Go).
- **Extensible tool list** for easy customization.

---

## Quick Start

### 1. Clone the repo

```bash
git clone https://github.com/yourusername/envsetup.git
cd envsetup
```

### 2. Run the bootstrap script

```bash
bash scripts/bootstrap.sh
```

This will:
- Verify essential tools (`git`, `curl`, `wget`, `tree`, etc.)
- Install missing tools using `apt` (Linux) or `brew` (MacOS)
- Set up user directories (`~/bin`, `~/src`)
- Optionally install Homebrew (on MacOS)
- Symlink dotfiles

---

## Scripts

- `scripts/bootstrap.sh`  
  Main setup script for verifying and installing essential tools with multi-version OS support.

- `scripts/os_detection.sh`  
  OS and version detection utilities. Detects Ubuntu, Debian, and macOS versions.

- `scripts/package_mappings.sh`  
  Package name mappings for different OS versions. Handles version-specific package differences.

- `scripts/test_version_support.sh`  
  Test script to verify OS detection and package mapping functionality.

---

## Customization

### Adding New OS Versions

To add support for new Ubuntu or Debian versions:

1. **Update `scripts/package_mappings.sh`**:
   - Add new package mapping arrays (e.g., `UBUNTU_26_PACKAGES`)
   - Update the `get_package_name()` function to handle the new version
   - Add version-specific package name differences

2. **Update `scripts/os_detection.sh`**:
   - Modify `is_supported_version()` to include the new version range

3. **Test the changes**:
   ```bash
   bash scripts/test_version_support.sh
   ```

### Adding New Tools

- Add tools to the `TOOLS` array in `scripts/bootstrap.sh`
- Update package mapping arrays in `scripts/package_mappings.sh` for each supported OS version
- Handle any version-specific installation differences

### Custom Dotfiles

- Place your dotfiles in the `dotfiles/` directory
- The bootstrap script will automatically symlink them to your home directory

### Example: Adding Support for Ubuntu 26.04

```bash
# In scripts/package_mappings.sh
declare -A UBUNTU_26_PACKAGES=(
  ["git"]="git"
  ["curl"]="curl"
  # ... other tools
  ["new-tool"]="new-package-name"
)

# Update get_package_name() function
case "$OS_MAJOR_VERSION" in
  20) eval "package_name=\${UBUNTU_20_PACKAGES[\"$tool\"]}" ;;
  22) eval "package_name=\${UBUNTU_22_PACKAGES[\"$tool\"]}" ;;
  24) eval "package_name=\${UBUNTU_24_PACKAGES[\"$tool\"]}" ;;
  26|*) eval "package_name=\${UBUNTU_26_PACKAGES[\"$tool\"]}" ;;
esac
```

---

---

## Version Compatibility Matrix

| Tool | Ubuntu 20.04 | Ubuntu 22.04 | Ubuntu 24.04+ | Debian 11 | Debian 12+ | macOS |
|------|-------------|-------------|---------------|-----------|------------|-------|
| git | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| curl | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| wget | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| tree | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| htop | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| fzf | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| ripgrep | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |
| bat | ✓ | ✓ | ✓ | ✓ (as batcat) | ✓ | ✓ |
| jq | ✓ | ✓ | ✓ | ✓ | ✓ | ✓ |

**Note**: The toolkit automatically handles package name differences (e.g., `bat` vs `batcat` in Debian 11) and creates appropriate aliases when needed.

## License

MIT
