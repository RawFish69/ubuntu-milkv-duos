#!/bin/bash
# configure.sh
# Automated setup for Milk-V Duo S build environment
# - Clones SDK
# - Patches kernel config
# - Downloads Ubuntu Base

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="$SCRIPT_DIR/duo-buildroot-sdk-v2"
UBUNTU_DIR="$SCRIPT_DIR/ubuntu_base"
MILKV_ARCH="${MILKV_ARCH:-arm64}"
UBUNTU_BASE_ARCH="${UBUNTU_BASE_ARCH:-$MILKV_ARCH}"
UBUNTU_BASE_TARBALL="ubuntu-base-22.04-base-${UBUNTU_BASE_ARCH}.tar.gz"
UBUNTU_BASE_URL="http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/${UBUNTU_BASE_TARBALL}"

echo "=========================================="
echo "Configuring Build Environment"
echo "=========================================="

# 1. Clone SDK
if [ ! -d "$SDK_DIR" ]; then
    echo "Cloning duo-buildroot-sdk-v2..."
    git clone https://github.com/milkv-duo/duo-buildroot-sdk-v2.git "$SDK_DIR"
else
    echo "Filesystem check: SDK directory exists."
fi

# 1.5 Patch SDK for tinyalsa link dependency (pcm_* undefined references)
bash "$SCRIPT_DIR/patch_sdk.sh" "$SDK_DIR"

# 2. Patch Kernel Config
DEFAULT_DEFCONFIG="$SDK_DIR/build/boards/cv181x/sg2000_milkv_duos_glibc_arm64_sd/linux/cvitek_sg2000_milkv_duos_glibc_arm64_sd_defconfig"
CONFIG_FILE="${MILKV_SDK_DEFCONFIG:-$DEFAULT_DEFCONFIG}"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "Default defconfig not found: $CONFIG_FILE"
    echo "Searching for Duo S defconfigs in SDK..."
    mapfile -t DUOS_DEFCONFIGS < <(find "$SDK_DIR/build/boards" -type f -name "*duos*defconfig*" 2>/dev/null)

    if [ "${#DUOS_DEFCONFIGS[@]}" -eq 0 ]; then
        echo "No Duo S defconfigs found in SDK."
        echo "Set MILKV_SDK_DEFCONFIG to the correct defconfig path."
        exit 1
    fi

    if [[ "$MILKV_ARCH" == "arm64" ]]; then
        mapfile -t ARM_DEFCONFIGS < <(printf '%s\n' "${DUOS_DEFCONFIGS[@]}" | grep -iE "arm|aarch64" || true)
        if [ "${#ARM_DEFCONFIGS[@]}" -eq 1 ]; then
            CONFIG_FILE="${ARM_DEFCONFIGS[0]}"
            echo "Using detected ARM defconfig: $CONFIG_FILE"
        else
            echo "Found multiple or no ARM defconfig candidates:"
            printf '  %s\n' "${DUOS_DEFCONFIGS[@]}"
            echo "Set MILKV_SDK_DEFCONFIG to the correct defconfig path."
            exit 1
        fi
    else
        if [ "${#DUOS_DEFCONFIGS[@]}" -eq 1 ]; then
            CONFIG_FILE="${DUOS_DEFCONFIGS[0]}"
            echo "Using detected defconfig: $CONFIG_FILE"
        else
            echo "Found multiple defconfig candidates:"
            printf '  %s\n' "${DUOS_DEFCONFIGS[@]}"
            echo "Set MILKV_SDK_DEFCONFIG to the correct defconfig path."
            exit 1
        fi
    fi
fi

if [ -f "$CONFIG_FILE" ]; then
    echo "Patching kernel configuration..."
    
    # Helper to append config if missing
    ensure_config() {
        local config="$1"
        if ! grep -q "^${config}=" "$CONFIG_FILE" && ! grep -q "^${config} is not set" "$CONFIG_FILE"; then
            echo "  Adding $config=y"
            echo "$config=y" >> "$CONFIG_FILE"
        elif grep -q "^# ${config} is not set" "$CONFIG_FILE"; then
            echo "  Enabling $config=y"
            sed -i "s/^# ${config} is not set/${config}=y/" "$CONFIG_FILE"
        else
            echo "  $config already set"
        fi
    }

    # Helper to ensure config is set as module (=m)
    ensure_config_module() {
        local config="$1"
        if ! grep -q "^${config}=" "$CONFIG_FILE" && ! grep -q "^${config} is not set" "$CONFIG_FILE"; then
            echo "  Adding $config=m (module)"
            echo "$config=m" >> "$CONFIG_FILE"
        elif grep -q "^# ${config} is not set" "$CONFIG_FILE"; then
            echo "  Enabling $config=m (module)"
            sed -i "s/^# ${config} is not set/${config}=m/" "$CONFIG_FILE"
        elif grep -q "^${config}=y" "$CONFIG_FILE"; then
            echo "  Converting $config to module (y -> m)"
            sed -i "s/^${config}=y/${config}=m/" "$CONFIG_FILE"
        else
            echo "  $config already set"
        fi
    }

    # Helper to set a config value (strings/numbers) exactly
    ensure_config_value() {
        local key="$1"
        local value="$2"
        if grep -q "^${key}=" "$CONFIG_FILE"; then
            echo "  Updating ${key}=${value}"
            sed -i "s|^${key}=.*|${key}=${value}|" "$CONFIG_FILE"
        else
            echo "  Adding ${key}=${value}"
            echo "${key}=${value}" >> "$CONFIG_FILE"
        fi
    }

    # Basic systemd requirements
    ensure_config "CONFIG_CGROUPS"
    ensure_config "CONFIG_NAMESPACES"
    ensure_config "CONFIG_AUTOFS4_FS"
    ensure_config "CONFIG_TMPFS_POSIX_ACL"
    ensure_config "CONFIG_SECCOMP"
    
    # Cgroup v2 support (critical for systemd 249+)
    ensure_config "CONFIG_CGROUP_BPF"
    ensure_config "CONFIG_CGROUP_CPUACCT"
    ensure_config "CONFIG_CGROUP_DEVICE"
    ensure_config "CONFIG_CGROUP_FREEZER"
    ensure_config "CONFIG_CGROUP_HUGETLB"
    ensure_config "CONFIG_CGROUP_NET_CLASSID"
    ensure_config "CONFIG_CGROUP_NET_PRIO"
    ensure_config "CONFIG_CGROUP_PERF"
    ensure_config "CONFIG_CGROUP_PIDS"
    ensure_config "CONFIG_CGROUP_RDMA"
    ensure_config "CONFIG_CGROUP_SCHED"
    ensure_config "CONFIG_CPUSETS"
    ensure_config "CONFIG_MEMCG"
    ensure_config "CONFIG_BLK_CGROUP"
    
    # BPF support (required by modern systemd)
    ensure_config "CONFIG_BPF"
    ensure_config "CONFIG_BPF_SYSCALL"
    ensure_config "CONFIG_BPF_JIT"
    ensure_config "CONFIG_HAVE_EBPF_JIT"
    
    # IPC namespace support
    ensure_config "CONFIG_IPC_NS"
    ensure_config "CONFIG_NET_NS"
    ensure_config "CONFIG_PID_NS"
    ensure_config "CONFIG_USER_NS"
    ensure_config "CONFIG_UTS_NS"
    
    # Essential filesystem features
    ensure_config "CONFIG_DEVTMPFS"
    ensure_config "CONFIG_DEVTMPFS_MOUNT"
    ensure_config "CONFIG_TMPFS"
    ensure_config "CONFIG_SYSFS"
    ensure_config "CONFIG_PROC_FS"
    
    # Additional systemd requirements
    ensure_config "CONFIG_SIGNALFD"
    ensure_config "CONFIG_TIMERFD"
    ensure_config "CONFIG_EPOLL"
    ensure_config "CONFIG_INOTIFY_USER"
    ensure_config "CONFIG_FANOTIFY"
    ensure_config "CONFIG_FHANDLE"
    ensure_config "CONFIG_EVENTFD"
    ensure_config "CONFIG_SHMEM"
    
    # USB Gadget Support for USB-C Networking
    echo "Configuring USB Gadget subsystem..."
    
    # Core USB support
    ensure_config "CONFIG_USB_SUPPORT"
    ensure_config "CONFIG_USB"
    
    # USB Gadget base configuration
    ensure_config "CONFIG_USB_GADGET"
    ensure_config "CONFIG_USB_GADGET_VBUS_DRAW"
    
    # USB Gadget controller drivers (platform-specific)
    # Milk-V DuoS uses DWC2 at 4340000.usb in device mode
    ensure_config "CONFIG_USB_DWC2"
    ensure_config "CONFIG_USB_DWC2_PERIPHERAL"

    # ConfigFS gadget framework (required for modern gadgets)
    ensure_config "CONFIG_CONFIGFS_FS"
    ensure_config "CONFIG_USB_CONFIGFS"
    ensure_config_module "CONFIG_USB_CONFIGFS_ECM"
    ensure_config_module "CONFIG_USB_CONFIGFS_RNDIS"
    
    # Core gadget function drivers (needed by g_ether and configfs functions)
    ensure_config_module "CONFIG_USB_LIBCOMPOSITE"
    ensure_config_module "CONFIG_USB_U_ETHER"
    ensure_config_module "CONFIG_USB_F_ECM"
    ensure_config_module "CONFIG_USB_F_RNDIS"
    
    # USB Ethernet Gadget drivers (legacy g_ether module)
    # CONFIG_USB_ETH=m builds the g_ether.ko kernel module which provides
    # RNDIS/ECM USB Ethernet gadget functionality for USB-C OTG networking.
    # This enables the usb0 interface (192.168.42.1) when the board is plugged
    # into a host PC via the USB-C OTG port.
    echo "Configuring USB Ethernet gadget (g_ether module)..."
    ensure_config_module "CONFIG_USB_ETH"
    ensure_config "CONFIG_USB_ETH_RNDIS"
    ensure_config "CONFIG_USB_ETH_EEM"
    
    # Localversion: keep kernelrelease + module vermagic aligned
    # Avoid double-suffix like "5.10.4-tag--tag-".
    # If the SDK already provides a localversion suffix, do not append another.
    if grep -q "^CONFIG_LOCALVERSION=\".*-tag-.*\"" "$CONFIG_FILE"; then
        echo "  CONFIG_LOCALVERSION already contains -tag-; leaving as-is."
    else
        echo "  Setting CONFIG_LOCALVERSION to empty to avoid double suffix."
        ensure_config_value "CONFIG_LOCALVERSION" "\"\""
    fi
    if grep -q "^CONFIG_LOCALVERSION_AUTO=y" "$CONFIG_FILE"; then
        echo "  Disabling CONFIG_LOCALVERSION_AUTO"
        sed -i "s/^CONFIG_LOCALVERSION_AUTO=y/# CONFIG_LOCALVERSION_AUTO is not set/" "$CONFIG_FILE"
    fi
    
    echo "USB Gadget configuration complete."
    echo "Kernel config patched."

    # Wi-Fi stack + SDIO essentials (for onboard Wi-Fi modules)
    echo "Configuring Wi-Fi/SDIO kernel options..."
    ensure_config "CONFIG_WLAN"
    ensure_config "CONFIG_WIRELESS"
    ensure_config "CONFIG_CFG80211"
    ensure_config_module "CONFIG_MAC80211"
    ensure_config "CONFIG_RFKILL"
    ensure_config "CONFIG_MMC"
    ensure_config "CONFIG_MMC_BLOCK"
    ensure_config "CONFIG_MMC_SDHCI"
    ensure_config "CONFIG_MMC_SDHCI_PLTFM"
    ensure_config "CONFIG_MMC_SDHCI_OF_ARASAN"
    ensure_config "CONFIG_MMC_SDIO"
    # Common SDIO Wi-Fi drivers (modules if available in this kernel)
    ensure_config_module "CONFIG_BRCMFMAC"
    ensure_config_module "CONFIG_BRCMFMAC_SDIO"
    ensure_config_module "CONFIG_RTL8723BS"
    ensure_config_module "CONFIG_RTL8723DS"
    ensure_config_module "CONFIG_RTL8189ES"
    echo "Wi-Fi/SDIO configuration complete."
else
    echo "Error: Config file not found at $CONFIG_FILE"
    echo "Has the SDK structure changed?"
    exit 1
fi

# 2.5 Patch device tree to enable Wi-Fi SDIO (if present)
ENABLE_WIFI_PATCH="${ENABLE_WIFI_PATCH:-1}"
if [ "$ENABLE_WIFI_PATCH" = "1" ]; then
    echo "Patching device tree for Wi-Fi SDIO (4320000) if needed..."
    bash "$SCRIPT_DIR/patch_wifi_dts.sh" "$SDK_DIR" || true
else
    echo "Wi-Fi DTS patch disabled (ENABLE_WIFI_PATCH=$ENABLE_WIFI_PATCH)."
fi

# 3. Download Ubuntu Base
if [ ! -d "$UBUNTU_DIR" ]; then
    mkdir -p "$UBUNTU_DIR"
fi

# Check if ubuntu base is already extracted (check for bin directory)
if [ ! -d "$UBUNTU_DIR/bin" ]; then
    echo "Downloading Ubuntu Base 22.04..."
    cd "$UBUNTU_DIR"
    wget -N "$UBUNTU_BASE_URL"
    
    echo "Extracting Ubuntu Base..."
    tar -xzf "$UBUNTU_BASE_TARBALL"
    # Clean up tarball to save space/cache
    rm "$UBUNTU_BASE_TARBALL"
    cd "$SCRIPT_DIR"
else
    echo "Filesystem check: Ubuntu Base already extracted."
fi

echo ""
echo "=========================================="
echo "✓ Configuration Complete!"
echo "=========================================="
echo "Run build: sudo bash build_sdk.sh && sudo bash install_systemd.sh && sudo bash build_image.sh"
echo ""
