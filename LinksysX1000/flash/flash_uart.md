# Flashing via UART Serial + TFTP

This is the **recommended and most reliable** method. It works even if the web UI rejects the image or the device is semi-bricked.

---

## Hardware Required

| Item | Notes |
|---|---|
| USB-to-3.3V TTL UART adapter | FTDI FT232, CP2102, or CH340 chip. **Must be 3.3V logic level** — NOT 5V or RS-232 |
| Jumper wires (×3) | For GND, TX, RX connections |
| Small flathead screwdriver | To open the X1000 case |
| TFTP server software | Tftpd32/Tftpd64 (Windows) or `atftpd`/`dnsmasq` (Linux) |
| Terminal emulator | PuTTY (Windows) or `minicom`/`screen` (Linux) |

---

## Step 1 — Open the Device and Locate UART Header

1. Remove the 4 screws on the bottom of the X1000 (two may be under rubber feet).
2. Pry the top cover off starting from the rear.
3. Locate the **J2 header** on the PCB — a 4-pin unpopulated through-hole header near the CPU.

### UART Pin Assignment (J2 header, left-to-right when facing PCB top):

```
  ┌────┬────┬────┬────┐
  │ 1  │ 2  │ 3  │ 4  │
  │VCC │ TX │ RX │GND │
  │3.3V│(out│(in)│    │
  └────┴────┴────┴────┘
         ↑    ↑
     Router  Router
      sends  receives
```

> **⚠️ Do NOT connect VCC (pin 1) from your adapter to the board.**  
> Only connect: GND → GND, Router TX → Adapter RX, Router RX → Adapter TX

---

## Step 2 — Connect and Open Terminal

1. Connect your adapter to the PC via USB.
2. Identify the COM port in Device Manager (Windows) or `ls /dev/ttyUSB*` (Linux).
3. Open PuTTY → Serial → COM port, settings:

```
Baud rate:    115200
Data bits:    8
Parity:       None
Stop bits:    1
Flow control: None
```

---

## Step 3 — Prepare TFTP Server (Windows example using Tftpd64)

1. Download **Tftpd64** from https://pjo2.github.io/tftpd64/
2. Set your PC ethernet IP (the one connected to the router's LAN port) to **static `192.168.1.100`**, mask `255.255.255.0`.
3. Place the firmware image in Tftpd64's root directory:
   ```
   openwrt-bcm63xx-generic-linksys_x1000-squashfs-cfe.bin
   ```
4. Start Tftpd64, set base directory to the folder containing the .bin file.

---

## Step 4 — Boot to CFE and Flash

1. Power **OFF** the router.
2. With terminal open and ready, power **ON** the router.
3. Watch the terminal — you'll see the CFE boot log. **Press `Ctrl+C`** immediately when you see:

   ```
   CFE version 1.0.xx for BCM963281 ...
   Press Ctrl-C to stop auto-boot...
   ```

4. At the `CFE>` prompt, configure the network:

   ```
   CFE> ifconfig eth0 -addr=192.168.1.1 -mask=255.255.255.0
   ```

5. Flash the firmware (replace filename with your actual build output):

   ```
   CFE> flash -noheader 192.168.1.100:openwrt-bcm63xx-generic-linksys_x1000-squashfs-cfe.bin flash0.trx
   ```

   Expected output:
   ```
   Reading 192.168.1.100:openwrt-...-cfe.bin: done
   Programming flash...................................................................
   Flash device programming successful.
   ```

6. Reboot:

   ```
   CFE> reboot
   ```

---

## Step 5 — First Boot

After reboot you should see OpenWrt kernel messages in the terminal.  
Wait ~90 seconds for first boot (filesystem overlay creation).

**Default OpenWrt login:**
- IP: `192.168.1.1`
- SSH: `ssh root@192.168.1.1`
- Password: *(blank — set one immediately)*

```bash
passwd    # set root password
```

---

## Troubleshooting

| Problem | Solution |
|---|---|
| No output in terminal | Check TX/RX wiring are not swapped; verify baud 115200 |
| `CFE>` not appearing | Press `Ctrl+C` faster — CFE timeout is ~3 seconds |
| TFTP timeout | Confirm PC static IP is `192.168.1.100`; check firewall allows UDP port 69 |
| "Flash failed" error | Image too large or wrong format — rebuild with correct image size |
| Device doesn't boot after flash | Re-enter CFE, flash again; if CFE is lost, JTAG recovery is needed |

---

## Recovery (Re-flashing Stock Firmware)

To go back to stock:
1. Enter CFE as above.
2. Download stock firmware from [Linksys Support](https://support.linksys.com).
3. Use same `flash -noheader` command with the stock `.bin`.

> **Note:** Some stock Linksys images have a proprietary header. If flash is rejected, try extracting the raw TRX from the stock image with `binwalk -e stock.bin`.
