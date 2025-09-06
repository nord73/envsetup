#!/bin/bash

set -euo pipefail

# --- help ---
show_help() {
cat << 'EOF'
Stage1 Binary Installation Script

USAGE:
    ./stage1.sh [OPTIONS]

DESCRIPTION:
    Installs the 'bin' tool and compatible binaries for managing development
    tools and dependencies. This script downloads and sets up essential
    binary management tools in user-local directories.

FEATURES:
    • Downloads and installs the latest 'bin' tool from marcosnils/bin
    • Sets up ~/bin directory for user-local binaries
    • Installs bin-compatible tools (vt-cli from VirusTotal)
    • No system-wide modifications required

INSTALLED TOOLS:
    • bin - Binary package manager (https://github.com/marcosnils/bin)
    • vt-cli - VirusTotal command line client

REQUIREMENTS:
    • curl and jq must be available
    • Internet connection for downloading binaries
    • Linux AMD64 platform

OPTIONS:
    -h, --help    Show this help message and exit

EXAMPLES:
    # Install bin tool and compatible binaries
    ./stage1.sh

DIRECTORIES:
    ~/bin/        User binaries directory (added to PATH)
    ~/tmp/        Temporary download directory (cleaned up)

NOTES:
    This script prepares the environment for further tool installations
    and should typically be run after the bootstrap script.

EOF
}

# --- parse args ---
for arg in "$@"; do
    case $arg in
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Use --help for usage information"
            exit 1
            ;;
    esac
done

# Prepare ~/bin

mkdir -p ~/bin

## Install bin START ##

mkdir -p ~/tmp && cd ~/tmp || exit

URL="marcosnils/bin"

LATEST_RELEASE=$(curl -s https://api.github.com/repos/$URL/releases/latest)
TAG_NAME=$(echo "$LATEST_RELEASE" | jq -r '.tag_name' | cut -c 2-)
FILENAME="bin_${TAG_NAME}_linux_amd64"

DOWNLOAD_URL=$(echo "$LATEST_RELEASE" | jq -r '.assets[] | select(.name | startswith("'"$FILENAME"'")) | .browser_download_url')

curl -s -L -o bin "$DOWNLOAD_URL"
chmod +x ./bin

./bin install "$URL"

cd ..
rm -rf ~/tmp/

## Install bin END ##

## Install bin compatible binaries START ##

bin install https://github.com/VirusTotal/vt-cli








## Install bin compatible binaries END ##








