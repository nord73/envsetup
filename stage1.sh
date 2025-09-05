#!/bin/bash

set -euo pipefail


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








