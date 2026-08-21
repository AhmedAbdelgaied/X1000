# Flashing via Stock Web UI

> [!WARNING]
> The stock Linksys web UI performs a firmware signature check. It will **reject images** that don't carry a valid Linksys header. This method may not work without header manipulation. If rejected, use the **UART + TFTP** method instead.

---

## Prerequisites

- PC connected to the X1000 via LAN cable (not Wi-Fi during flash)
- Custom OpenWrt image built: `openwrt-bcm63xx-generic-linksys_x1000-squashfs-cfe.bin`
- X1000 running stock Linksys firmware

---

## Method A — Direct Web UI Upload

1. Log in to the stock admin interface:
   - URL: `http://192.168.1.1`
   - Default login: admin / admin (or check bottom label)

2. Navigate to **Administration → Firmware Upgrade** (or similar — exact path varies by firmware version).

3. Click **Browse**, select your `.bin` image.

4. Click **Upgrade / Start Upgrade**.

5. **Do not interrupt power** during the flash process (~2-3 minutes).

6. The router will reboot automatically. Wait for the power LED to stabilize.

7. Set your PC to DHCP and try SSH to `192.168.1.1`:
   ```
   ssh root@192.168.1.1
   ```

---

## Method B — Overcome Signature Rejection (Header Injection)

If the web UI says "Invalid firmware" or rejects the image:

### Step 1 — Extract Linksys header from stock firmware

```bash
# On Linux/WSL2
# Download stock X1000 firmware from Linksys support site
# Then extract the 32-byte TRX header:
dd if=FW_X1000_1.0.06.bin of=linksys_header.bin bs=1 count=32

# Prepend it to the OpenWrt image:
cat linksys_header.bin openwrt-bcm63xx-generic-linksys_x1000-squashfs-cfe.bin \
    > openwrt_x1000_webflash.bin
```

### Step 2 — Upload the patched image

Repeat the web UI upload steps with `openwrt_x1000_webflash.bin`.

> **Note:** The prepended header may cause the CFE to try loading from the wrong offset. If the device bricks after this method, recover via UART + TFTP.

---

## Alternative: Telnet/SSH to Stock Firmware (Advanced)

Some Linksys firmware versions expose a hidden Telnet/SSH backdoor:

```bash
telnet 192.168.1.1
# or
ssh admin@192.168.1.1
```

If you get a shell, you can flash directly from the command line:
```bash
# On the router shell:
wget http://192.168.1.100/openwrt-bcm63xx-generic-linksys_x1000-squashfs-cfe.bin -O /tmp/fw.bin
mtd write /tmp/fw.bin firmware
reboot
```

---

## After Successful Flash

**First boot takes ~90 seconds** (jffs2 overlay creation).

```bash
# SSH into OpenWrt
ssh root@192.168.1.1     # password is blank
passwd                    # set a password immediately

# Copy your chosen config
scp config/network_ap.uci root@192.168.1.1:/etc/config/network
scp config/wireless.uci   root@192.168.1.1:/etc/config/wireless

# Apply
ssh root@192.168.1.1 "uci commit && reboot"
```

---

## Quick Verification Checklist

- [ ] Power LED solid after boot
- [ ] SSH accessible on `192.168.1.1`
- [ ] `uname -a` shows Linux + OpenWrt version
- [ ] `dmesg | grep mtd` shows correct flash partitions
- [ ] `iwinfo wlan0 info` shows radio up
- [ ] `ip link` shows `eth0`, `eth1`, `br-lan`, `wlan0`
