#!/bin/bash
# Wrapper to build the SDK with a clean PATH
# (Fixes Buildroot error about spaces in PATH from WSL)

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="$SCRIPT_DIR/duo-buildroot-sdk"

if [ ! -d "$SDK_DIR" ]; then
    echo "Error: SDK directory not found at $SDK_DIR"
    echo "Clone it first:"
    echo "  git clone https://github.com/milkv-duo/duo-buildroot-sdk.git"
    exit 1
fi

# Clean PATH (remove Windows paths with spaces)
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

echo "=========================================="
echo "Building Milk-V Duo S SDK"
echo "=========================================="
echo "PATH=$PATH"
echo ""

cd "$SDK_DIR"
./build.sh milkv-duos-sd

# Find the generated image
IMG_FILE=$(ls -t "$SDK_DIR/out"/milkv-duos-sd*.img 2>/dev/null | head -1)

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
