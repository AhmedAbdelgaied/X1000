# =============================================================================
# Linksys X1000 QoS & Bandwidth Management
# Advanced bandwidth control via tc (Traffic Control) + iptables
# Use this INSTEAD of or ALONGSIDE luci-app-sqm for fine-grained control
#
# This script runs at boot via /etc/rc.local or as a hotplug script.
# Deploy to router: scp config/qos_advanced.sh root@192.168.1.1:/etc/qos_advanced.sh
#                   ssh root@192.168.1.1 "chmod +x /etc/qos_advanced.sh"
#
# Add to /etc/rc.local (before exit 0):
#   /etc/qos_advanced.sh start
# =============================================================================

#!/bin/sh

# ── Configuration ─────────────────────────────────────────────────────────────
WAN_IF="pppoe-wan"          # WAN interface (PPPoE) — use 'eth0.30' if no PPPoE
LAN_IF="br-lan"             # LAN bridge interface
LAN_NET="192.168.100.0/24"  # LAN subnet

# ISP line speed — set to ACTUAL measured speed (run speed test first)
# Values in kbps (kilobits per second)
DOWN_KBPS=10000             # e.g., 10 Mbps download ← CHANGE
UP_KBPS=1000                # e.g., 1 Mbps upload    ← CHANGE

# Priority queue ratios (must add up to 100)
PRIO_HIGH=50    # Interactive (VoIP, DNS, ACK)
PRIO_NORMAL=35  # Normal web browsing
PRIO_BULK=15    # Downloads, streaming

# ── DSCP/TOS marks for traffic classification ─────────────────────────────────
# EF (Expedited Forwarding) → high priority
# CS0 → normal
# CS1 → bulk/background

start_qos() {
    echo "[QoS] Starting advanced QoS on $WAN_IF..."

    # ── EGRESS (upload) shaping ────────────────────────────────────────────────
    # Remove existing qdiscs
    tc qdisc del dev $WAN_IF root 2>/dev/null

    # Root HTB qdisc — default class = normal (12)
    tc qdisc add dev $WAN_IF root handle 1: htb default 12

    # Root class — total upload bandwidth
    tc class add dev $WAN_IF parent 1: classid 1:1 htb \
        rate ${UP_KBPS}kbit burst 15k

    # Class 11 — HIGH priority (VoIP, ACK, DNS, gaming)
    tc class add dev $WAN_IF parent 1:1 classid 1:11 htb \
        rate $((UP_KBPS * PRIO_HIGH / 100))kbit \
        ceil ${UP_KBPS}kbit burst 10k prio 1

    # Class 12 — NORMAL priority (web, SSH)
    tc class add dev $WAN_IF parent 1:1 classid 1:12 htb \
        rate $((UP_KBPS * PRIO_NORMAL / 100))kbit \
        ceil ${UP_KBPS}kbit burst 10k prio 2

    # Class 13 — BULK/background (downloads, torrents)
    tc class add dev $WAN_IF parent 1:1 classid 1:13 htb \
        rate $((UP_KBPS * PRIO_BULK / 100))kbit \
        ceil $((UP_KBPS * 60 / 100))kbit burst 10k prio 3

    # CAKE as leaf qdisc on each class (handles per-flow fairness)
    tc qdisc add dev $WAN_IF parent 1:11 handle 110: cake bandwidth \
        $((UP_KBPS * PRIO_HIGH / 100))kbit diffserv3
    tc qdisc add dev $WAN_IF parent 1:12 handle 120: cake bandwidth \
        $((UP_KBPS * PRIO_NORMAL / 100))kbit diffserv3
    tc qdisc add dev $WAN_IF parent 1:13 handle 130: cake bandwidth \
        $((UP_KBPS * PRIO_BULK / 100))kbit diffserv3

    # ── Ingress (download) shaping via IFB ────────────────────────────────────
    # Redirect incoming WAN traffic to IFB device for shaping
    modprobe ifb 2>/dev/null
    ip link set ifb0 up 2>/dev/null

    # Clear IFB
    tc qdisc del dev ifb0 root 2>/dev/null

    # Redirect WAN ingress to IFB
    tc qdisc add dev $WAN_IF handle ffff: ingress
    tc filter add dev $WAN_IF parent ffff: protocol ip u32 \
        match u32 0 0 action mirred egress redirect dev ifb0

    # CAKE on IFB for download limiting
    tc qdisc add dev ifb0 root cake bandwidth ${DOWN_KBPS}kbit \
        diffserv3 nat ingress

    # ── Traffic classification filters ────────────────────────────────────────
    # HIGH priority: DSCP EF (VoIP), ACK packets, DNS, ICMP
    tc filter add dev $WAN_IF parent 1: protocol ip prio 1 u32 \
        match ip tos 0xb8 0xfc flowid 1:11           # DSCP EF

    tc filter add dev $WAN_IF parent 1: protocol ip prio 2 u32 \
        match ip protocol 17 0xff \
        match ip dport 53 0xffff flowid 1:11          # DNS UDP

    tc filter add dev $WAN_IF parent 1: protocol ip prio 3 u32 \
        match ip protocol 1 0xff flowid 1:11          # ICMP

    # Small ACK packets → high priority (reduces upload congestion for downloads)
    tc filter add dev $WAN_IF parent 1: protocol ip prio 4 u32 \
        match ip protocol 6 0xff \
        match u8 0x05 0x0f at 0 \
        match u16 0x0000 0xffc0 at 2 flowid 1:11

    # BULK: DSCP CS1 (background class)
    tc filter add dev $WAN_IF parent 1: protocol ip prio 10 u32 \
        match ip tos 0x20 0xe0 flowid 1:13

    # Default → NORMAL
    # (everything else falls to default class 12 as set in htb)

    echo "[QoS] Done. Upload: ${UP_KBPS} kbps | Download: ${DOWN_KBPS} kbps"
    echo "[QoS] Priority: High=${PRIO_HIGH}% Normal=${PRIO_NORMAL}% Bulk=${PRIO_BULK}%"
}

stop_qos() {
    echo "[QoS] Stopping..."
    tc qdisc del dev $WAN_IF root 2>/dev/null
    tc qdisc del dev $WAN_IF ingress 2>/dev/null
    tc qdisc del dev ifb0 root 2>/dev/null
    ip link set ifb0 down 2>/dev/null
    echo "[QoS] Stopped."
}

show_stats() {
    echo "=== Upload (${WAN_IF}) ==="
    tc -s class show dev $WAN_IF

    echo ""
    echo "=== Download (ifb0) ==="
    tc -s qdisc show dev ifb0

    echo ""
    echo "=== Per-Host Bandwidth (nlbwmon) ==="
    nlbw -c show -o RX,TX,TOTAL 2>/dev/null || echo "nlbwmon not running"
}

case "$1" in
    start)   start_qos ;;
    stop)    stop_qos ;;
    restart) stop_qos; sleep 1; start_qos ;;
    stats)   show_stats ;;
    *)
        echo "Usage: $0 {start|stop|restart|stats}"
        echo ""
        echo "  start   — Apply QoS rules"
        echo "  stop    — Remove all QoS rules"
        echo "  restart — Reload QoS rules"
        echo "  stats   — Show per-class bandwidth stats"
        exit 1
        ;;
esac
