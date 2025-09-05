# envsetup

A minimal, user-local environment setup toolkit for new computers, users, VMs, and remote VPS on **Ubuntu 24.04+**, **Debian 13+**, and **MacOS (latest)**.
This repo helps bootstrap a clean development environment with essential tools, dotfiles, and language runtimes, avoiding unnecessary system-wide installations.

---

## Features

- **Bootstrap scripts** for verifying and installing essential tools.
- **Dotfiles management** for shell and editor configuration.
- **User-local installs** (no global contamination).
- **Optional language runtimes** (Python, Node.js, Go).
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
- Verify essential tools (`git`, `curl`, `wget`, `tree`, etc.)
- Install missing tools using `apt` (Linux) or `brew` (MacOS)
- Set up user directories (`~/bin`, `~/src`)
- Optionally install Homebrew (on MacOS)
- Symlink dotfiles

---

## Scripts

- **`scripts/bootstrap.sh`**  
  Main setup script for verifying and installing essential tools.

- **`scripts/validate.sh`**  
  Validation script to check all scripts for syntax and basic functionality.

- **`stage1.sh`**  
  Install script for the `bin` tool and compatible binaries.

- **`rescue-install/install-zfs-trixie.sh`**  
  Advanced ZFS-on-root installer for Debian 13 with enhanced security and features.

---

## ZFS Installer Features

The `rescue-install/install-zfs-trixie.sh` script provides:

### Security & Robustness
- **Secure environment variable passing** (no sed/perl injection)
- **Hardened SSH key import** with validation and timeout handling
- **Comprehensive error handling** with proper cleanup
- **Input validation** and requirement checking

### Advanced Features
- **DEBUG mode** for troubleshooting (`DEBUG=1`)
- **Optional disk autodetect** (automatically finds largest available disk)
- **Optimal partition alignment** (1MiB boundaries)
- **Robust cleanup** with retries and process termination
- **Idempotent operations** (safe to re-run)

### Usability
- **Comprehensive help** (`--help` or `-h`)
- **Color-coded logging** with different message types
- **Configuration display** before proceeding
- **Environment variable configuration** via `.env` file

### Usage Examples

```bash
# Basic install with auto-detected disk
sudo ./rescue-install/install-zfs-trixie.sh

# Install with specific configuration
sudo DISK=/dev/nvme0n1 NEW_USER=admin SSH_IMPORT_IDS="gh:myuser" ./rescue-install/install-zfs-trixie.sh

# Install with debug mode and force (no confirmations)
sudo DEBUG=1 FORCE=1 ./rescue-install/install-zfs-trixie.sh

# Show help
./rescue-install/install-zfs-trixie.sh --help
```

---

## Customization

- Add more tools to `scripts/bootstrap.sh` as needed.
- Place your dotfiles in the `dotfiles/` directory.
- Extend with language runtimes or containers as required.
- Configure ZFS installer via environment variables or `.env` file.

---

## Validation

Run the validation script to check all components:

```bash
./scripts/validate.sh
```

This will verify syntax, run shellcheck, and test basic functionality.

---

## License

MIT
