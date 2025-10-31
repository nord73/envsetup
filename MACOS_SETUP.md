# macOS Desktop Setup Guide

This guide provides comprehensive best practices for setting up a clean macOS system using envsetup, with clear strategies for different use cases and avoiding unnecessary system contamination.

## Table of Contents

- [Initial Setup from cmd-R](#initial-setup-from-cmd-r)
- [Apple Silicon Considerations](#apple-silicon-considerations)
- [Developer Tools Setup](#developer-tools-setup)
- [Account Strategy](#account-strategy)
- [Setup Scenarios](#setup-scenarios)
- [Installation Order](#installation-order)
- [Modern Tool Recommendations](#modern-tool-recommendations)
- [Shell Configuration](#shell-configuration)
- [Security Best Practices](#security-best-practices)
- [Performance Optimization](#performance-optimization)
- [Backup Strategy](#backup-strategy)
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

## Apple Silicon Considerations

If you have an Apple Silicon Mac (M1, M2, M3, M4, or later), there are additional considerations:

### Rosetta 2 Installation

Rosetta 2 allows Intel-based applications to run on Apple Silicon Macs. While many apps are now native, some may still require Rosetta 2.

**Check if Rosetta 2 is installed:**
```bash
/usr/bin/pgrep -q oahd && echo "Rosetta 2 is installed" || echo "Rosetta 2 is not installed"
```

**Install Rosetta 2:**
```bash
softwareupdate --install-rosetta --agree-to-license
```

**When to install Rosetta 2:**
- ✓ If you need to run any Intel-only applications
- ✓ If you use development tools that haven't been updated to ARM
- ✓ If you're unsure (it's small and harmless to have installed)
- ✗ If you're strictly running only Apple Silicon native apps

### Homebrew on Apple Silicon

Homebrew on Apple Silicon installs to `/opt/homebrew` (instead of `/usr/local` on Intel Macs).

**envsetup handles this automatically:**
- User-local installation: `~/.brew` (works on both Intel and Apple Silicon)
- System-wide installation: Script detects and uses existing Homebrew at correct location

**Architecture-specific considerations:**
```bash
# Check your Mac's architecture
uname -m  # arm64 = Apple Silicon, x86_64 = Intel

# If using system Homebrew, confirm installation path
which brew  # /opt/homebrew/bin/brew (Apple Silicon) or /usr/local/bin/brew (Intel)
```

### Running Intel Applications

Some applications may still be Intel-only:

```bash
# Check if an application is running under Rosetta
# In Activity Monitor, add the "Kind" column
# "Apple" = Native, "Intel" = Running under Rosetta

# Or check from command line
file /Applications/YourApp.app/Contents/MacOS/YourApp
```

### Performance Notes

- **Native apps** perform significantly better than Intel apps under Rosetta
- **Prefer native versions** when available (check developer websites)
- **Docker considerations**: Docker Desktop runs natively on Apple Silicon but can run both ARM and x86_64 containers

---

## Developer Tools Setup

### Command Line Tools

The Xcode Command Line Tools are essential for most development work:

**Installation:**
```bash
xcode-select --install
```

**Verification:**
```bash
xcode-select -p
# Should output: /Library/Developer/CommandLineTools
```

**Troubleshooting:**
```bash
# If having issues, reset and reinstall
sudo rm -rf /Library/Developer/CommandLineTools
xcode-select --install
```

### Xcode (Full IDE)

Only install if you need iOS/macOS development:

**Option 1: Mac App Store (Recommended)**
```bash
# Using mas-cli (install via envsetup with --mas flag)
mas install 497799835  # Xcode
```

**Option 2: Direct Download**
- Visit https://developer.apple.com/download/
- Download Xcode
- Move to Applications folder
- First launch: `sudo xcodebuild -license accept`

**Size consideration:** Xcode is large (~12-15GB). Only install if needed.

### Git Configuration

After installing git via envsetup, configure it:

```bash
git config --global user.name "Your Name"
git config --global user.email "your.email@example.com"
git config --global init.defaultBranch main
git config --global pull.rebase false  # or true, based on preference
```

**Optional but recommended:**
```bash
# Better diff output
git config --global diff.algorithm histogram

# Helpful aliases
git config --global alias.st status
git config --global alias.co checkout
git config --global alias.br branch
git config --global alias.lg "log --graph --oneline --decorate --all"

# macOS-specific: Use macOS keychain for credentials
git config --global credential.helper osxkeychain
```

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

## Modern Tool Recommendations

Beyond the base tools provided by envsetup, consider these modern alternatives and productivity enhancers:

### Terminal Emulators

**iTerm2** (Traditional, Highly Configurable)
```bash
# Add to macos-apps.txt
iterm2
```
- ✓ Split panes, profiles, extensive customization
- ✓ Free and open source
- ✓ Well-established, stable

**Warp** (Modern, AI-Enhanced)
```bash
# Add to macos-apps.txt
warp
```
- ✓ Modern UI with blocks and workflows
- ✓ AI command suggestions
- ✓ Built-in collaboration features
- ⚠ Requires account (free tier available)

**Alacritty** (Fast, Minimal)
```bash
brew install --cask alacritty
```
- ✓ GPU-accelerated, extremely fast
- ✓ Minimal, focused on performance
- ✗ Less features than iTerm2/Warp

### Web Browsers

**Arc** (Modern, Productivity-Focused)
```bash
# Add to macos-apps.txt
arc
```
- ✓ Vertical tabs, spaces for organization
- ✓ Built-in ad blocker, split view
- ✓ Native macOS design
- ⚠ Invitation or waitlist may be required

**Brave** (Privacy-Focused)
```bash
# Add to macos-apps.txt
brave-browser
```
- ✓ Built-in ad blocking and privacy features
- ✓ Chromium-based (Chrome extension compatible)
- ✓ Crypto wallet integration (optional)

### Productivity Tools

**Raycast** (Spotlight Replacement)
```bash
# Add to macos-apps.txt
raycast
```
- ✓ Extensible launcher with plugins
- ✓ Clipboard history, snippets, scripts
- ✓ Window management, calculator, and more
- ✓ Free for personal use

**Rectangle** (Window Management)
```bash
# Add to macos-apps.txt
rectangle
```
- ✓ Keyboard shortcuts for window tiling
- ✓ Free and open source
- ✓ Simple, lightweight

**Alternatives:** Rectangle Pro (paid), Magnet (paid), BetterSnapTool (paid)

**Wezterm** (Modern Terminal)
```bash
# Add to macos-apps.txt
wezterm
```
- ✓ GPU-accelerated
- ✓ Highly configurable via Lua
- ✓ Built-in multiplexing
- ✓ Cross-platform

### Development Tools

**Visual Studio Code** (Most Popular Editor)
```bash
# Add to macos-apps.txt
visual-studio-code
```
- ✓ Extensive extension ecosystem
- ✓ Built-in Git integration
- ✓ Remote development support

**Docker Desktop** (Containerization)
```bash
# Add to macos-apps.txt
docker
```
- ✓ Native Apple Silicon support
- ✓ Kubernetes integration
- ⚠ Resource intensive

**Postman** (API Development)
```bash
# Add to macos-apps.txt
postman
```
- ✓ API testing and documentation
- ✓ Collection management
- ✓ Team collaboration features

### Command Line Utilities

**Modern Replacements for Classic Tools:**

```bash
# Add to your packages or install via Homebrew
brew install \
  eza          # Modern 'ls' with colors and icons \
  bat          # Better 'cat' with syntax highlighting \
  ripgrep      # Faster 'grep' \
  fd           # Faster 'find' \
  zoxide       # Smarter 'cd' with frecency \
  httpie       # Better 'curl' for APIs \
  tldr         # Simpler 'man' pages \
  duf          # Better 'df' \
  dust         # Better 'du' \
  procs        # Modern 'ps' \
  bottom       # Better 'top/htop' \
  delta        # Better git diff
```

### Recommended Apps Configuration Example

```bash
# macos-apps.txt - Developer Setup
iterm2
warp
visual-studio-code
docker
postman
rectangle
raycast
arc
firefox
slack
notion
obsidian
```

```bash
# mas-apps.txt - Mac App Store
497799835   # Xcode (if doing iOS/macOS dev)
441258766   # Magnet (alternative to Rectangle)
1295203466  # Microsoft Remote Desktop
```

---

## Shell Configuration

macOS uses Zsh as the default shell since macOS Catalina (10.15). Proper shell configuration enhances productivity.

### Zsh Setup

**Default Shell Verification:**
```bash
echo $SHELL
# Should output: /bin/zsh
```

**Configuration File:**
Your main Zsh configuration file is `~/.zshrc`

### Oh My Zsh (Optional Framework)

**Installation:**
```bash
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

**Benefits:**
- ✓ Plugin system for common tools (git, docker, etc.)
- ✓ Theme system for prompt customization
- ✓ Auto-updates
- ⚠ Can slow down shell startup if overused

**Recommended Plugins:**
```bash
# In ~/.zshrc
plugins=(git brew macos docker kubectl zoxide fzf)
```

### Starship Prompt (Modern Alternative)

**Installation:**
```bash
brew install starship

# Add to ~/.zshrc
echo 'eval "$(starship init zsh)"' >> ~/.zshrc
```

**Benefits:**
- ✓ Fast and minimal
- ✓ Shows git status, language versions, etc.
- ✓ Cross-shell compatible
- ✓ Highly configurable

### Essential Shell Aliases

Add to your `~/.zshrc`:

```bash
# Navigation
alias ..='cd ..'
alias ...='cd ../..'
alias ~='cd ~'

# Modern tool replacements (if installed)
alias ls='eza --icons'
alias ll='eza -l --icons'
alias la='eza -la --icons'
alias cat='bat'

# Git shortcuts (if not using oh-my-zsh git plugin)
alias gs='git status'
alias ga='git add'
alias gc='git commit'
alias gp='git push'
alias gl='git log --oneline --graph --decorate'

# macOS specific
alias showfiles='defaults write com.apple.finder AppleShowAllFiles YES; killall Finder'
alias hidefiles='defaults write com.apple.finder AppleShowAllFiles NO; killall Finder'
alias cleanup="find . -type f -name '*.DS_Store' -ls -delete"

# Homebrew
alias brewup='brew update && brew upgrade && brew cleanup'
```

### Path Configuration

If using envsetup's user-local Homebrew:

```bash
# In ~/.zshrc
source ~/bin/brew-source.sh

# Add user bin to PATH if not already there
export PATH="$HOME/bin:$PATH"
```

### Shell Performance

**Measure startup time:**
```bash
time zsh -i -c exit
```

**If slow (>1s), diagnose:**
```bash
# Add to beginning of ~/.zshrc temporarily
zmodload zsh/zprof

# Add to end of ~/.zshrc temporarily
zprof

# Then open new terminal and review output
```

### Tab Completion

**Enable advanced completion:**
```bash
# Usually already in ~/.zshrc, but verify:
autoload -Uz compinit && compinit
```

**Case-insensitive completion:**
```bash
# Add to ~/.zshrc
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
```

---

## Security Best Practices

Keeping your Mac secure without sacrificing usability:

### FileVault (Disk Encryption)

**Enable FileVault:**
```bash
# System Preferences → Security & Privacy → FileVault → Turn On FileVault

# Or via command line (requires restart):
sudo fdesetup enable
```

**Verification:**
```bash
fdesetup status
# Should output: FileVault is On
```

**Important:**
- ✓ Protects data if Mac is lost or stolen
- ✓ Required for some corporate policies
- ⚠ Save recovery key in secure location
- ⚠ Slight performance impact (usually negligible on modern Macs)

### Firewall

**Enable Firewall:**
```bash
# System Preferences → Security & Privacy → Firewall → Turn On Firewall

# Or via command line:
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setglobalstate on
```

**Firewall Options:**
```bash
# Enable stealth mode (don't respond to ping):
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setstealthmode on

# Block all incoming connections (strict):
sudo /usr/libexec/ApplicationFirewall/socketfilterfw --setblockall on
```

### Gatekeeper

Gatekeeper prevents unknown applications from running:

**Status Check:**
```bash
spctl --status
# Should output: assessments enabled
```

**Allowing Apps from Identified Developers:**
- System Preferences → Security & Privacy → General
- "Allow apps downloaded from: App Store and identified developers"

**Running Unsigned Apps (Use Caution):**
```bash
# Right-click app → Open (first time only)
# Or temporarily disable (not recommended):
sudo spctl --master-disable
```

### SSH Key Management

**Generate SSH Keys:**
```bash
# Ed25519 (recommended, modern)
ssh-keygen -t ed25519 -C "your.email@example.com"

# RSA (if Ed25519 not supported)
ssh-keygen -t rsa -b 4096 -C "your.email@example.com"
```

**Add to SSH Agent:**
```bash
# Start agent
eval "$(ssh-agent -s)"

# Add key to agent and macOS keychain
ssh-add --apple-use-keychain ~/.ssh/id_ed25519

# Configure SSH to use keychain (add to ~/.ssh/config)
cat >> ~/.ssh/config << EOF
Host *
  AddKeysToAgent yes
  UseKeychain yes
  IdentityFile ~/.ssh/id_ed25519
EOF
```

### Password Management

**Use a Password Manager:**
- ✓ 1Password (commercial, highly rated)
- ✓ Bitwarden (open source, freemium)
- ✓ iCloud Keychain (built-in, basic)

**Enable Two-Factor Authentication:**
- Enable 2FA on Apple ID
- Enable 2FA on all critical services (GitHub, email, etc.)

### Privacy Settings

**Review Privacy Settings:**
```bash
# System Preferences → Security & Privacy → Privacy
```

**Recommended:**
- ✓ Review Location Services permissions
- ✓ Review Contacts, Calendar, Photos access
- ✓ Disable analytics if desired
- ✓ Review Full Disk Access carefully

### System Integrity Protection (SIP)

SIP is enabled by default. **Leave it enabled** unless you have specific needs.

**Check Status:**
```bash
csrutil status
# Should output: System Integrity Protection status: enabled
```

### Software Updates

**Enable Automatic Updates:**
```bash
# System Preferences → Software Update → Advanced
# Check: Install macOS updates, Install app updates, Install system data files and security updates
```

**Manual Check:**
```bash
softwareupdate --list
sudo softwareupdate --install --all
```

---

## Performance Optimization

Keeping your Mac responsive and efficient:

### Reduce Visual Effects

**Disable Animations:**
```bash
# Reduce motion
defaults write com.apple.universalaccess reduceMotion -bool true

# Reduce transparency
defaults write com.apple.universalaccess reduceTransparency -bool true

# Faster window animations
defaults write NSGlobalDomain NSWindowResizeTime -float 0.001

# Disable window animations
defaults write NSGlobalDomain NSAutomaticWindowAnimationsEnabled -bool false

# Restart Dock to apply
killall Dock
```

**Revert if Needed:**
```bash
defaults delete com.apple.universalaccess reduceMotion
defaults delete com.apple.universalaccess reduceTransparency
defaults delete NSGlobalDomain NSWindowResizeTime
defaults delete NSGlobalDomain NSAutomaticWindowAnimationsEnabled
killall Dock
```

### Dock Optimization

**Faster Dock:**
```bash
# Remove dock show/hide delay
defaults write com.apple.dock autohide-delay -float 0
defaults write com.apple.dock autohide-time-modifier -float 0.5

# Restart Dock
killall Dock
```

**Minimize to Application Icon:**
```bash
defaults write com.apple.dock minimize-to-application -bool true
killall Dock
```

### Spotlight Optimization

**Exclude Folders from Spotlight:**
```bash
# System Preferences → Spotlight → Privacy
# Add folders like ~/Downloads, node_modules, etc.
```

**Rebuild Spotlight Index (if search is slow):**
```bash
sudo mdutil -E /
```

### Login Items

**Reduce Startup Items:**
```bash
# System Preferences → Users & Groups → Login Items
# Remove unnecessary startup applications
```

### Storage Optimization

**Check Storage:**
```bash
# About This Mac → Storage → Manage
```

**Clean System:**
```bash
# Clear caches (careful!)
rm -rf ~/Library/Caches/*

# Empty trash
rm -rf ~/.Trash/*

# Homebrew cleanup (if using Homebrew)
brew cleanup --prune=all

# Remove old iOS backups
rm -rf ~/Library/Application\ Support/MobileSync/Backup/*
```

**Additional Cleanup:**
- Remove old Xcode versions/simulators (if applicable)
- Clear Downloads folder
- Remove large files you don't need (use Disk Inventory X or DaisyDisk)

### Activity Monitor

**Monitor Resource Usage:**
```bash
# Built-in tool: Applications → Utilities → Activity Monitor
# Or command line:
top
```

**Common Resource Hogs:**
- Chrome/browser with many tabs
- Docker Desktop when idle
- Electron apps (Slack, Discord, etc.)
- Spotlight indexing
- Time Machine backups during operation

### Restart Regularly

**Recommended:**
- Restart weekly for optimal performance
- Updates often require restart
- Clears memory leaks and temporary issues

---

## Backup Strategy

Protect your data with a comprehensive backup strategy:

### Time Machine (Local Backups)

**Setup:**
1. Connect external drive (1TB+ recommended)
2. System Preferences → Time Machine
3. Select Backup Disk
4. Enable automatic backups

**Best Practices:**
- ✓ Use encrypted backup disk
- ✓ Keep backup drive unplugged when not backing up (protection from malware/accidents)
- ✓ Replace backup drives every 3-5 years
- ⚠ Time Machine is not bootable on Apple Silicon Macs

**Exclude Unnecessary Folders:**
```bash
# System Preferences → Time Machine → Options → Exclude These Items
```

Common exclusions:
- `~/Downloads`
- `~/.Trash`
- `~/Library/Caches`
- `node_modules` directories
- Virtual machine images

### Cloud Backups

**iCloud:**
- ✓ Built-in, seamless
- ✓ Documents, Desktop, Photos
- ⚠ Limited free space (5GB), paid plans available

**Alternative Services:**
- **Backblaze** (unlimited for ~$7/month)
- **Arq + Cloud Storage** (S3, B2, etc.)
- **Dropbox, Google Drive, OneDrive** (for specific folders)

### Version Control for Code

**Git + GitHub/GitLab/Bitbucket:**
```bash
# Keep all code in Git repositories
# Push regularly to remote
git push origin main
```

**Benefits:**
- ✓ Infinite version history
- ✓ Branch-based experimentation
- ✓ Collaboration support
- ✓ Off-site backup

### Configuration Backup

**Dotfiles Repository:**
```bash
# Keep your configuration in Git
mkdir ~/dotfiles
cd ~/dotfiles
git init

# Add configurations
cp ~/.zshrc .
cp ~/.gitconfig .
cp ~/.ssh/config ssh_config

git add .
git commit -m "Initial dotfiles"
git remote add origin <your-private-repo>
git push -u origin main
```

**App Lists (envsetup):**
```bash
# Keep your macos-apps.txt and mas-apps.txt in version control
cd ~/src/envsetup
git add macos-apps.txt mas-apps.txt
git commit -m "My app configuration"
```

### Testing Backups

**Verify Backups Regularly:**
- Restore a test file from Time Machine
- Check iCloud sync status
- Verify cloud backup service is running

**Recovery Testing:**
- Know how to boot into Recovery Mode (cmd-R)
- Know how to restore from Time Machine
- Test restoring a file before you need it

### 3-2-1 Backup Rule

**Best Practice:**
- **3** copies of your data
- **2** different media types
- **1** off-site copy

**Example:**
1. Original data on Mac
2. Time Machine backup (external drive)
3. Cloud backup (Backblaze/iCloud/etc.)

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
