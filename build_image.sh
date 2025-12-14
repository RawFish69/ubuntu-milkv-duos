#!/bin/bash
# Copy Ubuntu Base to SD card image

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Auto-detect paths
UBUNTU_BASE="$SCRIPT_DIR/ubuntu_base"
DUO_SDK_DIR="$SCRIPT_DIR/duo-buildroot-sdk"

# Find the latest SDK image (ignore stock backup to ensure we have fresh kernel)
# We exclude *-ubuntu.img and *-stock.img to find the fresh build output
IMG_SOURCE=$(find "$DUO_SDK_DIR/out" \( -name "milkv-duos-sd-*.img" -o -name "milkv-duos-sd_*.img" \) -not -name "*-stock.img" -not -name "*-ubuntu.img" -type f 2>/dev/null | sort -r | head -1)

if [ -n "$IMG_SOURCE" ] && [ -f "$IMG_SOURCE" ]; then
    echo "Found latest SDK image: $IMG_SOURCE"
    IMG_FILE="${IMG_SOURCE%.img}-ubuntu.img"
    echo "Creating working copy: $IMG_FILE"
    cp "$IMG_SOURCE" "$IMG_FILE"
else
    echo "Error: Image file not found in $DUO_SDK_DIR/out/"
    echo "Build the SDK first: sudo bash build_sdk.sh"
    exit 1
fi

# Locate kernel modules dynamically to handle version differences
echo "Locating kernel modules..."

# Method 1: Find by modules.order (most reliable marker of a module dir)
# We look for a directory inside the SDK containing modules.order
MODULE_DIR_MARKER=$(find "$DUO_SDK_DIR" -name "modules.order" | grep "/lib/modules/" | head -n 1)

if [ -n "$MODULE_DIR_MARKER" ]; then
    # dirname of .../lib/modules/5.10.4-tag-/modules.order is .../lib/modules/5.10.4-tag-
    FOUND_MOD_DIR=$(dirname "$MODULE_DIR_MARKER")
    KERNEL_VERSION=$(basename "$FOUND_MOD_DIR")
    KERNEL_MODULES_SRC="$(dirname "$FOUND_MOD_DIR")" # Parent: .../lib/modules
    
    echo "Found modules at: $FOUND_MOD_DIR"
    echo "Detected Kernel Version: $KERNEL_VERSION"
else
    echo "Error: Could not locate kernel modules in SDK!"
    echo "Checked: $DUO_SDK_DIR"
    echo "Please ensure you have run 'build_sdk.sh' successfully."
    exit 1
fi

SD_MOUNT="/mnt/sdcard_rootfs"
BOOT_MOUNT="/mnt/sdcard_boot"
LOOP_DEV=""

cleanup() {
    echo "Cleaning up..."
    cd "$SCRIPT_DIR"
    
    # Unmount Ubuntu Base bind mounts
    sudo umount -l "$UBUNTU_BASE/dev/random" 2>/dev/null || true
    sudo umount -l "$UBUNTU_BASE/dev" 2>/dev/null || true
    sudo umount -l "$UBUNTU_BASE/proc" 2>/dev/null || true
    sudo umount -l "$UBUNTU_BASE/sys" 2>/dev/null || true
    sudo umount -l "$UBUNTU_BASE/tmp" 2>/dev/null || true
    
    # Unmount image partitions
    sudo umount -l "$SD_MOUNT" 2>/dev/null || true
    sudo umount -l "$BOOT_MOUNT" 2>/dev/null || true
    
    # Detach loop device
    if [ -n "$LOOP_DEV" ]; then
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
}

trap cleanup EXIT

echo "Phase 3: Ubuntu Base Setup"
echo "Image: $IMG_FILE"
echo ""

# Setup loop device - find a free one
echo "Setting up loop device..."
LOOP_DEV=$(sudo losetup -f --show -P "$IMG_FILE")
echo "Using loop device: $LOOP_DEV"

# Show current partition layout
echo ""
echo "Current partition layout:"
sudo fdisk -l "$LOOP_DEV"
echo ""

# Find the rootfs partition number (the last ext4 partition)
ROOT_PART_NUM=""
for i in 4 3 2; do
    if [ -b "${LOOP_DEV}p${i}" ]; then
        FSTYPE=$(sudo blkid -o value -s TYPE "${LOOP_DEV}p${i}" 2>/dev/null || echo "")
        if [ "$FSTYPE" = "ext4" ] || [ "$FSTYPE" = "ext2" ] || [ "$FSTYPE" = "ext3" ]; then
            ROOT_PART_NUM="$i"
            echo "Found rootfs partition: p${ROOT_PART_NUM} (type: $FSTYPE)"
            break
        fi
    fi
done

if [ -z "$ROOT_PART_NUM" ]; then
    echo "Error: Could not find rootfs partition (ext2/3/4)"
    echo "Available partitions:"
    lsblk "$LOOP_DEV"
    exit 1
fi

echo ""
lsblk "$LOOP_DEV"
echo ""

# Expand the rootfs partition if it's too small for our expanded Ubuntu base
echo "Checking rootfs partition size..."
CURRENT_SIZE=$(sudo blockdev --getsize64 "${LOOP_DEV}p${ROOT_PART_NUM}")
CURRENT_SIZE_MB=$((CURRENT_SIZE / 1024 / 1024))
echo "Current rootfs size: ${CURRENT_SIZE_MB}MB"

# Our expanded Ubuntu base needs ~1.2GB, so expand to 2GB to be safe
TARGET_SIZE_MB=2048

if [ "$CURRENT_SIZE_MB" -lt "$TARGET_SIZE_MB" ]; then
    echo "Rootfs partition is too small (${CURRENT_SIZE_MB}MB < ${TARGET_SIZE_MB}MB)"
    echo "Expanding rootfs partition..."
    
    # First, unmount if mounted
    sudo umount "${LOOP_DEV}p${ROOT_PART_NUM}" 2>/dev/null || true
    
    # Get partition start sector
    PART_START=$(sudo fdisk -l "$LOOP_DEV" | grep "${LOOP_DEV}p${ROOT_PART_NUM}" | awk '{print $2}')
    echo "Partition start sector: $PART_START"
    
    # Calculate new end sector for 2GB partition (2048MB * 1024 * 1024 / 512 bytes per sector)
    NEW_SIZE_SECTORS=$((TARGET_SIZE_MB * 1024 * 1024 / 512))
    NEW_END_SECTOR=$((PART_START + NEW_SIZE_SECTORS - 1))
    
    # Extend the image file to accommodate larger partition
    IMAGE_SIZE=$(stat -c%s "$IMG_FILE")
    NEW_IMAGE_SIZE=$((PART_START * 512 + NEW_SIZE_SECTORS * 512))
    if [ "$NEW_IMAGE_SIZE" -gt "$IMAGE_SIZE" ]; then
        echo "Extending image file to accommodate larger partition..."
        sudo truncate -s "$NEW_IMAGE_SIZE" "$IMG_FILE"
        
        # Refresh loop device to see new size
        sudo losetup -d "$LOOP_DEV"
        LOOP_DEV=$(sudo losetup -f --show -P "$IMG_FILE")
        echo "Re-attached loop device: $LOOP_DEV"
    fi
    
    # Delete and recreate the rootfs partition with new size
    echo "Recreating partition ${ROOT_PART_NUM} with larger size..."
    sudo bash -c "fdisk $LOOP_DEV << EOF
d
${ROOT_PART_NUM}
n
p
${ROOT_PART_NUM}
${PART_START}
${NEW_END_SECTOR}
w
EOF" || echo "fdisk completed (warnings are normal)"
    
    # Re-read partition table
    sudo partprobe "$LOOP_DEV" || true
    sleep 2
    
    # Force kernel to re-read partitions
    sudo losetup -d "$LOOP_DEV"
    LOOP_DEV=$(sudo losetup -f --show -P "$IMG_FILE")
    echo "Re-attached loop device after partition resize: $LOOP_DEV"
    sleep 1
    
    # Resize the ext4 filesystem to fill the partition
    echo "Resizing ext4 filesystem..."
    sudo e2fsck -f -y "${LOOP_DEV}p${ROOT_PART_NUM}" || true
    sudo resize2fs "${LOOP_DEV}p${ROOT_PART_NUM}" || true
    
    echo "Partition expanded successfully!"
    sudo fdisk -l "$LOOP_DEV"
else
    echo "Rootfs partition size is adequate (${CURRENT_SIZE_MB}MB)"
fi

# Mount rootfs partition
echo "Mounting rootfs partition..."
sudo mkdir -p "$SD_MOUNT"
sudo mount "${LOOP_DEV}p${ROOT_PART_NUM}" "$SD_MOUNT" || exit 1
echo "Mounted rootfs (p${ROOT_PART_NUM}) at $SD_MOUNT"

# Setup Ubuntu Base for chroot
cd "$UBUNTU_BASE"
sudo mkdir -p dev proc sys tmp etc/apt

# Mount bind mounts for chroot
sudo mount --bind /dev dev
sudo mount --bind /proc proc
sudo mount --bind /sys sys
sudo mount -t tmpfs tmpfs tmp
sudo chmod 1777 tmp

sudo bash -c 'echo "nameserver 8.8.8.8" > etc/resolv.conf'

if [ ! -f etc/apt/sources.list ]; then
    sudo bash -c 'cat > etc/apt/sources.list << "EOF"
deb http://ports.ubuntu.com/ubuntu-ports jammy main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-updates main restricted universe multiverse
deb http://ports.ubuntu.com/ubuntu-ports jammy-security main restricted universe multiverse
EOF'
fi

# Copy kernel modules
# We found KERNEL_MODULES_SRC to be the parent of the version dir (e.g. .../lib/modules)
if [ -d "$KERNEL_MODULES_SRC" ]; then
    echo "Copying kernel modules from $KERNEL_MODULES_SRC..."
    sudo mkdir -p "$UBUNTU_BASE/lib/modules"
    # Copy all version directories (e.g. 5.10.4-tag-) into /lib/modules
    sudo cp -r "$KERNEL_MODULES_SRC"/* "$UBUNTU_BASE/lib/modules/" 2>/dev/null || true
    
    # Verify copy
    if [ -d "$UBUNTU_BASE/lib/modules/$KERNEL_VERSION" ]; then
        echo "✓ Modules for $KERNEL_VERSION installed successfully."
        
        # HACK: Fix for version mismatch (uname -r is 5.10.4-tag-, modules are 5.10.4)
        # We blindly create a symlink from 5.10.4-tag- to 5.10.4 if it doesn't exist
        if [ ! -d "$UBUNTU_BASE/lib/modules/${KERNEL_VERSION}-tag-" ]; then
            echo "Creating symlink for ${KERNEL_VERSION}-tag- -> ${KERNEL_VERSION}..."
            ln -sf "$KERNEL_VERSION" "$UBUNTU_BASE/lib/modules/${KERNEL_VERSION}-tag-"
        fi
    else
        echo "Error: Failed to install modules for $KERNEL_VERSION"
        ls -la "$UBUNTU_BASE/lib/modules"
        exit 1
    fi
fi

# Run the user setup script to create admin user and setup SSH
if [ -f "$SCRIPT_DIR/setup_users.sh" ]; then
    echo "Running setup_users.sh..."
    # Skip cleanup in setup_users.sh because we need mounts for subsequent operations
    sudo SKIP_CLEANUP=true bash "$SCRIPT_DIR/setup_users.sh"
else
    echo "Error: setup_users.sh not found!"
    exit 1
fi

# Create fstab
sudo bash -c "cat > $UBUNTU_BASE/etc/fstab << EOF
/dev/mmcblk0p${ROOT_PART_NUM}  /               ext4    defaults,noatime  0       1
tmpfs           /tmp            tmpfs   defaults          0       0
tmpfs           /var/tmp        tmpfs   defaults          0       0
EOF"

# Set root password and configure system
echo "Configuring Ubuntu system..."
sudo chroot "$UBUNTU_BASE" /usr/bin/qemu-riscv64-static /bin/sh -c "echo 'root:milkv' | chpasswd" 2>/dev/null || true

# Set hostname
echo "milkv-duos" | sudo tee "$UBUNTU_BASE/etc/hostname" > /dev/null

# Configure g_ether module auto-loading
echo "Configuring g_ether module auto-loading..."
sudo bash -c 'echo "g_ether" > "$UBUNTU_BASE/etc/modules-load.d/g_ether.conf"'

# Configure network for RNDIS (USB Ethernet gadget)
sudo mkdir -p "$UBUNTU_BASE/etc/systemd/network"
sudo bash -c 'cat > "$UBUNTU_BASE/etc/systemd/network/30-usb0.network" << EOF
[Match]
Name=usb0

[Network]
Address=192.168.42.1/24
DHCPServer=yes

[DHCPServer]
PoolOffset=100
PoolSize=20
EOF'

# Enable networkd
sudo mkdir -p "$UBUNTU_BASE/etc/systemd/system/multi-user.target.wants"
sudo ln -sf /lib/systemd/system/systemd-networkd.service "$UBUNTU_BASE/etc/systemd/system/multi-user.target.wants/" 2>/dev/null || true

# Create getty service for serial console
sudo mkdir -p "$UBUNTU_BASE/etc/systemd/system/getty.target.wants"
sudo ln -sf /lib/systemd/system/serial-getty@.service "$UBUNTU_BASE/etc/systemd/system/getty.target.wants/serial-getty@ttyS0.service" 2>/dev/null || true

# Configure SSH for root login
echo "Configuring SSH server..."
sudo mkdir -p "$UBUNTU_BASE/etc/ssh"
if [ -f "$UBUNTU_BASE/etc/ssh/sshd_config" ]; then
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin yes/' "$UBUNTU_BASE/etc/ssh/sshd_config"
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$UBUNTU_BASE/etc/ssh/sshd_config"
else
    sudo bash -c "cat > $UBUNTU_BASE/etc/ssh/sshd_config << 'SSHEOF'
Port 22
PermitRootLogin yes
PasswordAuthentication yes
PubkeyAuthentication yes
UsePAM yes
X11Forwarding no
PrintMotd no
AcceptEnv LANG LC_*
Subsystem sftp /usr/lib/openssh/sftp-server
SSHEOF"
fi

# Enable SSH service
if [ -f "$UBUNTU_BASE/lib/systemd/system/ssh.service" ]; then
    sudo ln -sf /lib/systemd/system/ssh.service "$UBUNTU_BASE/etc/systemd/system/multi-user.target.wants/" 2>/dev/null || true
fi
if [ -f "$UBUNTU_BASE/lib/systemd/system/sshd.service" ]; then
    sudo ln -sf /lib/systemd/system/sshd.service "$UBUNTU_BASE/etc/systemd/system/multi-user.target.wants/" 2>/dev/null || true
fi

# Setup SSH directories
sudo mkdir -p "$UBUNTU_BASE/root/.ssh"
sudo chmod 700 "$UBUNTU_BASE/root/.ssh"

# Unmount chroot bind mounts before copying
cd "$SCRIPT_DIR"
sudo umount -l "$UBUNTU_BASE/tmp" 2>/dev/null || true
sudo umount -l "$UBUNTU_BASE/sys" 2>/dev/null || true
sudo umount -l "$UBUNTU_BASE/proc" 2>/dev/null || true
sudo umount -l "$UBUNTU_BASE/dev" 2>/dev/null || true

# Copy Ubuntu Base to image
echo "Copying Ubuntu Base to image..."
sudo rm -rf "$SD_MOUNT"/*
sudo rsync -aAX "$UBUNTU_BASE/" "$SD_MOUNT/" --exclude=proc --exclude=sys --exclude=sysroot

# Create essential device nodes in the rootfs
echo "Creating essential device nodes..."
sudo mkdir -p "$SD_MOUNT/dev"
sudo mknod -m 622 "$SD_MOUNT/dev/console" c 5 1 2>/dev/null || true
sudo mknod -m 666 "$SD_MOUNT/dev/null" c 1 3 2>/dev/null || true
sudo mknod -m 666 "$SD_MOUNT/dev/zero" c 1 5 2>/dev/null || true
sudo mknod -m 666 "$SD_MOUNT/dev/ptmx" c 5 2 2>/dev/null || true
sudo mknod -m 666 "$SD_MOUNT/dev/tty" c 5 0 2>/dev/null || true
sudo mknod -m 444 "$SD_MOUNT/dev/random" c 1 8 2>/dev/null || true
sudo mknod -m 444 "$SD_MOUNT/dev/urandom" c 1 9 2>/dev/null || true
sudo mkdir -p "$SD_MOUNT/dev/pts"
sudo mkdir -p "$SD_MOUNT/dev/shm"

# Create symlinks
sudo ln -sf /proc/self/fd "$SD_MOUNT/dev/fd" 2>/dev/null || true
sudo ln -sf /proc/self/fd/0 "$SD_MOUNT/dev/stdin" 2>/dev/null || true
sudo ln -sf /proc/self/fd/1 "$SD_MOUNT/dev/stdout" 2>/dev/null || true
sudo ln -sf /proc/self/fd/2 "$SD_MOUNT/dev/stderr" 2>/dev/null || true

# Ensure init exists (systemd should be at /sbin/init)
if [ ! -e "$SD_MOUNT/sbin/init" ] && [ -e "$SD_MOUNT/lib/systemd/systemd" ]; then
    sudo ln -sf /lib/systemd/systemd "$SD_MOUNT/sbin/init"
fi

# Unmount rootfs
echo "Syncing and unmounting rootfs..."
sudo sync
sudo umount "$SD_MOUNT"

# Verify boot partition has required files (but don't modify it!)
# The stock SDK image already has correct boot.sd and fip.bin
echo "Verifying boot partition (read-only check)..."
sudo mkdir -p "$BOOT_MOUNT"



# Final sync and cleanup
sudo sync

# Detach loop device
sudo losetup -d "$LOOP_DEV"
LOOP_DEV=""

echo ""
echo "=========================================="
echo "✓ Image build complete!"
echo "=========================================="
echo "Image: $IMG_FILE"
echo ""
echo "Flash with:"
echo "  On Windows: Use BalenaEtcher"
echo "  On Linux:   sudo dd if=$IMG_FILE of=/dev/sdX bs=4M status=progress"
echo ""
echo "After booting:"
echo "  Serial console: 115200 baud on ttyS0"
echo "  SSH: ssh root@192.168.42.1 (via USB RNDIS)"
echo "  Password: milkv"
echo ""
echo "NOTE: Rootfs partition is small (~768MB). Resize after boot:"
echo "  fdisk /dev/mmcblk0  # delete & recreate partition ${ROOT_PART_NUM}"
echo "  reboot"
echo "  resize2fs /dev/mmcblk0p${ROOT_PART_NUM}"
echo ""
