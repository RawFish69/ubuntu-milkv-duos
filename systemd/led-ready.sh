#!/bin/sh
set -eu

# Optional overrides in /etc/default/led-ready
if [ -f /etc/default/led-ready ]; then
    # shellcheck disable=SC1091
    . /etc/default/led-ready
fi

# Default to Duo S blue LED GPIO (from Buildroot SDK)
LED_PIN="${LED_PIN:-509}"
INTERVAL="${INTERVAL:-0.5}"
READY_IFACE="${READY_IFACE:-usb0}"
READY_WAIT_SEC="${READY_WAIT_SEC:-120}"

GPIO_EXPORT="/sys/class/gpio/export"
GPIO_DIR="/sys/class/gpio/gpio${LED_PIN}"

if [ ! -e "$GPIO_EXPORT" ]; then
    echo "GPIO sysfs not available; skipping LED blink" >&2
    exit 0
fi

if [ ! -d "$GPIO_DIR" ]; then
    echo "$LED_PIN" > "$GPIO_EXPORT" 2>/dev/null || true
fi

echo out > "$GPIO_DIR/direction" 2>/dev/null || true

# Wait for USB gadget interface to have an IPv4 address (best-effort).
if [ -n "$READY_IFACE" ]; then
    i=0
    while [ "$i" -lt "$READY_WAIT_SEC" ]; do
        if ip -4 addr show dev "$READY_IFACE" 2>/dev/null | grep -q "inet "; then
            break
        fi
        sleep 1
        i=$((i + 1))
    done
fi

while true; do
    echo 0 > "$GPIO_DIR/value" 2>/dev/null || true
    sleep "$INTERVAL"
    echo 1 > "$GPIO_DIR/value" 2>/dev/null || true
    sleep "$INTERVAL"
done
