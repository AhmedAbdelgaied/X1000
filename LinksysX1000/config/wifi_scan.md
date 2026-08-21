# Wi-Fi Scan, Connect, and Repeater Configuration Guide

## Overview

The **BCM43217** chip with the `brcmsmac` driver supports Wi-Fi scanning in all modes.  
This guide covers:
1. Scanning for nearby networks (CLI + LuCI)
2. Connecting to an upstream AP (repeater/STA mode)
3. Verifying if concurrent STA+AP works on your hardware
4. Fallback: wired WAN + Wi-Fi AP if STA+AP isn't supported

---

## Method 1 — Scan via LuCI (Easiest)

1. Open browser → `http://192.168.1.1`
2. Go to **Network → Wireless**
3. Click **Scan** next to `radio0`
4. A list of nearby SSIDs appears with signal strength (RSSI), channel, and encryption
5. Click **Join Network** next to the SSID you want to connect to
6. Enter the password and assign it to the `wwan` network interface
7. Click **Save & Apply**

---

## Method 2 — Scan via CLI (SSH)

```bash
# Trigger a scan and display results
iwinfo wlan0 scan

# Output example:
# Cell 01 - Address: AA:BB:CC:DD:EE:01
#           ESSID: "MyRouter"
#           Mode: Master  Channel: 6
#           Signal: -55 dBm  Quality: 55/70
#           Encryption: WPA2 PSK (CCMP)
```

Sort by signal strength:
```bash
iwinfo wlan0 scan | grep -E "(ESSID|Signal)" | paste - -
```

---

## Method 3 — Quick Connect via UCI (CLI)

After scanning and identifying your target SSID:

```bash
# Set the upstream STA connection
uci set wireless.wwan=wifi-iface
uci set wireless.wwan.device='radio0'
uci set wireless.wwan.mode='sta'
uci set wireless.wwan.network='wwan'
uci set wireless.wwan.ssid='TargetSSID'          # ← upstream SSID
uci set wireless.wwan.encryption='psk2'
uci set wireless.wwan.key='TargetPassword'        # ← upstream password
uci commit wireless
wifi reload
```

Check connection status:
```bash
iwinfo wlan0 info    # should show "Mode: Client" and BSSID of upstream AP
ip addr show wlan0   # should show IP from upstream DHCP
ping -c 3 8.8.8.8    # confirm internet reachability
```

---

## Verify Concurrent STA+AP Support

The BCM43217 + brcmsmac driver *may or may not* support running STA and AP simultaneously.  
Check after boot:

```bash
iw list | grep -A 20 "valid interface combinations"
```

### Case A — Concurrent mode IS supported ✅

Output will include something like:
```
valid interface combinations:
  * #{ managed } <= 1, #{ AP } <= 1,
    total <= 2, channels <= 1, STA/AP BI must match
```

→ Apply `config/wireless.uci` **Section C** (STA + AP) — full repeater works.

### Case B — Concurrent mode NOT supported ⚠️

Output shows only single-interface combinations, e.g.:
```
valid interface combinations:
  * #{ managed, AP } <= 1, total <= 1
```

→ Use the **wired WAN fallback** below.

---

## Fallback: Wired WAN Port + Wi-Fi AP (No Concurrent Radio Required)

If brcmsmac doesn't support concurrent STA+AP, use the WAN Ethernet port for upstream connectivity and Wi-Fi only for local AP:

```
[Internet/Modem] ──Ethernet──> [X1000 WAN port] → [X1000 AP Wi-Fi] → [Clients]
```

This is actually the **most stable configuration** and avoids the concurrent-radio limitation entirely.  
Use `config/network_pppoe_vlan.uci` (for PPPoE) or `config/network_ap.uci` (bridged) for the WAN side, and `config/wireless.uci` Section A for the AP.

---

## Persistent Wi-Fi Scan Script (save to router)

Save this to `/usr/bin/wifiscan` on the router for quick scanning:

```bash
#!/bin/sh
# Quick Wi-Fi scanner for X1000 / OpenWrt
# Usage: wifiscan [interface]
# Example: wifiscan wlan0

IFACE="${1:-wlan0}"

echo "=== Scanning on $IFACE ==="
iwinfo "$IFACE" scan 2>/dev/null | awk '
/Cell/ { if (ssid != "") printf "%-32s  Ch:%-3s  Signal:%-6s  Enc:%s\n", ssid, ch, sig, enc
         ssid=""; ch=""; sig=""; enc="" }
/ESSID/  { gsub(/"/, "", $2); ssid = $2 }
/Channel/ { ch = $2 }
/Signal/  { sig = $2 " " $3 }
/Encryption/ { enc = substr($0, index($0,$2)) }
END { if (ssid != "") printf "%-32s  Ch:%-3s  Signal:%-6s  Enc:%s\n", ssid, ch, sig, enc }
' | sort -t: -k3 -rn

echo ""
echo "Run 'iwinfo $IFACE assoclist' to see connected clients."
```

Install on router:
```bash
scp config/wifiscan root@192.168.1.1:/usr/bin/wifiscan
ssh root@192.168.1.1 "chmod +x /usr/bin/wifiscan && wifiscan"
```

---

## Advanced: Lock to Specific AP (BSSID)

If multiple APs broadcast the same SSID (roaming environment):

```bash
# Scan and get BSSID of the strongest signal
iwinfo wlan0 scan | grep -B1 "MySSID" | grep "Address"

# Lock STA to that BSSID
uci set wireless.wwan.bssid='AA:BB:CC:DD:EE:FF'
uci commit wireless && wifi reload
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| `iwinfo wlan0 scan` returns empty | Run `wifi up` first; `dmesg | grep brcmsmac` for errors |
| STA connects but no internet | Check `relayd` is running: `ps | grep relayd` |
| STA keeps disconnecting | Reduce `txpower` to 17 dBm; check channel congestion |
| AP not starting after STA | Concurrent mode not supported — use wired WAN fallback |
| `brcmsmac` firmware not found | Check `/lib/firmware/brcm/` for `brcmsmac-ag-43217.fw` |
