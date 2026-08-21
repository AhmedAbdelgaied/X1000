# Linksys X1000 — Custom OpenWrt Firmware

Custom OpenWrt 23.05.5 firmware for the **Linksys X1000** (BCM63281, Annex A).  
Repurposed as a pure network device — DSL modem permanently disabled.  
Supports **Access Point**, **PPPoE+VLAN Gateway**, and **Wi-Fi Repeater** modes.

---

## Hardware (Confirmed)

| Component | Part |
|---|---|
| **CPU** | BCM63281TKFBG @ 320 MHz (MIPS32) |
| **RAM** | Winbond W9751G6KB-25 — 64 MB DDR2 |
| **Flash** | MXIC MX25L6406E — 8 MB SPI NOR |
| **Wi-Fi** | BCM43217KMLG — 2.4 GHz 802.11n, 2×2 MIMO (PCIe) |
| **Ethernet** | 3× LAN + 1× WAN (10/100 Mbps) |
| **DSL** | Annex A (POTS) — **disabled, unused** |
| **Bootloader** | CFE (Common Firmware Environment) |

**Wi-Fi driver:** `brcmsmac` — open-source, supports 802.11n  
**Flash layout:**
```
0x000000 - 0x010000 : CFE bootloader (64 KB, read-only)
0x010000 - 0x7F0000 : firmware — kernel + rootfs (~7.875 MB)
0x7F0000 - 0x800000 : NVRAM — MAC addresses, board ID (64 KB)
```

---

## Repository Layout

```
LinksysX1000/
├── README.md
├── build/
│   ├── setup_env.sh               ← WSL2/Linux build setup (run once)
│   ├── .config                    ← OpenWrt menuconfig for bcm63xx/X1000
│   └── patches/
│       ├── 001-x1000-dts.patch    ← DTS board port: BCM63281 + BCM43217
│       └── 002-x1000-profile.patch← Build profile in bcm63xx.mk
├── config/
│   ├── network_ap.uci             ← Mode 1: Access Point
│   ├── network_pppoe_vlan.uci     ← Mode 2: PPPoE + VLAN 30
│   ├── network_repeater.uci       ← Mode 3: Wi-Fi Repeater
│   ├── wireless.uci               ← SSID: Abdelgaied — all modes
│   ├── relayd.uci                 ← relayd daemon (repeater mode)
│   ├── sqm.uci                    ← SQM CAKE QoS config
│   ├── nlbwmon.uci                ← Per-host bandwidth monitoring
│   ├── qos_advanced.sh            ← Advanced tc/HTB/CAKE QoS script
│   └── wifi_scan.md               ← Wi-Fi scan & connect guide
└── flash/
    ├── flash_uart.md              ← UART + CFE TFTP guide (recommended)
    └── flash_webui.md             ← Web UI flash guide
```

---

## Build

Requires Linux or WSL2. Run once:
```bash
bash build/setup_env.sh
```

Or manually:
```bash
git clone -b v23.05.5 https://github.com/openwrt/openwrt.git ~/openwrt-x1000
cd ~/openwrt-x1000

# Apply patches
patch -p1 < /path/to/build/patches/001-x1000-dts.patch
patch -p1 < /path/to/build/patches/002-x1000-profile.patch

# Feeds + config
./scripts/feeds update -a && ./scripts/feeds install -a
cp /path/to/build/.config .config
make defconfig

# Build (~45 min first run)
make -j$(nproc) V=s 2>&1 | tee build.log
```

**Output:** `bin/targets/bcm63xx/generic/openwrt-bcm63xx-generic-linksys_x1000-squashfs-cfe.bin`

---

## Flash

| Method | Guide | Hardware |
|---|---|---|
| **UART + CFE TFTP** ✅ recommended | `flash/flash_uart.md` | USB-to-3.3V TTL adapter |
| Web UI upload | `flash/flash_webui.md` | LAN cable only |

UART settings: **115200 8N1, no flow control**  
CFE TFTP command:
```
CFE> ifconfig eth0 -addr=192.168.1.1 -mask=255.255.255.0
CFE> flash -noheader 192.168.1.100:openwrt-...-linksys_x1000-squashfs-cfe.bin flash0.trx
CFE> reboot
```

---

## Configure Operating Mode

After first boot — SSH to `192.168.1.1` (blank password):

```bash
passwd    # set root password immediately
```

### Mode 1 — Access Point
```bash
scp config/network_ap.uci  root@192.168.1.1:/etc/config/network
scp config/wireless.uci    root@192.168.1.1:/etc/config/wireless
ssh root@192.168.1.1 "uci commit && reboot"
```

### Mode 2 — PPPoE + VLAN 30
```bash
# Edit network_pppoe_vlan.uci: fill in username/password
scp config/network_pppoe_vlan.uci root@192.168.1.1:/etc/config/network
scp config/wireless.uci           root@192.168.1.1:/etc/config/wireless
ssh root@192.168.1.1 "uci commit && reboot"
```

### Mode 3 — Wi-Fi Repeater
```bash
# First check if BCM43217 supports concurrent STA+AP: see config/wifi_scan.md
scp config/network_repeater.uci root@192.168.1.1:/etc/config/network
scp config/wireless.uci         root@192.168.1.1:/etc/config/wireless
scp config/relayd.uci           root@192.168.1.1:/etc/config/relayd
ssh root@192.168.1.1 "uci commit && /etc/init.d/relayd enable && reboot"
```

---

## QoS & Bandwidth Management

### Option A — SQM CAKE (via LuCI)
> Network → SQM QoS — simplest, recommended for PPPoE mode

```bash
scp config/sqm.uci root@192.168.1.1:/etc/config/sqm
ssh root@192.168.1.1 "/etc/init.d/sqm enable && /etc/init.d/sqm start"
```
**Remember:** Disable hardware/software flow offloading in Firewall settings.

### Option B — Advanced tc/HTB/CAKE Script
> Fine-grained 3-tier priority queuing: VoIP/ACK → Normal → Bulk downloads

```bash
scp config/qos_advanced.sh root@192.168.1.1:/etc/qos_advanced.sh
ssh root@192.168.1.1 "chmod +x /etc/qos_advanced.sh"

# Edit /etc/qos_advanced.sh — set DOWN_KBPS and UP_KBPS to your actual ISP speed
ssh root@192.168.1.1 "/etc/qos_advanced.sh start"

# View live per-class stats
ssh root@192.168.1.1 "/etc/qos_advanced.sh stats"
```

### Bandwidth Monitor (nlbwmon)
> Per-host traffic tracking with persistent history — view in LuCI: Statistics → Bandwidth Monitor

```bash
scp config/nlbwmon.uci root@192.168.1.1:/etc/config/nlbwmon
ssh root@192.168.1.1 "/etc/init.d/nlbwmon enable && /etc/init.d/nlbwmon start"

# CLI: view per-host usage
ssh root@192.168.1.1 "nlbw -c show"
```

---

## Wi-Fi Scan & Connect

See **`config/wifi_scan.md`** for full guide. Quick reference:

```bash
# Scan for nearby networks
iwinfo wlan0 scan

# Quick connect via UCI
uci set wireless.wwan=wifi-iface
uci set wireless.wwan.device='radio0'
uci set wireless.wwan.mode='sta'
uci set wireless.wwan.ssid='TargetSSID'
uci set wireless.wwan.encryption='psk2'
uci set wireless.wwan.key='TargetPassword'
uci set wireless.wwan.network='wwan'
uci commit wireless && wifi reload

# Verify BCM43217 concurrent STA+AP capability
iw list | grep -A 20 "valid interface combinations"
```

---

## Known Limitations

| | |
|---|---|
| **Flash** | 8 MB — very tight. Monitor free space with `df -h` after installing packages |
| **Concurrent STA+AP** | BCM43217 + brcmsmac — uncertain; verify with `iw list` after boot |
| **QoS + CPU** | 320 MHz CPU limits SQM throughput; effective up to ~20-30 Mbps WAN |
| **No DSL** | DSL Annex A hardware has no open-source driver — intentionally disabled |
| **OpenWrt EOL** | bcm63xx support dropped in OpenWrt 24.10 — use 23.05.x only |

---

## Useful Commands

```bash
# Wi-Fi status and clients
iwinfo wlan0 info && iwinfo wlan0 assoclist

# Network interfaces
ip addr && ip route

# PPPoE WAN status
ifstatus wan | jsonfilter -e '@.ipv4-address[0].address'

# VLAN interface check
ip -d link show eth0.30

# Flash free space
df -h

# QoS stats
/etc/qos_advanced.sh stats

# Bandwidth monitor
nlbw -c show

# Factory reset (keeps OpenWrt, wipes config)
firstboot && reboot
```

---

## Recovery

- **Soft reset:** Hold RESET button 10+ seconds → boots with default config
- **Serial recovery:** Follow `flash/flash_uart.md` to re-flash via CFE TFTP
