#!/bin/bash
#
# Install build dependencies for Milk-V Duo S SDK
# Handles package name differences across Ubuntu versions
#

set -e

echo "=========================================="
echo "Installing Build Dependencies"
echo "=========================================="
echo ""

# Update package list
echo "Updating package list..."
sudo apt update

# Base packages that should work on all Ubuntu versions
BASE_PACKAGES="pkg-config build-essential ninja-build automake autoconf libtool wget curl git gcc libssl-dev bc squashfs-tools android-sdk-libsparse-utils jq scons parallel tree python3-dev python3-pip device-tree-compiler ssh cpio fakeroot flex bison genext2fs rsync unzip dosfstools mtools tcl openssh-client cmake expect libconfuse2 parted e2fsprogs qemu-user-static binfmt-support"

# Packages that may have different names or be obsolete
# Try to install alternatives or skip if not available

echo ""
echo "Installing base packages..."
sudo apt install -y $BASE_PACKAGES

echo ""
echo "Installing ncurses (for menuconfig)..."
# Try libncurses5-dev first, fall back to libncurses-dev
if sudo apt install -y libncurses5-dev 2>/dev/null; then
    echo "  ✓ Installed libncurses5-dev"
elif sudo apt install -y libncurses-dev 2>/dev/null; then
    echo "  ✓ Installed libncurses-dev (alternative)"
else
    echo "  ⚠️  Could not install ncurses dev package"
fi

# Try to install libncurses5 runtime if needed
sudo apt install -y libncurses5 2>/dev/null || sudo apt install -y libncurses6 2>/dev/null || echo "  ⚠️  ncurses runtime may already be installed"

echo ""
echo "Installing python3-distutils (if available)..."
# python3-distutils is included in python3 in Ubuntu 22.04+, but try to install if available
sudo apt install -y python3-distutils 2>/dev/null || echo "  ℹ️  python3-distutils not needed (included in python3)"

echo ""
echo "Installing slib (if available)..."
# slib may not be available, try to install or skip
sudo apt install -y slib 2>/dev/null || echo "  ℹ️  slib not available - may not be required"

echo ""
echo "Installing additional packages..."
# Additional packages that might be needed
sudo apt install -y python3-setuptools 2>/dev/null || true
sudo apt install -y file 2>/dev/null || true

echo ""
echo "=========================================="
echo "Verifying critical tools..."
echo "=========================================="

MISSING=0
for tool in make gcc cmake python3 git wget curl; do
    if command -v $tool &> /dev/null; then
        VERSION=$($tool --version 2>/dev/null | head -1 || echo "installed")
        echo "  ✓ $tool: $VERSION"
    else
        echo "  ❌ $tool: NOT FOUND"
        MISSING=1
    fi
done

echo ""

if [ $MISSING -eq 1 ]; then
    echo "⚠️  WARNING: Some critical tools are missing!"
    echo "   Please check the errors above and install manually if needed."
    exit 1
fi

# Check cmake version
if command -v cmake &> /dev/null; then
    CMAKE_VERSION=$(cmake --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
    CMAKE_MAJOR=$(echo $CMAKE_VERSION | cut -d. -f1)
    CMAKE_MINOR=$(echo $CMAKE_VERSION | cut -d. -f2)
    CMAKE_PATCH=$(echo $CMAKE_VERSION | cut -d. -f3)
    
    echo "Checking cmake version..."
    if [ "$CMAKE_MAJOR" -lt 3 ] || ([ "$CMAKE_MAJOR" -eq 3 ] && [ "$CMAKE_MINOR" -lt 16 ]) || ([ "$CMAKE_MAJOR" -eq 3 ] && [ "$CMAKE_MINOR" -eq 16 ] && [ "$CMAKE_PATCH" -lt 5 ]); then
        echo "  ⚠️  cmake version $CMAKE_VERSION is below required 3.16.5"
        echo "     Consider installing a newer version if build fails."
    else
        echo "  ✓ cmake version $CMAKE_VERSION meets requirements"
    fi
fi

echo ""
echo "=========================================="
echo "✓ Dependency installation complete!"
echo "=========================================="
echo ""
echo "You can now proceed with the build:"
echo "  bash build_sdk.sh"
echo ""

