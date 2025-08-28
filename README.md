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
  Main setup script for verifying and installing essential tools.

- `scripts/verify_tools.sh`  
  Checks presence and versions of essential tools.

---

## Customization

- Add more tools to `scripts/bootstrap.sh` as needed.
- Place your dotfiles in the `dotfiles/` directory.
- Extend with language runtimes or containers as required.

---

## License

MIT
