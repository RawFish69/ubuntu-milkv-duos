#!/bin/bash
# Setup users and enable SSH access for Ubuntu rootfs
# This script configures root login and SSH service

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UBUNTU_BASE="$SCRIPT_DIR/ubuntu_base"

if [ ! -d "$UBUNTU_BASE" ]; then
    echo "Error: Ubuntu Base directory not found: $UBUNTU_BASE"
    exit 1
fi

echo "==========================================="
echo "Configuring Users and SSH Access"
echo "==========================================="

# Setup bind mounts for chroot
cd "$UBUNTU_BASE"
sudo mkdir -p dev proc sys tmp

if ! mountpoint -q dev 2>/dev/null; then
    sudo mount --bind /dev dev
fi
if ! mountpoint -q proc 2>/dev/null; then
    sudo mount --bind /proc proc
fi
if ! mountpoint -q sys 2>/dev/null; then
    sudo mount --bind /sys sys
fi
if ! mountpoint -q tmp 2>/dev/null; then
    sudo mount -t tmpfs tmpfs tmp
    sudo chmod 1777 tmp
fi

# Configure SSH to allow root login
echo "Configuring SSH for root login..."
sudo mkdir -p "$UBUNTU_BASE/etc/ssh"

# Enable root login via SSH
if [ -f "$UBUNTU_BASE/etc/ssh/sshd_config" ]; then
    # Modify existing config
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$UBUNTU_BASE/etc/ssh/sshd_config"
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$UBUNTU_BASE/etc/ssh/sshd_config"
else
    # Create basic config if it doesn't exist
    sudo bash -c "cat > $UBUNTU_BASE/etc/ssh/sshd_config << 'EOF'
# SSH Server Configuration for Milk-V Duo S
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
EOF"
fi

# Set root password
    sudo chroot "$UBUNTU_BASE" /usr/bin/qemu-riscv64-static /bin/sh -c "echo 'root:milkv' | chpasswd"
# Removed incorrect fi

# Create 'admin' user
echo "Creating user 'admin'..."
# Check if user exists (POSIX compliant redirection)
if ! sudo chroot "$UBUNTU_BASE" /usr/bin/qemu-riscv64-static /bin/sh -c "id -u admin >/dev/null 2>&1"; then
    sudo chroot "$UBUNTU_BASE" /usr/bin/qemu-riscv64-static /bin/sh -c "useradd -m -s /bin/bash admin"
fi

# Set password using usermod -p with hash to avoid CHPASSWD/PAM issues in chroot
# Hash for '69420': $6$D1mL14pctsEZqZwr$apG.RoLxZdHtMK7reySwMpnVPU2u6eWQDaPjlziLePnvkSD6c/ALj32jekRMJg5llRz1odkA5PrRAbCuPr1rr1
ADMIN_HASH='\$6\$D1mL14pctsEZqZwr\$apG.RoLxZdHtMK7reySwMpnVPU2u6eWQDaPjlziLePnvkSD6c/ALj32jekRMJg5llRz1odkA5PrRAbCuPr1rr1'
sudo chroot "$UBUNTU_BASE" /usr/bin/qemu-riscv64-static /bin/sh -c "usermod -p '$ADMIN_HASH' admin"
sudo chroot "$UBUNTU_BASE" /usr/bin/qemu-riscv64-static /bin/sh -c "usermod -aG sudo admin"

# Enable SSH service
echo "Enabling SSH service..."
sudo mkdir -p "$UBUNTU_BASE/etc/systemd/system/multi-user.target.wants"
if [ -f "$UBUNTU_BASE/lib/systemd/system/ssh.service" ]; then
    sudo ln -sf /lib/systemd/system/ssh.service "$UBUNTU_BASE/etc/systemd/system/multi-user.target.wants/" 2>/dev/null || true
fi
if [ -f "$UBUNTU_BASE/lib/systemd/system/sshd.service" ]; then
    sudo ln -sf /lib/systemd/system/sshd.service "$UBUNTU_BASE/etc/systemd/system/multi-user.target.wants/" 2>/dev/null || true
fi

# Create .ssh directory for root with proper permissions
echo "Setting up SSH directories..."
sudo mkdir -p "$UBUNTU_BASE/root/.ssh"
sudo chmod 700 "$UBUNTU_BASE/root/.ssh"

# Create a helpful message of the day
sudo bash -c "cat > $UBUNTU_BASE/etc/motd << 'EOF'
╔════════════════════════════════════════════════════════╗
║         Welcome to Ubuntu 22.04 on Milk-V Duo S        ║
╚════════════════════════════════════════════════════════╝

System Information:
  - Ubuntu 22.04 LTS (Jammy Jellyfish) for RISC-V
  - Kernel: Linux 5.10 (custom build)
  - USB-C Networking: Enabled via USB Gadget

Available Tools:
  - SSH Server: Enabled (current connection)
  - Network: ifconfig, ip, ethtool, traceroute
  - Editors: nano, vim
  - Development: gcc, g++, cmake, git, make
  - USB Tools: lsusb, usb-devices

Quick Start:
  - Check network: ifconfig or ip addr
  - Update packages: apt update && apt upgrade
  - Resize rootfs: See README.md for instructions

Documentation: /root/README.md (if available)
Support: https://github.com/milkv-duo

EOF"

# Cleanup bind mounts (only if not skipped)
if [ "$SKIP_CLEANUP" != "true" ]; then
    cd "$SCRIPT_DIR"
    sudo umount -l "$UBUNTU_BASE/tmp" 2>/dev/null || true
    sudo umount -l "$UBUNTU_BASE/sys" 2>/dev/null || true
    sudo umount -l "$UBUNTU_BASE/proc" 2>/dev/null || true
    sudo umount -l "$UBUNTU_BASE/dev" 2>/dev/null || true
else
    echo "Skipping cleanup (handled by caller)..."
fi

echo ""
echo "✓ User and SSH configuration complete!"
echo "  Root password: milkv"
echo "  SSH: Enabled on boot"
echo ""
