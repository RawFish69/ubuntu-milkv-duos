# Milk-V Duo S Ubuntu Port

This is my custom Ubuntu 22.04 image build for the Milk-V Duo S. It replaces the stock Buildroot rootfs with a full Ubuntu Base system while keeping the official kernel.

## Features

- **Users**:
    - `root` (password: `milkv`)
    - `admin` (password: `69420`, sudo enabled) - **Created automatically** during build.
- **Networking**:
    - **USB-C**: RNDIS/ECM Gadget enabled. Connect to PC and SSH to `192.168.42.1`.
    - **Ethernet**: DHCP enabled via `systemd-networkd`.
- **Tools**: `ssh`, `gcc`, `make`, `git`, `nano`, `htop`, `fdisk`, `lsusb` included.

## Build

### Option 1: GitHub Actions (Recommended)
1. Go to the **Actions** tab in this repo.
2. Select **Manual Full Build** workflow.
3. Click **Run workflow**.
4. Download the artifact when complete.

### Option 2: Build Locally
**Prerequisites:** Ubuntu 20.04+ or WSL2.

**Steps:**
1.  **Setup**:
    ```bash
    bash install_dependencies.sh
    bash configure.sh
    ```

2.  **Build**:
    ```bash
    # 1. Compile Kernel/SDK
    sudo bash build_sdk.sh

    # 2. Prepare RootFS
    sudo bash install_systemd.sh
    sudo bash setup_users.sh

    # 3. Pack Image
    sudo bash build_image.sh
    ```

The final image will be in `duo-buildroot-sdk/out/`.

## Connecting

### USB-C (Gadget Ethernet)
Connect the board to your PC via the USB-C OTG port.

- **Board IP**: `192.168.42.1`
- **SSH**: `ssh admin@192.168.42.1` (password: `69420`)

### Serial Console
- **Baud**: 115200
- **Pinout**: TX->Pin 10, RX->Pin 8, GND->Pin 9.

## Current Status
**Stage:** Dev / Alpha
- **OS**: Ubuntu 22.04 Minimal
- **Kernel**: 5.10.4 (Custom Build)
- **USB Networking**: Working (RNDIS/ECM)
- **SSH**: Working (`admin` user)
- **Package Manager**: Working (`apt` repo configured)

## Known Issues
1.  **Partition Size**: Rootfs is small (~800MB) on first boot. You must manually resize it.
2.  **MAC Address**: Ethernet MAC is random on every boot (u-boot env issue).
3.  **Boot Logs**: Some systemd services fail (sysctl) due to missing kernel configs, but harmless.

## Testing & Setup Commands

### 1. Resize Root Partition (First Boot)
Expand the filesystem to fill your SD card:
```bash
# 1. Delete and recreate partition 3
sudo fdisk /dev/mmcblk0 <<EOF
d
3
n
3


w
EOF

# 2. Reboot to apply partition table
sudo reboot

# 3. Resize filesystem (after reboot)
sudo resize2fs /dev/mmcblk0p3
```

### 2. Verify Networking & USB Gadget
Running on the board:
```bash
# 1. Check if USB Ethernet interface exists
ip addr show usb0
# Expected: inet 192.168.42.1/24 ...

# 2. Check if g_ether module is loaded
lsmod | grep g_ether
# Expected: g_ether size ...

# 3. Check Kernel logs for Gadget ready
dmesg | grep "Ethernet Gadget"
# Expected: g_ether gadget: Ethernet Gadget, version ...

# 4. Check the fix service status (if usb0 is missing)
systemctl status usb-gadget-fix
# Should show "Active: active (exited)" and logs of "modprobe g_ether"

# 5. Manual Force Fix (if all else fails)
sudo /usr/local/bin/fix-usb-gadget.sh
```

### 3. Verify SSH & User
```bash
# 1. Check SSH Service Status
systemctl status ssh
# Expected: Active: active (running)

# 2. Verify 'admin' user exists
id admin
# Expected: uid=1000(admin) gid=1000(admin) groups=1000(admin),27(sudo)...

# 3. Test SSH from Host PC (e.g., your laptop)
ssh admin@192.168.42.1
# Password: 69420
```

### 4. Motor Driver Test
Compile and run the motor driver test code:
```bash
cd ~/testing
gcc -o motor_test motor_driver.c -lwiringx
sudo ./motor_test
```
