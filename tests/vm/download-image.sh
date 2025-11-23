#!/bin/bash
# Download cloud images for VM testing
# Supports Ubuntu and Debian

set -euo pipefail

OS_VERSION="$1"
CACHE_DIR="${HOME}/.cache/vm-images"
mkdir -p "$CACHE_DIR"

# Image URLs
declare -A IMAGE_URLS=(
    ["ubuntu-22.04"]="https://cloud-images.ubuntu.com/releases/22.04/release/ubuntu-22.04-server-cloudimg-amd64.img"
    ["ubuntu-24.04"]="https://cloud-images.ubuntu.com/releases/24.04/release/ubuntu-24.04-server-cloudimg-amd64.img"
    ["debian-11"]="https://cloud.debian.org/images/cloud/bullseye/latest/debian-11-generic-amd64.qcow2"
    ["debian-12"]="https://cloud.debian.org/images/cloud/bookworm/latest/debian-12-generic-amd64.qcow2"
)

if [[ ! -v IMAGE_URLS["$OS_VERSION"] ]]; then
    echo "ERROR: Unsupported OS version: $OS_VERSION"
    echo "Supported: ${!IMAGE_URLS[@]}"
    exit 1
fi

IMAGE_URL="${IMAGE_URLS[$OS_VERSION]}"
IMAGE_FILE="$CACHE_DIR/${OS_VERSION}.qcow2"

if [[ -f "$IMAGE_FILE" ]]; then
    echo "Image already cached: $IMAGE_FILE"
    exit 0
fi

echo "Downloading $OS_VERSION cloud image..."
curl -L -o "$IMAGE_FILE.tmp" "$IMAGE_URL"
mv "$IMAGE_FILE.tmp" "$IMAGE_FILE"
echo "Downloaded to: $IMAGE_FILE"
