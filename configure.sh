#!/bin/bash
# configure.sh
# Automated setup for Milk-V Duo S build environment
# - Clones SDK
# - Patches kernel config
# - Downloads Ubuntu Base

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SDK_DIR="$SCRIPT_DIR/duo-buildroot-sdk"
UBUNTU_DIR="$SCRIPT_DIR/ubuntu_base"

echo "=========================================="
echo "Configuring Build Environment"
echo "=========================================="

# 1. Clone SDK
if [ ! -d "$SDK_DIR" ]; then
    echo "Cloning duo-buildroot-sdk..."
    git clone https://github.com/milkv-duo/duo-buildroot-sdk.git "$SDK_DIR"
else
    echo "Filesystem check: SDK directory exists."
fi

# 2. Patch Kernel Config
CONFIG_FILE="$SDK_DIR/build/boards/cv181x/cv1813h_milkv_duos_sd/linux/cvitek_cv1813h_milkv_duos_sd_defconfig"

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
    
    echo "Kernel config patched."
else
    echo "Error: Config file not found at $CONFIG_FILE"
    echo "Has the SDK structure changed?"
    exit 1
fi

# 3. Download Ubuntu Base
if [ ! -d "$UBUNTU_DIR" ]; then
    mkdir -p "$UBUNTU_DIR"
fi

# Check if ubuntu base is already extracted (check for bin directory)
if [ ! -d "$UBUNTU_DIR/bin" ]; then
    echo "Downloading Ubuntu Base 22.04..."
    cd "$UBUNTU_DIR"
    wget -N http://cdimage.ubuntu.com/ubuntu-base/releases/22.04/release/ubuntu-base-22.04-base-riscv64.tar.gz
    
    echo "Extracting Ubuntu Base..."
    tar -xzf ubuntu-base-22.04-base-riscv64.tar.gz
    # Clean up tarball to save space/cache
    rm ubuntu-base-22.04-base-riscv64.tar.gz
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
