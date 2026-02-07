# Network + SSH Setup on Custom Ubuntu RootFS (Minimal)

This document contains legacy notes on how to bring up networking and install SSH on a bare-minimum Ubuntu root filesystem (without our automated scripts).

### 1. Verify Ethernet Device Exists
```bash
ls /sys/class/net
# Expected: eth0  lo  sit0
```

### 2. Create a Network Configuration for DHCP

Since no editors (nano/vi) might be available:

```bash
cat <<EOF > /etc/systemd/network/20-eth0.network
[Match]
Name=eth0

[Network]
DHCP=yes
EOF
```

### 3. Enable + Start systemd-networkd
```bash
systemctl enable systemd-networkd
systemctl start systemd-networkd
systemctl restart systemd-networkd
```

### 4. Verify Network Status
```bash
networkctl status eth0
```
Expected: `State: routable (configured)`

### 5. Fix DNS (if needed)
```bash
echo "nameserver 8.8.8.8" > /etc/resolv.conf
```

### 6. Install SSH
```bash
apt update
apt install openssh-server -y
systemctl enable ssh
systemctl start ssh
```

### 7. Connect via SSH
```bash
ssh root@<BOARD_IP>
```

---

## Windows ICS (Internet Connection Sharing) Setup

If connecting via Ethernet directly to a Windows PC:

1. **Windows**: Share Wi-Fi to Ethernet adapter.
2. **Windows**: Check IP of Ethernet adapter (usually becomes `192.168.137.1`).
3. **Board**: Setup DHCP (as above).
4. **Find IP**: Use `arp -a` on Windows to find the board's IP in `192.168.137.x`.
