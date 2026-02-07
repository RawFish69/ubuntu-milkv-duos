#!/bin/bash
set -euo pipefail

GADGET_DIR="/sys/kernel/config/usb_gadget/g1"
CONFIG_DIR="${GADGET_DIR}/configs/c.1"
STRINGS_DIR="${GADGET_DIR}/strings/0x409"

VMLINUX_MODULES=(libcomposite usb_f_ecm usb_f_rndis usb_u_ether)

get_serial() {
    if [ -r /proc/device-tree/serial-number ]; then
        tr -d '\0' </proc/device-tree/serial-number
        return
    fi
    awk -F': ' '/Serial/ {print $2; exit}' /proc/cpuinfo 2>/dev/null || true
}

load_modules() {
    # Unload legacy g_ether if present; it can own the UDC and block configfs
    modprobe -r g_ether 2>/dev/null || true
    for mod in "${VMLINUX_MODULES[@]}"; do
        modprobe "$mod" 2>/dev/null || true
    done
}

mount_configfs() {
    if ! mountpoint -q /sys/kernel/config; then
        mkdir -p /sys/kernel/config
        mount -t configfs none /sys/kernel/config
    fi
}

setup_gadget() {
    mount_configfs
    load_modules
    # Ensure stale gadget state doesn't block reconfiguration
    teardown_gadget

    mkdir -p "$GADGET_DIR"
    echo 0x1d6b > "${GADGET_DIR}/idVendor"
    echo 0x0104 > "${GADGET_DIR}/idProduct"
    echo 0x0200 > "${GADGET_DIR}/bcdUSB"
    echo 0xEF > "${GADGET_DIR}/bDeviceClass"
    echo 0x02 > "${GADGET_DIR}/bDeviceSubClass"
    echo 0x01 > "${GADGET_DIR}/bDeviceProtocol"

    mkdir -p "$STRINGS_DIR"
    echo "$(get_serial || echo 00000000)" > "${STRINGS_DIR}/serialnumber"
    echo "Milk-V" > "${STRINGS_DIR}/manufacturer"
    echo "DuoS USB Gadget" > "${STRINGS_DIR}/product"

    mkdir -p "$CONFIG_DIR"
    echo 250 > "${CONFIG_DIR}/MaxPower"
    mkdir -p "${CONFIG_DIR}/strings/0x409"
    echo "ECM+RNDIS" > "${CONFIG_DIR}/strings/0x409/configuration"

    # ECM function (Linux/macOS)
    mkdir -p "${GADGET_DIR}/functions/ecm.usb0"
    echo "02:1a:11:00:00:01" > "${GADGET_DIR}/functions/ecm.usb0/dev_addr"
    echo "02:1a:11:00:00:02" > "${GADGET_DIR}/functions/ecm.usb0/host_addr"

    # RNDIS function (Windows)
    mkdir -p "${GADGET_DIR}/functions/rndis.usb1"
    echo "02:1a:11:00:00:03" > "${GADGET_DIR}/functions/rndis.usb1/dev_addr"
    echo "02:1a:11:00:00:04" > "${GADGET_DIR}/functions/rndis.usb1/host_addr"

    # Microsoft OS descriptors for RNDIS
    echo 1 > "${GADGET_DIR}/os_desc/use"
    echo 0xcd > "${GADGET_DIR}/os_desc/b_vendor_code"
    echo "MSFT100" > "${GADGET_DIR}/os_desc/qw_sign"
    mkdir -p "${GADGET_DIR}/functions/rndis.usb1/os_desc/interface.rndis"
    echo "RNDIS" > "${GADGET_DIR}/functions/rndis.usb1/os_desc/interface.rndis/compatible_id"
    echo "5162001" > "${GADGET_DIR}/functions/rndis.usb1/os_desc/interface.rndis/sub_compatible_id"

    ln -sf "${GADGET_DIR}/functions/ecm.usb0" "${CONFIG_DIR}"
    ln -sf "${GADGET_DIR}/functions/rndis.usb1" "${CONFIG_DIR}"
    ln -sf "${CONFIG_DIR}" "${GADGET_DIR}/os_desc"

    UDC="$(ls /sys/class/udc 2>/dev/null | head -n1 || true)"
    if [ -z "$UDC" ]; then
        echo "No UDC found; gadget not bound." >&2
        return 1
    fi
    # Unbind any other gadgets that may already own the UDC
    for g in /sys/kernel/config/usb_gadget/*; do
        if [ -e "$g/UDC" ]; then
            echo "" > "$g/UDC" 2>/dev/null || true
        fi
    done
    # Bind this gadget to the UDC (retry once if busy)
    if ! echo "$UDC" > "${GADGET_DIR}/UDC" 2>/dev/null; then
        sleep 1
        echo "" > "${GADGET_DIR}/UDC" 2>/dev/null || true
        echo "$UDC" > "${GADGET_DIR}/UDC"
    fi

    # Configure interfaces (systemd-networkd can also do this)
    # Note: systemd-networkd will handle IP assignment via .network files
    ip link set usb0 up 2>/dev/null || true
    ip link set usb1 up 2>/dev/null || true
}

teardown_gadget() {
    if [ ! -d "$GADGET_DIR" ]; then
        return 0
    fi
    # Unbind if currently bound
    if [ -e "${GADGET_DIR}/UDC" ]; then
        echo "" > "${GADGET_DIR}/UDC" 2>/dev/null || true
    fi
    # Remove config links and os_desc link
    rm -f "${CONFIG_DIR}/ecm.usb0" "${CONFIG_DIR}/rndis.usb1" 2>/dev/null || true
    rm -f "${GADGET_DIR}/os_desc/c.1" 2>/dev/null || true
    # Remove function-specific os_desc before removing functions
    rmdir "${GADGET_DIR}/functions/rndis.usb1/os_desc/interface.rndis" 2>/dev/null || true
    rmdir "${GADGET_DIR}/functions/rndis.usb1/os_desc" 2>/dev/null || true
    rmdir "${GADGET_DIR}/functions/ecm.usb0" 2>/dev/null || true
    rmdir "${GADGET_DIR}/functions/rndis.usb1" 2>/dev/null || true
    # Remove config and strings
    rmdir "${CONFIG_DIR}/strings/0x409" 2>/dev/null || true
    rmdir "${CONFIG_DIR}/strings" 2>/dev/null || true
    rmdir "${CONFIG_DIR}" 2>/dev/null || true
    rmdir "${STRINGS_DIR}" 2>/dev/null || true
    rmdir "${GADGET_DIR}/strings" 2>/dev/null || true
    rmdir "${GADGET_DIR}/os_desc" 2>/dev/null || true
    rmdir "${GADGET_DIR}" 2>/dev/null || true
}

case "${1:-start}" in
    start)
        setup_gadget
        ;;
    stop)
        teardown_gadget
        ;;
    restart)
        teardown_gadget
        setup_gadget
        ;;
    *)
        echo "Usage: $0 {start|stop|restart}" >&2
        exit 1
        ;;
esac
