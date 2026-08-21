#!/usr/bin/env bash
# =============================================================================
# Linksys X1000 — OpenWrt 23.05 Build Environment Setup
# Target: bcm63xx / BCM63281
# Run this on: Ubuntu 20.04/22.04 (native or WSL2)
# =============================================================================

set -euo pipefail

OPENWRT_TAG="v23.05.5"
OPENWRT_DIR="$HOME/openwrt-x1000"
REPO="https://github.com/openwrt/openwrt.git"

echo "=== [1/5] Installing build dependencies ==="
sudo apt-get update -qq
sudo apt-get install -y \
    build-essential clang flex bison g++ gawk gcc-multilib \
    g++-multilib gettext git libncurses-dev libssl-dev \
    python3-distutils rsync unzip zlib1g-dev file wget curl \
    libelf-dev swig python3-setuptools pkg-config \
    libpython3-dev ccache

echo "=== [2/5] Cloning OpenWrt ${OPENWRT_TAG} ==="
if [ -d "$OPENWRT_DIR" ]; then
    echo "Directory $OPENWRT_DIR already exists — pulling latest..."
    cd "$OPENWRT_DIR"
    git fetch origin
    git checkout "$OPENWRT_TAG"
else
    git clone --depth 1 -b "$OPENWRT_TAG" "$REPO" "$OPENWRT_DIR"
    cd "$OPENWRT_DIR"
fi

echo "=== [3/5] Updating feeds ==="
./scripts/feeds update -a
./scripts/feeds install -a

echo "=== [4/5] Applying X1000 patches ==="
PATCH_DIR="$(dirname "$(realpath "$0")")/patches"

if [ -d "$PATCH_DIR" ]; then
    for patch in "$PATCH_DIR"/*.patch; do
        echo "  Applying: $(basename "$patch")"
        patch -p1 --forward < "$patch" || echo "  [WARN] Patch may already be applied."
    done
else
    echo "  [WARN] Patch directory not found at $PATCH_DIR"
    echo "         Copy patches manually before running make."
fi

echo "=== [5/5] Copying .config ==="
CONFIG_SRC="$(dirname "$(realpath "$0")")/.config"
if [ -f "$CONFIG_SRC" ]; then
    cp "$CONFIG_SRC" "$OPENWRT_DIR/.config"
    cd "$OPENWRT_DIR" && make defconfig
    echo "  .config applied and expanded."
else
    echo "  [WARN] .config not found — run 'make menuconfig' manually."
fi

echo ""
echo "============================================================"
echo "  Build environment ready at: $OPENWRT_DIR"
echo ""
echo "  Next steps:"
echo "    cd $OPENWRT_DIR"
echo "    make menuconfig          # verify: Target=bcm63xx, Profile=Linksys X1000"
echo "    make -j\$(nproc) V=s     # full build (~30-60 min first time)"
echo ""
echo "  Output image:"
echo "    bin/targets/bcm63xx/generic/openwrt-*-linksys_x1000-*.bin"
echo "============================================================"
