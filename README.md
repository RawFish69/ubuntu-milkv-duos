# Ubuntu Base Port for Milk-V Duo S

Port Ubuntu Base 22.04 to Milk-V Duo S (SG2000/CV1813H) by replacing Buildroot rootfs while keeping official kernel and bootloader. 

## Automated Build

**GitHub Actions** can automatically build the image.

1. **Fork** this repository.
2. Navigate to the **Actions** tab in your fork.
3. Select **Build Milk-V Duo S Image** and click **Run workflow**.
4. Once completed, download the `milkv-duos-ubuntu-image` from the **Artifacts** section.

## Local Build

If you need to build locally, we provide a `configure.sh` script to automate setup.

**Prerequisites:** Ubuntu 20.04/22.04 or WSL2.

### 1. Setup Environment
```bash
# Install dependencies
bash install_dependencies.sh

# Clone SDK, patch config, and download Ubuntu Base
bash configure.sh
```

### 2. Build
```bash
# Build the SDK (Compiles kernel/uboot - takes time)
sudo bash build_sdk.sh

# Prepare Ubuntu rootfs
sudo bash install_systemd.sh

# Create final SD card image
sudo bash build_image.sh
```

**Custom image size:**
```bash
IMAGE_SIZE_MB=4096 sudo bash build_image.sh
```

## Connecting to the Board

### Serial Console (Recommended for First Boot)

Connect a **3.3V** USB-to-TTL adapter to **UART0** on Header J3:

| Duo S Pin | Name | Adapter Pin |
|-----------|------|-------------|
| Pin 8 | A16 (UART0_TX) | RX |
| Pin 10 | A17 (UART0_RX) | TX |
| Pin 9 | GND | GND |

**Settings:** 115200 baud, 8N1, no flow control

⚠️ **Use 3.3V adapter only** - 5V will damage the board!

On Windows, use PuTTY or similar. On Linux/WSL:
```bash
screen /dev/ttyUSB0 115200
# or
minicom -D /dev/ttyUSB0 -b 115200
```

### SSH via USB RNDIS (USB Ethernet Gadget)

The board presents itself as a USB network device when connected via USB-C.

| Setting | Value |
|---------|-------|
| Board IP | `192.168.42.1` |
| Host IP | `192.168.42.x` (DHCP assigned) |
| Username | `root` |
| Password | `milkv` |

**Windows Setup:**

1. Connect board via USB-C
2. Windows should detect "RNDIS Gadget" network adapter
3. The adapter should get IP `192.168.42.x` automatically
4. SSH to the board:
   ```
   ssh root@192.168.42.1
   ```

**Linux/WSL Setup:**

```bash
# Check if usb0 interface appeared
ip addr show usb0

# If no IP, set manually:
sudo ip addr add 192.168.42.2/24 dev usb0
sudo ip link set usb0 up

# SSH to board
ssh root@192.168.42.1
```

**WSL2 Note:** USB passthrough to WSL2 requires [usbipd-win](https://github.com/dorssel/usbipd-win). Alternatively, SSH from Windows PowerShell instead.

### Internet Access for the Board

The board can access the internet through your host PC:

**On Linux Host:**
```bash
# Enable IP forwarding
sudo sysctl -w net.ipv4.ip_forward=1

# NAT the board's traffic (replace eth0 with your internet interface)
sudo iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o eth0 -j MASQUERADE
```

**On the Board:**
```bash
# Add default route through host
ip route add default via 192.168.42.2
```

## Troubleshooting

**Board not booting:**
- Connect serial console to see boot messages
- Verify boot files: `fip.bin` and `boot.sd` must both be in partition 1
- Try flashing stock SDK image first to verify hardware works

**No output on serial console:**
- Check TX/RX aren't swapped
- Verify baud rate is 115200
- Ensure ground is connected

**USB RNDIS not working:**
- Check USB cable supports data (not charge-only)
- On Windows: Check Device Manager for RNDIS adapter
- Kernel modules must be present in `/lib/modules`

**Script errors:**
- Ensure `qemu-user-static` installed
- Check disk space
- Verify Ubuntu Base extracted correctly

**Loop device busy error:**
```
losetup: failed to set up loop device: Device or resource busy
```
Fix by detaching loop devices:
```bash
sudo umount /mnt/sdcard_rootfs 2>/dev/null
sudo umount /mnt/sdcard_boot 2>/dev/null
sudo losetup -D  # Detach all loop devices
```
Then run `build_image.sh` again.

**Rootfs partition too small (manual resize after flash):**
If you've already flashed and booted, resize on the device:
```bash
# 1. Resize partition (replace p3/p4 with your rootfs partition)
fdisk /dev/mmcblk0
# Type: d, 3 (delete partition 3)
# Type: n, 3 (create new partition, same start sector, use all space)
# Type: w (write)

# 2. Reboot, then resize filesystem
reboot
resize2fs /dev/mmcblk0p3
```

## Testing Stock Image (Debug Boot Issues)

If the board won't boot, first test with stock Buildroot:

```bash
# Rebuild SDK (creates fresh stock image)
cd duo-buildroot-sdk
./build.sh milkv-duos-sd

# Flash the NEW image from out/ WITHOUT running build_image.sh
# The stock image should be ~150-200MB
```

If stock boots: proceed with Ubuntu steps.  
If stock doesn't boot: check SD card, serial console, or try different USB cable.

## Quick Reference

| Item | Value |
|------|-------|
| Board IP (USB) | `192.168.42.1` |
| SSH Login | `root` / `milkv` |
| Serial Baud | `115200` |
| Serial Device | `ttyS0` |
| UART0 TX | Pin 8 (A16) → Adapter RX |
| UART0 RX | Pin 10 (A17) ← Adapter TX |
| GND | Pin 9 |
