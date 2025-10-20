# macOS Desktop Setup Guide

This guide provides comprehensive best practices for setting up a clean macOS system using envsetup, with clear strategies for different use cases and avoiding unnecessary system contamination.

## Table of Contents

- [Initial Setup from cmd-R](#initial-setup-from-cmd-r)
- [Account Strategy](#account-strategy)
- [Setup Scenarios](#setup-scenarios)
- [Installation Order](#installation-order)
- [Best Practices](#best-practices)

---

## Initial Setup from cmd-R

When setting up a Mac from Recovery Mode (cmd-R at boot), follow these steps for the cleanest setup:

### 1. Recovery Mode Initial Setup

1. **Boot into Recovery**: Hold `cmd-R` immediately after power-on
2. **Disk Utility**: 
   - Erase the internal drive (APFS format, encrypted recommended)
   - Name it appropriately (e.g., "Macintosh HD")
3. **Install macOS**: Choose "Reinstall macOS" from Recovery
4. **Wait for Installation**: Let the system complete the fresh install

### 2. First Boot Configuration

During the Setup Assistant:

- **Internet Connection**: Connect to Wi-Fi
- **Migration Assistant**: Skip - don't migrate from another Mac/backup
- **Apple ID**: 
  - For personal Macs: Sign in with your Apple ID
  - For company Macs: Follow your organization's policy
  - You can skip and add later if unsure
- **Terms and Conditions**: Accept
- **Computer Account**: See [Account Strategy](#account-strategy) below
- **Location Services**: Enable (useful for time zone)
- **Analytics**: Personal preference
- **Screen Time**: Personal preference
- **Siri**: Personal preference
- **FileVault**: Enable for encryption (recommended)
- **Touch ID**: Set up if available

### 3. Post-Setup Configuration

Before installing anything:

1. **Check for Updates**: System Preferences → Software Update
2. **Install Command Line Tools** (if needed):
   ```bash
   xcode-select --install
   ```
3. **Configure Basic Settings**: Display, trackpad, dock preferences

---

## Account Strategy

Choose the appropriate account strategy based on your use case:

### Strategy 1: Single User Account (Recommended for Personal Macs)

**Best for:** Personal laptops, sole-user workstations

**Setup:**
- Create one admin account during setup
- Use this account for everything
- envsetup installs to user home directory (`~/.brew`, `~/bin`)
- No system contamination - everything is user-local

**Advantages:**
- Simple and straightforward
- Easy to maintain
- User-local Homebrew prevents system-wide pollution
- Can be easily reset by deleting and recreating the account

**Setup Process:**
1. Create admin account during first boot
2. Run envsetup with chosen scenario
3. All tools install to your home directory

### Strategy 2: Separate Admin + Standard User (Maximum Security)

**Best for:** Security-conscious users, shared machines

**Setup:**
- Create admin account during first boot (use for system updates only)
- Create a second standard user account for daily work
- Log out of admin, use standard account daily
- Only switch to admin for system updates or configuration

**Advantages:**
- Better security posture
- Prevents accidental system changes
- Clear separation of privileges
- Standard user can still use Homebrew (user-local)

**Setup Process:**
1. Create admin account during first boot (e.g., "Admin")
2. In System Preferences → Users & Groups, create standard user (e.g., "workuser")
3. Log out, log into standard user
4. Run envsetup - it works fine without sudo for most tools
5. When sudo is needed, authenticate with admin password

### Strategy 3: Clean Production + Development Separation (For Professionals)

**Best for:** Developers who want a pristine "production" environment and a "dev playground"

**Implementation Options:**

#### Option A: Two Accounts on One Mac
- Account 1: "Production" user - clean-desktop scenario only
- Account 2: "Development" user - developer-desktop scenario
- Fast user switching between them

#### Option B: Two Separate Macs
- Mac 1: Production/presentation machine - clean-desktop or production-server scenario
- Mac 2: Development machine - developer-desktop scenario with everything

#### Option C: Separate Volumes/Containers (Advanced)
- Use APFS volumes or containers for complete isolation
- Boot into different volumes for different purposes

---

## Setup Scenarios

envsetup provides multiple installation scenarios optimized for different macOS use cases:

### Scenario 1: Clean Desktop (Minimal/Pristine)

**Use case:** Minimal macOS setup, presentation machines, administrative workstations

**Philosophy:** Install only essential tools, keep system as clean as possible

**Includes:**
- Base command-line tools: `tmux`, `git`, `curl`, `wget`, `jq`
- User-local Homebrew (optional: use `--no-brew` flag to skip)
- No additional development tools
- No GUI applications (unless explicitly specified with `--apps`)

**Installation:**
```bash
git clone https://github.com/yourusername/envsetup.git
cd envsetup
bash scripts/bootstrap.sh --scenario=clean-desktop
```

**Optional additions:**
```bash
# Add minimal GUI apps
cat > macos-apps.txt << EOF
iterm2
EOF
bash scripts/bootstrap.sh --scenario=clean-desktop --apps
```

**Recommended for:**
- ✓ Executive/presentation Macs
- ✓ "Production" desktop environment
- ✓ Family members' computers
- ✓ Machines you want to keep pristine
- ✓ Administrative/documentation workstations

### Scenario 2: Developer Desktop (Full Development)

**Use case:** Primary development machine, full-featured workstation

**Philosophy:** Install comprehensive development tooling while maintaining organization

**Includes:**
- Base tools: `tmux`, `git`, `curl`, `wget`, `jq`
- Developer tools: `tree`, `htop`, `fzf`, `ripgrep`, `bat`
- User-local Homebrew
- Optional: GUI apps, Docker Desktop, additional tools

**Installation:**
```bash
git clone https://github.com/yourusername/envsetup.git
cd envsetup

# Basic developer setup
bash scripts/bootstrap.sh --scenario=developer-desktop

# Full setup with apps and tools
cat > macos-apps.txt << EOF
iterm2
visual-studio-code
docker
postman
firefox
slack
EOF

bash scripts/bootstrap.sh --scenario=developer-desktop --apps --bin
```

**Recommended for:**
- ✓ Primary development machines
- ✓ "Dirty all-inclusive" dev stations
- ✓ Software engineers' workstations
- ✓ Machines where you do most of your work

### Scenario 3: Selective Install (Custom)

**Use case:** Specific needs, partial tooling, customized environment

**Philosophy:** Choose exactly what you need, nothing more

**Installation:**
```bash
# Start with clean desktop as base
bash scripts/bootstrap.sh --scenario=clean-desktop

# Manually install additional tools as needed
brew install fzf ripgrep

# Or create a custom scenario by modifying bootstrap.sh
```

**Recommended for:**
- ✓ Special-purpose machines
- ✓ Testing/experimentation environments
- ✓ Highly customized workflows
- ✓ Learning/training environments

### Scenario 4: Production Server Style

**Use case:** Mac used as a server or automation workstation

**Philosophy:** Minimal tools, no GUI apps, server-oriented

**Includes:**
- Base tools only: `tmux`, `git`, `curl`, `wget`, `jq`
- No development tools
- No GUI applications
- Suitable for Mac Mini servers or automation hosts

**Installation:**
```bash
bash scripts/bootstrap.sh --scenario=production-server
```

**Recommended for:**
- ✓ Mac Mini servers
- ✓ CI/CD runners
- ✓ Automation workstations
- ✓ Headless Mac systems

---

## Installation Order

Follow this order for the cleanest setup:

### Phase 1: System Preparation
1. ✅ Complete macOS installation from cmd-R
2. ✅ Complete Setup Assistant
3. ✅ Install system updates
4. ✅ Configure basic system preferences
5. ✅ Install Command Line Tools if needed: `xcode-select --install`

### Phase 2: Account Setup
1. ✅ Decide on account strategy
2. ✅ Create necessary user accounts
3. ✅ Log into the account you'll use for development

### Phase 3: envsetup Installation
1. ✅ Clone envsetup repository:
   ```bash
   mkdir -p ~/src
   cd ~/src
   git clone https://github.com/yourusername/envsetup.git
   cd envsetup
   ```

2. ✅ Choose your scenario and run bootstrap:
   ```bash
   # Example: Clean desktop
   bash scripts/bootstrap.sh --scenario=clean-desktop
   
   # Example: Developer desktop with apps
   bash scripts/bootstrap.sh --scenario=developer-desktop --apps --mas
   ```

3. ✅ Activate Homebrew (if using user-local installation):
   ```bash
   source ~/bin/brew-source.sh
   # Add to your shell profile (~/.zshrc or ~/.bashrc):
   echo 'source ~/bin/brew-source.sh' >> ~/.zshrc
   ```

### Phase 4: Application Installation (Optional)
1. ✅ Create `macos-apps.txt` with desired Homebrew Cask apps
2. ✅ Create `mas-apps.txt` with Mac App Store app IDs
3. ✅ Run with `--apps` and/or `--mas` flags
4. ✅ Sign into Mac App Store if using `mas`

### Phase 5: Additional Configuration
1. ✅ Configure installed applications
2. ✅ Set up shell preferences
3. ✅ Configure git, SSH keys, etc.
4. ✅ Install language runtimes (Node.js, Python, etc.) as needed

---

## Best Practices

### Keeping the System Clean

1. **Use User-Local Homebrew**: 
   - Default installation to `~/.brew` keeps system directories clean
   - No need for `sudo` in most cases
   - Easy to completely remove by deleting `~/.brew`

2. **Avoid System-Wide Installations**:
   - Don't install tools with system package managers if available via Homebrew
   - Keep tools in `~/bin`, `~/.brew/bin`, etc.
   - Use `--prefix=$HOME/.local` when building from source

3. **Document Your Setup**:
   - Keep your `macos-apps.txt` and `mas-apps.txt` in version control (private repo)
   - Document custom configurations
   - Makes rebuilding easy if needed

4. **Regular Cleanup**:
   ```bash
   # Clean Homebrew caches
   brew cleanup
   
   # Remove unused formulae
   brew autoremove
   
   # Check for issues
   brew doctor
   ```

### Version Control Your Configuration

Create a private dotfiles/config repository:

```bash
mkdir -p ~/src/my-config
cd ~/src/my-config
git init

# Add your app lists
cp ~/src/envsetup/macos-apps.txt .
cp ~/src/envsetup/mas-apps.txt .

# Add custom configurations
# ... add your dotfiles, scripts, etc.

git add .
git commit -m "Initial configuration"
git remote add origin <your-private-repo>
git push -u origin main
```

### Rebuilding from Scratch

With envsetup and versioned configurations, you can rebuild your environment quickly:

```bash
# Phase 1: Fresh macOS install (cmd-R)
# Phase 2: Clone your config repo
git clone <your-private-repo> ~/src/my-config

# Phase 3: Clone and run envsetup
git clone https://github.com/yourusername/envsetup.git ~/src/envsetup
cd ~/src/envsetup
cp ~/src/my-config/macos-apps.txt .
cp ~/src/my-config/mas-apps.txt .
bash scripts/bootstrap.sh --scenario=developer-desktop --apps --mas

# Phase 4: Restore dotfiles from your config repo
# ... symlink or copy dotfiles as needed
```

### Hybrid Approach: Multiple Scenarios on One Mac

You can maintain different "profiles" by using different user accounts:

**Example Setup:**
```
Admin (admin account)
├── Used for system updates only
├── No envsetup installation
└── Kept completely clean

Work (standard user)
├── Scenario: clean-desktop
├── Only: base tools + essential apps
└── Presentation-ready

Dev (standard user)
├── Scenario: developer-desktop
├── All development tools
└── Playground for experimentation
```

Fast user switching allows you to jump between environments instantly.

---

## Troubleshooting

### Issue: Homebrew Commands Not Found

**Solution:**
```bash
# Activate Homebrew for current session
source ~/bin/brew-source.sh

# Add to shell profile permanently
echo 'source ~/bin/brew-source.sh' >> ~/.zshrc
source ~/.zshrc
```

### Issue: sudo Required for Homebrew

**Solution:** You're probably using system-wide Homebrew. envsetup uses user-local Homebrew by default. To switch:

```bash
# Remove system-wide Homebrew (backup first!)
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)"

# Run envsetup again - it will install user-local Homebrew
bash scripts/bootstrap.sh --scenario=<your-scenario>
```

### Issue: App Store Installations Fail

**Solution:**
```bash
# Sign into Mac App Store
mas signin your@email.com

# Or sign in via App Store GUI, then retry
bash scripts/bootstrap.sh --mas
```

### Issue: Want to Switch Scenarios

**Solution:** Just run bootstrap again with a different scenario:

```bash
# Switch from clean-desktop to developer-desktop
bash scripts/bootstrap.sh --scenario=developer-desktop

# Tools already installed will be skipped
# New tools will be installed
```

---

## Examples

### Example 1: Pristine Production Desktop

```bash
# Use clean-desktop with minimal apps
cd ~/src/envsetup

cat > macos-apps.txt << EOF
# Just essential productivity apps
iterm2
firefox
EOF

bash scripts/bootstrap.sh --scenario=clean-desktop --apps

# Result: Clean system with only base tools + terminal + browser
```

### Example 2: Full Developer Workstation

```bash
# Use developer-desktop with full tooling
cd ~/src/envsetup

cat > macos-apps.txt << EOF
iterm2
visual-studio-code
docker
postman
slack
notion
rectangle
firefox
google-chrome
EOF

cat > mas-apps.txt << EOF
497799835   # Xcode
EOF

bash scripts/bootstrap.sh --scenario=developer-desktop --apps --mas --bin

# Result: Complete development environment
```

### Example 3: Selective Research/Writing Machine

```bash
# Start minimal, add specific tools
cd ~/src/envsetup

cat > macos-apps.txt << EOF
iterm2
notion
obsidian
zotero
EOF

bash scripts/bootstrap.sh --scenario=clean-desktop --apps

# Manually add just what you need
brew install pandoc
brew install R

# Result: Clean system optimized for research/writing
```

---

## Summary

**Key Recommendations:**

1. **Clean Install**: Always start from cmd-R for the cleanest setup
2. **Account Strategy**: Single admin account is fine for personal use; separate accounts for security
3. **Choose Your Scenario**:
   - `clean-desktop`: Pristine/minimal systems
   - `developer-desktop`: Full development workstations
   - Custom: Build your own by starting minimal and adding tools
4. **User-Local Tools**: envsetup defaults to `~/.brew` - no system pollution
5. **Version Control**: Save your `macos-apps.txt` and `mas-apps.txt` for easy rebuilds
6. **Multiple Profiles**: Use different user accounts for different purposes (production vs dev)

With these practices, you can maintain clean, reproducible macOS environments that are easy to rebuild and don't contaminate system directories.
