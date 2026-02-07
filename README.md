# Ubuntu Base Port for Milk-V Duo S

Port Ubuntu Base 22.04 to Milk-V Duo S (SG2000/CV1813H) by replacing Buildroot rootfs while keeping the official kernel and bootloader.

> This was made for a robotics research project on my other GitHub account but that repo is closed source at the moment. **Use this repo at your own risk.**

This repository builds a custom Ubuntu 22.04 (ARM64) image for the Milk-V Duo S using the **duo-buildroot-sdk-v2** SDK. Set the board hardware switch to ARM and use the ARM-compatible SDK v2 target; chroot operations use `qemu-aarch64-static`.

## Features

- **Users** (created automatically during build):
  - `root` (password: `milkv`)
  - `admin` (password: `69420`, sudo enabled)
  - `ubuntu` (password: `milkv`, sudo enabled)
- **Networking**:
  - **USB-C**: RNDIS/ECM gadget. Connect to PC and SSH to `192.168.42.1`.
  - **Ethernet**: DHCP via `systemd-networkd`.
- **Tools**: `ssh`, `gcc`, `make`, `git`, `nano`, `htop`, `fdisk`, `lsusb` included.
- **Ready LED**: Blue LED blinks when USB gadget has an address (configurable via `/etc/default/led-ready`).

## Automated Build (GitHub Actions)

**GitHub Actions** in this repo can run the full pipeline or individual stages.

1. Open the **Actions** tab in this repository.
2. Select **Build Milk-V Duo S Ubuntu Image** (or **Manual Full Build**).
3. Click **Run workflow**, choose build type (e.g. `full` for complete build) and cleanup level.
4. When the run finishes, download the artifact from the workflow summary.

## Local Build

**Prerequisites:** Ubuntu 20.04/22.04 or WSL2.

### 1. Setup environment

```bash
# Install dependencies
bash install_dependencies.sh

# Clone SDK v2, patch config, and download Ubuntu Base
bash configure.sh
```

### 2. Build

```bash
# Build the SDK (compiles kernel/uboot — takes time)
sudo bash build_sdk.sh

# Prepare Ubuntu rootfs
sudo bash install_systemd.sh
sudo bash setup_users.sh

# Create final SD card image
sudo bash build_image.sh
```

**Custom image size:**

```bash
TARGET_SIZE_MB=4096 sudo bash build_image.sh
```

**Notes:**

- You do **not** need to run `patch_sdk.sh` manually; `configure.sh` and `build_sdk.sh` run it automatically.
- If your system has only `python3`, the repo provides `tools/python` and `build_sdk.sh` adds it to PATH.
- On ARM64, PQTool is skipped by default. To enable: `export BUILD_PQTOOL=1` before `build_sdk.sh`.
- **Wi-Fi DTS patch:** To disable: `export ENABLE_WIFI_PATCH=0`. To add extra properties:  
  `export WIFI_DTS_PROPS='reset-gpios = <&gpio 3 2 GPIO_ACTIVE_LOW>;'`

The final image is written under `duo-buildroot-sdk-v2/out/` (e.g. `*-ubuntu.img`).

## Connecting to the Board

### Serial console (UART0)

Use a USB-to-TTL adapter (3.3 V logic).

- **TX** → Pin 10 (Rx)
- **RX** → Pin 8 (Tx)
- **GND** → Pin 9
- **Baud:** 115200

### SSH (USB RNDIS)

Connect via USB-C. Board IP is `192.168.42.1`.

**Users:**

- `root` (password: `milkv`)
- `admin` (password: `69420`, sudo enabled)
- `ubuntu` (password: `milkv`, sudo enabled)

**Windows:** RNDIS driver should auto-install. SSH to `root@192.168.42.1` or `admin@192.168.42.1`.

**Linux/WSL:**

```bash
sudo ip addr add 192.168.42.2/24 dev usb0   # Set host IP if needed
ssh root@192.168.42.1
# or
ssh admin@192.168.42.1
```

**WSL2:** USB passthrough to WSL2 needs [usbipd-win](https://github.com/dorssel/usbipd-win). Alternatively, use SSH from Windows PowerShell.

If the board shows `NO-CARRIER`, the host has not enumerated the USB gadget yet — use a data-capable USB-C cable and the OTG port (avoid hubs).

### Internet access for the board

The board can use the host’s internet:

**On Linux host:**

```bash
sudo sysctl -w net.ipv4.ip_forward=1
sudo iptables -t nat -A POSTROUTING -s 192.168.42.0/24 -o eth0 -j MASQUERADE
```

**On the board:**

```bash
ip route add default via 192.168.42.2
```

## Troubleshooting

**Board not booting:**

- Use serial console to see boot messages.
- Ensure boot files `fip.bin` and `boot.sd` are in partition 1.
- Try flashing the stock SDK image first to confirm hardware.

**No serial output:**

- Check TX/RX are not swapped, baud is 115200, and GND is connected.

**USB RNDIS not working:**

- Use a data-capable cable; on Windows check Device Manager for the RNDIS adapter.
- Ensure kernel modules are present in `/lib/modules`.

**SSH not working:**

- Check: `systemctl status ssh`, `id admin` / `id ubuntu`, `ip addr show usb0`.
- Try: `sudo /usr/local/bin/fix-usb-gadget.sh`

**Script errors:**

- Install `qemu-user-static`, check disk space, and that Ubuntu Base was extracted correctly.

**Loop device busy:**

```text
losetup: failed to set up loop device: Device or resource busy
```

Detach and retry:

```bash
sudo umount /mnt/sdcard_rootfs 2>/dev/null
sudo umount /mnt/sdcard_boot 2>/dev/null
sudo losetup -D
```

Then run `build_image.sh` again.

**Rootfs partition too small (resize after flash):**

If the board has already booted from the flashed image:

```bash
fdisk /dev/mmcblk0
# d, 3 — delete partition 3
# n, 3 — new partition 3, same start sector, use rest of disk
# w — write
reboot
resize2fs /dev/mmcblk0p3
```

## Testing stock image (debug boot)

If the board does not boot, test with stock Buildroot first:

```bash
cd duo-buildroot-sdk-v2
./build.sh milkv-duos-glibc-arm64-sd
# Flash the new image from out/ without running build_image.sh
```

If stock boots, continue with the Ubuntu steps. If not, check SD card, serial connection, and USB cable.

## Testing and setup commands (on the board)

**USB gadget:**

```bash
systemctl status usb-gadget --no-pager
ip addr show usb0
networkctl status usb0
```

**LED ready service:**

```bash
systemctl status led-ready --no-pager
```

**Serial console (on host):**

```bash
screen /dev/ttyUSB0 115200
```

## Quick reference

| Item            | Value              |
|----------------|--------------------|
| Board IP (USB) | `192.168.42.1`     |
| SSH (root)     | `root` / `milkv`   |
| SSH (admin)    | `admin` / `69420`  |
| SSH (ubuntu)   | `ubuntu` / `milkv` |
| Serial baud    | `115200`           |
| Serial device  | `ttyS0`            |
| UART0 TX       | Pin 8 (A16) → adapter RX |
| UART0 RX       | Pin 10 (A17) ← adapter TX |
| GND            | Pin 9              |

## Future work

I may sync more features from the other repository when possible, for example:

- **WiringX** — GPIO library support.
- **ROS2** — Robot Operating System 2 integration.
- Other improvements as they mature.

## License and disclaimer

Use this repository and the generated images at your own risk. See the project’s license terms for details.
