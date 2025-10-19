# envsetup

A minimal, user-local environment setup toolkit for new computers, users, VMs, and remote VPS with **multi-version support** for Ubuntu, Debian, Fedora, and macOS.
This repo helps bootstrap a clean development environment with essential tools, dotfiles, and language runtimes, avoiding unnecessary system-wide installations.

## Supported Operating Systems

### Ubuntu
- **Ubuntu 20.04+** (Focal and later)
- **Ubuntu 20.10, 21.10, 22.10, 23.10, etc.** (Interim releases)
- **Ubuntu 22.04+** (Jammy and later) 
- **Ubuntu 24.04+** (Noble and later)
- Supports Desktop, Server, and Minimal variants

### Debian
- **Debian 11+** (Bullseye and later)
- **Debian 12** (Bookworm)
- **Debian 13** (Trixie)

### Fedora
- **Fedora 35+** (recent versions)
- Supports Workstation and Server variants

### macOS
- **macOS 10.15+** (Catalina and later)
- **Homebrew support**: User-local installation to `~/.brew` (non-root)
- **Package installation**: Command-line tools via Homebrew
- **App installation**: GUI applications via Homebrew Cask and Mac App Store (mas-cli)

The toolkit automatically detects your OS version and variant, adapting package installation accordingly. It handles version-specific differences like package names and repository configurations.

---

## Features

- **Bootstrap scripts** for verifying and installing essential tools.
- **Multi-scenario support** for different installation types (developer desktop, clean desktop, development server, production server, docker host).
- **Automatic hypervisor detection** for virtual machines with guest agent installation (VMware, VirtualBox, Hyper-V, KVM/QEMU, Xen).
- **Dotfiles management** for shell and editor configuration.
- **User-local installs** (no global contamination).
- **Optional Docker CE installation** for containerized workflows.
- **Support for marcosnils/bin** for clean binary installations.
- **Extensible tool list** for easy customization.
- **ZFS-on-root installer** for Debian 13 with advanced features.

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
- Verify essential tools (`tmux`, `git`, `curl`, `wget`, `jq`, etc.)
- Install missing tools using `apt` (Ubuntu/Debian), `dnf` (Fedora), or `brew` (macOS)
- Set up user directories (`~/bin`, `~/src`)
- Optionally install Homebrew (on macOS)
- Symlink dotfiles

### Installation Scenarios

The bootstrap script supports different installation scenarios to match your needs:

```bash
# Developer desktop (default) - full set of development tools
bash scripts/bootstrap.sh --scenario=developer-desktop

# Clean desktop - minimal base packages only
bash scripts/bootstrap.sh --scenario=clean-desktop

# Development server - server + development tools
bash scripts/bootstrap.sh --scenario=development-server

# Production server - minimal packages for production use
bash scripts/bootstrap.sh --scenario=production-server

# Docker host - dedicated container host with Docker CE
bash scripts/bootstrap.sh --scenario=docker-host
```

### Optional Components

```bash
# Install Docker CE
bash scripts/bootstrap.sh --docker

# Install marcosnils/bin tool for binary management
bash scripts/bootstrap.sh --bin

# Combine options
bash scripts/bootstrap.sh --scenario=development-server --docker --bin
```

---

## Scripts

- `scripts/bootstrap.sh`  
  Main setup script for verifying and installing essential tools with multi-version OS support and installation scenarios.

- `scripts/os_detection.sh`  
  OS and version detection utilities. Detects Ubuntu, Debian, Fedora, and macOS versions, including OS variants (Desktop, Server, Minimal, Workstation).

- `scripts/package_mappings.sh`  
  Package name mappings for different OS versions. Handles version-specific package differences.

- `scripts/test_version_support.sh`  
  Test script to verify OS detection and package mapping functionality.

---

## Installation Scenarios

### Developer Desktop
Best for: Local development workstations

**Includes:**
- Base packages: `tmux`, `git`, `curl`, `wget`, `jq`
- Developer tools: `tree`, `htop`, `fzf`, `ripgrep`, `bat`

**Usage:**
```bash
bash scripts/bootstrap.sh --scenario=developer-desktop
```

### Clean Desktop
Best for: Minimal desktop installations, lightweight systems

**Includes:**
- Base packages only: `tmux`, `git`, `curl`, `wget`, `jq`

**Usage:**
```bash
bash scripts/bootstrap.sh --scenario=clean-desktop
```

### Development Server
Best for: Remote development servers, CI/CD runners

**Includes:**
- Base packages: `tmux`, `git`, `curl`, `wget`, `jq`
- Developer tools: `tree`, `htop`, `fzf`, `ripgrep`, `bat`

**Usage:**
```bash
bash scripts/bootstrap.sh --scenario=development-server --docker
```

### Production Server
Best for: Production deployments, minimal attack surface

**Includes:**
- Base packages only: `tmux`, `git`, `curl`, `wget`, `jq`

**Usage:**
```bash
bash scripts/bootstrap.sh --scenario=production-server
```

### Docker Host
Best for: Dedicated Docker container hosts, container orchestration servers

**Includes:**
- Base packages: `tmux`, `git`, `curl`, `wget`, `jq`
- Monitoring tools: `tree`, `htop`
- Docker CE (automatically installed)
- Current user added to docker group for non-root access

**Usage:**
```bash
bash scripts/bootstrap.sh --scenario=docker-host
```

**Note:** After installation, you need to log out and back in (or run `newgrp docker`) for the docker group membership to take effect.

---

## Virtual Machine Support

The bootstrap script automatically detects when running in a virtual machine and installs the appropriate hypervisor guest agent for optimal performance and integration.

### Supported Hypervisors

| Hypervisor | Ubuntu/Debian Agent | Fedora Agent | Auto-detection |
|------------|-------------------|--------------|----------------|
| VMware | open-vm-tools | open-vm-tools | ✓ |
| VirtualBox | virtualbox-guest-utils | virtualbox-guest-additions | ✓ |
| Hyper-V | hyperv-daemons | hyperv-daemons | ✓ |
| KVM/QEMU | qemu-guest-agent | qemu-guest-agent | ✓ |
| Xen | xen-guest-agent | xen-guest-agent | ✓ |

### What Guest Agents Do

Guest agents enable:
- **Better performance**: Optimized drivers and services
- **Time synchronization**: Keeps VM time in sync with host
- **Clipboard sharing**: Copy/paste between host and guest (where supported)
- **File sharing**: Shared folders functionality
- **Dynamic resolution**: Automatic screen resolution adjustment
- **Host communication**: Better integration with hypervisor management tools

### Manual Installation

If you're on physical hardware or want to skip agent installation, the script automatically detects this and continues without installing agents.

---

## macOS Support

### Homebrew Installation

The bootstrap script supports two Homebrew installation modes:

#### Default User-Local Installation (Recommended)

The script installs Homebrew to `~/.brew` without requiring root access:

```bash
bash scripts/bootstrap.sh
```

This creates:
- `~/.brew/` - Homebrew installation directory
- `~/bin/brew-source.sh` - Script to activate Homebrew in your shell

**Activating Homebrew:**
```bash
# Add to your shell profile (~/.bashrc, ~/.zshrc, etc.)
source ~/bin/brew-source.sh

# Or activate for current session
source ~/bin/brew-source.sh
```

The `brew-source.sh` script contains:
```bash
export PATH="$HOME/.brew/bin:$PATH"
export HOMEBREW_PREFIX="$HOME/.brew"
```

#### System-Wide Installation

If you prefer the official system-wide Homebrew installation to `/opt/homebrew` (Apple Silicon) or `/usr/local` (Intel):

1. Install Homebrew manually first:
   ```bash
   /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
   ```

2. Run the bootstrap script - it will detect the existing Homebrew installation

### Installing macOS Applications

The bootstrap script supports installing GUI applications on macOS:

#### Homebrew Cask Applications

Install applications via Homebrew Cask by creating a `macos-apps.txt` file:

```bash
# Create macos-apps.txt with apps to install
cat > macos-apps.txt << EOF
iterm2
visual-studio-code
docker
firefox
slack
EOF

# Run bootstrap to install apps
bash scripts/bootstrap.sh --apps
```

#### Mac App Store Applications

Install applications from the Mac App Store using `mas-cli`:

```bash
# Create mas-apps.txt with App Store app IDs
cat > mas-apps.txt << EOF
497799835  # Xcode
1333542190 # 1Password 7
1295203466 # Microsoft Remote Desktop
EOF

# Run bootstrap to install apps
bash scripts/bootstrap.sh --mas
```

**Finding App IDs:**
```bash
# Search for an app
mas search "App Name"

# List installed apps with IDs
mas list
```

#### Combined Installation

Install both command-line tools and applications:

```bash
bash scripts/bootstrap.sh --apps --mas
```

---

## Customization

### Adding New OS Versions

To add support for new Ubuntu, Debian, or Fedora versions:

1. **Update `scripts/package_mappings.sh`**:
   - Package mappings are mostly version-agnostic for Ubuntu and Debian
   - Add specific version mappings only if package names differ
   - For Fedora, update `FEDORA_PACKAGES` if needed

2. **Update `scripts/os_detection.sh`**:
   - Modify `is_supported_version()` to include the new version range

3. **Test the changes**:
   ```bash
   bash scripts/test_version_support.sh
   ```

### Adding New Tools

- Add tools to the appropriate array in `scripts/bootstrap.sh`:
  - `BASE_TOOLS` for essential tools (installed in all scenarios)
  - Add to scenario-specific tool lists for `developer-desktop` or `development-server`
- Update package mapping arrays in `scripts/package_mappings.sh` for each supported OS
- Handle any version-specific installation differences

### Custom Dotfiles

- Place your dotfiles in the `dotfiles/` directory
- The bootstrap script will automatically symlink them to your home directory

### Example: Adding Support for a New Tool

```bash
# In scripts/package_mappings.sh, add to package arrays
declare -A UBUNTU_PACKAGES=(
  # ... existing tools ...
  ["neovim"]="neovim"
)

declare -A FEDORA_PACKAGES=(
  # ... existing tools ...
  ["neovim"]="neovim"
)

# In scripts/bootstrap.sh, add to appropriate tool list
case "$INSTALL_SCENARIO" in
  developer-desktop)
    TOOLS=(${BASE_TOOLS[@]} tree htop fzf ripgrep bat neovim)
    ;;
  # ...
esac
```

---

---

## Version Compatibility Matrix

| Tool | Ubuntu 20.04+ | Debian 11+ | Fedora 35+ | macOS |
|------|---------------|------------|------------|-------|
| tmux | ✓ | ✓ | ✓ | ✓ |
| git | ✓ | ✓ | ✓ | ✓ |
| curl | ✓ | ✓ | ✓ | ✓ |
| wget | ✓ | ✓ | ✓ | ✓ |
| jq | ✓ | ✓ | ✓ | ✓ |
| tree | ✓ | ✓ | ✓ | ✓ |
| htop | ✓ | ✓ | ✓ | ✓ |
| fzf | ✓ | ✓ | ✓ | ✓ |
| ripgrep | ✓ | ✓ | ✓ | ✓ |
| bat | ✓ | ✓ (batcat in Debian 11) | ✓ | ✓ |

**Notes**: 
- The toolkit automatically handles package name differences (e.g., `bat` vs `batcat` in Debian 11) and creates appropriate aliases when needed.
- Ubuntu support includes both LTS releases (20.04, 22.04, 24.04) and interim releases (20.10, 21.10, 22.10, etc.)
- Supports Ubuntu Desktop, Server, and Minimal variants
- Supports Fedora Workstation and Server variants

## License

MIT
