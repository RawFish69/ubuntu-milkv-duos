#!/bin/bash
# Install systemd into Ubuntu Base

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_BASE="$SCRIPT_DIR/ubuntu_base"

if [ ! -d "$UBUNTU_BASE" ]; then
    echo "Error: Ubuntu Base directory not found: $UBUNTU_BASE"
    exit 1
fi

# Check prerequisites
if ! dpkg -s qemu-user-static binfmt-support >/dev/null 2>&1; then
    echo "Installing qemu-user-static..."
    sudo apt-get update
    sudo apt-get install -y qemu-user-static binfmt-support
fi

if [ -x /usr/sbin/update-binfmts ]; then
    sudo update-binfmts --enable qemu-riscv64 2>/dev/null || true
fi

if [ ! -f /proc/sys/fs/binfmt_misc/qemu-riscv64 ]; then
    sudo bash -c 'echo ":qemu-riscv64:M::\x7fELF\x02\x01\x01\x00\x00\x00\x00\x00\x00\x00\x00\x00\x02\x00\xf3\x00:\xff\xff\xff\xff\xff\xff\xff\x00\xff\xff\xff\xff\xff\xff\xff\xff\xfe\xff\xff\xff:/usr/bin/qemu-riscv64-static:OC" > /proc/sys/fs/binfmt_misc/register' 2>/dev/null || true
fi

# Copy QEMU
QEMU_CHROOT_PATH="/usr/bin/qemu-riscv64-chroot"
if [ ! -f "$UBUNTU_BASE$QEMU_CHROOT_PATH" ]; then
    sudo mkdir -p "$UBUNTU_BASE/usr/bin"
    sudo cp /usr/bin/qemu-riscv64-static "$UBUNTU_BASE$QEMU_CHROOT_PATH"
    sudo chmod +x "$UBUNTU_BASE$QEMU_CHROOT_PATH"
fi

cd "$UBUNTU_BASE"

# Setup bind mounts
sudo umount -l dev/random 2>/dev/null || true
sudo umount -l dev proc sys tmp 2>/dev/null || true
sleep 1

for d in dev proc sys tmp; do
    if ! mountpoint -q "$d"; then
        sudo rm -rf "$d" 2>/dev/null || true
    fi
done

sudo mkdir -p dev proc sys tmp etc/apt

sudo mount --bind /dev dev
sudo mount --bind /proc proc
sudo mount --bind /sys sys
sudo mount -t tmpfs tmpfs tmp
sudo chmod 1777 tmp
if [ -c /dev/urandom ]; then
    sudo mount --bind /dev/urandom dev/random
fi

sudo bash -c 'echo "nameserver 8.8.8.8" > etc/resolv.conf'

if [ ! -f etc/apt/sources.list ]; then
    sudo bash -c 'cat > etc/apt/sources.list << "EOF"
deb http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
EOF'
fi

if [ ! -f "$UBUNTU_BASE/usr/bin/qemu-riscv64-static" ]; then
    sudo cp /usr/bin/qemu-riscv64-static "$UBUNTU_BASE/usr/bin/"
    sudo chmod +x "$UBUNTU_BASE/usr/bin/qemu-riscv64-static"
fi

# Update package lists
echo "Updating package lists..."
if sudo chroot "$UBUNTU_BASE" /usr/bin/test -x /usr/bin/apt-get; then
    sudo env DEBIAN_FRONTEND=noninteractive chroot "$UBUNTU_BASE" /usr/bin/apt-get update 2>&1 | head -20
else
    (cd "$UBUNTU_BASE" && sudo env DEBIAN_FRONTEND=noninteractive /usr/bin/qemu-riscv64-static -L . /usr/bin/apt-get update) 2>&1 | head -20
fi

# Install systemd
echo "Installing systemd..."
if sudo chroot "$UBUNTU_BASE" /usr/bin/test -x /usr/bin/apt-get; then
    sudo env DEBIAN_FRONTEND=noninteractive chroot "$UBUNTU_BASE" \
        /usr/bin/apt-get install -y --no-install-recommends \
        systemd systemd-sysv udev dbus networkd-dispatcher \
        iputils-ping netbase ca-certificates openssh-server 2>&1 | tee /tmp/systemd_install.log
else
    (cd "$UBUNTU_BASE" && sudo env DEBIAN_FRONTEND=noninteractive /usr/bin/qemu-riscv64-static \
        -L . /usr/bin/apt-get install -y --no-install-recommends \
        systemd systemd-sysv udev dbus networkd-dispatcher \
        iputils-ping netbase ca-certificates openssh-server) 2>&1 | tee /tmp/systemd_install.log
fi

# Setup init symlink
if [ -f lib/systemd/systemd ]; then
    sudo mkdir -p sbin
    if [ -L sbin/init ]; then
        sudo rm sbin/init
    fi
    sudo ln -sf /lib/systemd/systemd sbin/init
    echo "systemd installed"
else
    echo "Error: systemd installation failed"
    exit 1
fi

# Cleanup
sudo umount -l dev/random 2>/dev/null || true
sudo umount -l dev proc sys tmp 2>/dev/null || true
