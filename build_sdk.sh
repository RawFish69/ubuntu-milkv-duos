#!/bin/bash
# Wrapper to build the SDK with a clean PATH
# (Fixes Buildroot error about spaces in PATH from WSL)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="$SCRIPT_DIR/duo-buildroot-sdk-v2"

# Arch/target selection (override via environment)
MILKV_ARCH="${MILKV_ARCH:-arm64}"
if [ -z "${MILKV_SDK_TARGET:-}" ]; then
    if [[ "$MILKV_ARCH" == "arm64" ]]; then
        MILKV_SDK_TARGET="milkv-duos-glibc-arm64-sd"
    else
        MILKV_SDK_TARGET="milkv-duos-musl-riscv64-sd"
    fi
else
    MILKV_SDK_TARGET="${MILKV_SDK_TARGET}"
fi

if [ ! -d "$SDK_DIR" ]; then
    echo "Error: SDK directory not found at $SDK_DIR"
    echo "Clone it first:"
    echo "  git clone https://github.com/milkv-duo/duo-buildroot-sdk-v2.git $SDK_DIR"
    exit 1
fi

# Ensure SDK is patched for tinyalsa link dependency (pcm_* undefined references)
bash "$SCRIPT_DIR/patch_sdk.sh" "$SDK_DIR"

# Clean PATH (remove Windows paths with spaces)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
# Ensure python is available as `python` (SDK tools expect it)
export PATH="$SCRIPT_DIR/tools:$PATH"

# On ARM64, skip PQTool by default and only enable it when explicitly requested.
# This avoids non-deterministic host linker failures in isp_tool_daemon.
if [[ "$MILKV_ARCH" == "arm64" ]]; then
    if [[ "${BUILD_PQTOOL:-0}" == "1" ]]; then
        SKIP_PQTOOL=0
    else
        SKIP_PQTOOL=1
    fi
else
    : "${SKIP_PQTOOL:=0}"
fi
export SKIP_PQTOOL

echo "=========================================="
echo "Building Milk-V Duo S SDK"
echo "=========================================="
echo "PATH=$PATH"
echo "ARCH=$MILKV_ARCH"
echo "SDK TARGET=$MILKV_SDK_TARGET"
echo "SKIP_PQTOOL=$SKIP_PQTOOL"
if [[ "$MILKV_ARCH" == "arm64" ]]; then
    echo "BUILD_PQTOOL=${BUILD_PQTOOL:-0} (set BUILD_PQTOOL=1 to enable)"
fi
echo ""

cd "$SDK_DIR"
if [[ "$MILKV_ARCH" == "arm64" ]]; then
    if [[ "$MILKV_SDK_TARGET" != *"arm"* && "$MILKV_SDK_TARGET" != *"aarch64"* ]]; then
        echo "WARNING: MILKV_ARCH=arm64 but target '$MILKV_SDK_TARGET' does not look like an ARM target."
        echo "If your SDK uses a different name for the ARM build, set it like:"
        echo "  export MILKV_SDK_TARGET=<your-arm-target>"
        echo "Then re-run this script."
        echo ""
    fi

    # Verify target appears ARM64 in SDK v2 layout
    BOARD_CONFIG="$SDK_DIR/device/$MILKV_SDK_TARGET/boardconfig.sh"
    BOARD_DIR=""
    if [ -f "$BOARD_CONFIG" ]; then
        # shellcheck disable=SC1090
        source "$BOARD_CONFIG"
        if [ -n "$MV_BOARD_LINK" ]; then
            BOARD_DIR=$(find "$SDK_DIR/build/boards" -type d -name "$MV_BOARD_LINK" -print -quit)
        fi
    fi

    if [ -n "$BOARD_DIR" ] && [ -d "$BOARD_DIR" ]; then
        if [[ "$MV_BOARD_LINK" != *"arm64"* && "$BOARD_DIR" != *"arm64"* && ! -d "$BOARD_DIR/dts_arm64" ]]; then
            echo "ERROR: Target '$MILKV_SDK_TARGET' does not appear to be ARM64 in SDK v2."
            echo "Board dir: $BOARD_DIR"
            echo "Set MILKV_SDK_TARGET to an ARM64 target (e.g. milkv-duos-glibc-arm64-sd)."
            exit 1
        fi
    else
        echo "WARNING: Could not locate board for '$MILKV_SDK_TARGET' to verify ARM64."
        echo "Proceeding without ARM64 verification."
        echo ""
    fi
fi

SKIP_PQTOOL="$SKIP_PQTOOL" ./build.sh "$MILKV_SDK_TARGET"

# Find the generated image
IMG_FILE=$(ls -t "$SDK_DIR/out"/*.img 2>/dev/null | head -1)

if [ -n "$IMG_FILE" ] && [ -f "$IMG_FILE" ]; then
    # Create a backup of the original stock image
    BACKUP_FILE="${IMG_FILE%.img}-stock.img"
    if [ ! -f "$BACKUP_FILE" ]; then
        echo ""
        echo "Creating backup of stock image..."
        cp "$IMG_FILE" "$BACKUP_FILE"
        echo "Stock backup: $BACKUP_FILE"
    fi
    
    IMG_SIZE=$(du -h "$IMG_FILE" | cut -f1)
    
    echo ""
    echo "=========================================="
    echo "✓ SDK Build Complete!"
    echo "=========================================="
    echo ""
    echo "Image: $IMG_FILE"
    echo "Size:  $IMG_SIZE"
    echo ""
    echo "Next steps:"
    echo "  1. TEST STOCK IMAGE FIRST (recommended):"
    echo "     Flash $IMG_FILE with BalenaEtcher"
    echo "     Connect serial console (115200 baud)"
    echo "     Verify board boots to Buildroot"
    echo ""
    echo "  2. THEN build Ubuntu image:"
    echo "     sudo bash build_image.sh"
    echo ""
else
    echo ""
    echo "WARNING: Could not find generated image in $SDK_DIR/out/"
fi
