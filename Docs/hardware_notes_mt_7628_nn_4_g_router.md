# Hardware Notes — MT7628NN 4G Router

*A single place to track all hardware facts we’ve confirmed so far.*

## Board & Core
- **Board marking:** `M7628NNxCPETSxUIv2_v3.0.2868.01.21_P0`
- **SoC/Target:** MediaTek **MT7628NN** (MIPS 24KEc @ ~580 MHz) — OpenWrt target `ramips/mt76x8`
- **RAM:** 64 MB DDR2 (512 Mbit, 16‑bit)
- **Flash:** 16 MB SPI‑NOR (Winbond W25Q128BV)
- **Wi‑Fi:** Integrated 2.4 GHz 802.11n (1T1R, MT7628 internal radio)
- **Ethernet:** MT7628 internal 10/100 switch
- **USB:** 1× USB 2.0 Type‑A (for LTE modem)
- **Antenna connectors:** 2× Wi‑Fi + 2× LTE (SMA)
- **Chassis class:** ZBT WE5931‑like

## Console & Defaults
- **UART header:** 3‑pin (3.3 V) — GND / TX / RX, **57600 8N1**
- **Default LAN IP (vendor):** `192.168.188.1`
- **MAC (example seen):** `88:12:7D:00:C0:2C`

## Bootloader (from mtd0)
- **Type/Version:** Ralink **U‑Boot 1.1.3** (Apr 02 2021 10:40:12)
- **Boot defaults (env):**
  - `bootcmd=tftp`, `bootdelay=1`, `baudrate=57600`
  - `ipaddr=192.168.188.1`, `serverip=192.168.188.103`, `ethaddr=00:AA:BB:CC:DD:40`
- **Accepted image format:** legacy **uImage** with **magic 0x27151967**; both header CRC (hcrc) and data CRC (dcrc) must be valid
- **Typical load/entry:** load `0x82000000` (entry approx `0x80285de0`)
- **Recovery paths:** boot menu + TFTP; also exposes an HTML updater page in the bootloader

## Flash / Partitions (DT & dumps)
- **Layout (OpenWrt style):**
  - `u-boot`        — 0x00000000–0x00030000 (192 KB)
  - `u-boot-env`    — 0x00030000–0x00040000 (64 KB)
  - `kernel`        — variable (~2 MB typical)
  - `rootfs`        — variable
  - `factory`       — 0x00040000–0x00050000 (64 KB, radio cal/MAC)
  - (sometimes `art` duplicate cal — 64 KB)

## Radio / Regulatory
- **Band:** 2.4 GHz only (HT40 capable)
- **Region we use:** `DK` (Denmark)

## 4G/LTE Modem
- **Module slot:** Quectel **EC200T** class (USB)
- **Typical USB VID:PID:** **1286:4e3c** (serial composition)
- **Drivers that work:** `option` (USB‑serial), `cdc_acm` (AT), `cdc_ether`/`rndis_host` (ECM/RNDIS when exposed)
- **Device nodes (serial):** `/dev/ttyUSB0..3` (varies; PPP commonly on **/dev/ttyUSB3**)
- **GPIO control (observed):**
  - **GPIO1** → Modem **PWR_EN** (1→on, then deassert)
  - **GPIO4** → Modem **RESET_N** (active‑low pulse to reset)

## LEDs / Buttons
- ~8 status LEDs; 2 buttons (Reset, WPS) — exact map TBD

## Power
- **Input:** 12 V DC @ ~1 A (also seen via Micro‑USB on some units)

## OpenWrt Fit (what we target)
- **Closest profiles:** `zbtlink_zbt-we5926` / `zbtlink_zbt-we5931` / `mediatek_mt7628an-eval`
- **Safe boot path:** UART → **TFTP RAM‑boot** (initramfs at `0x82000000`) → `sysupgrade -n`

## Notes / To‑confirm
- Switch driver details (RT305x/ESW vs DSA) — currently using swconfig on 6.12.x
- LED/GPIO map for all indicators
- Exact entry point varies by image/profile; we keep upstream defaults unless required

---
*This note aggregates confirmed facts from boot logs, mtd dumps, and prior runbooks. Update as we learn more.*



## LEDs, Buttons & GPIO Map

> **Numbering note (this board/OpenWrt build):** the Linux GPIO numbers are offset by **+512** from the MT7628 index. Example: MT7628 `GPIO1` appears as `/sys/class/gpio/gpio513`. Below we list both.

### Summary table
| Function | MT7628 GPIO | Linux `/sys` GPIO | Polarity | Notes |
|---|---:|---:|---|---|
| **Modem PWR_EN** | 1 | 513 | Active‑high (hold briefly) | Enable EC200T power: set 1 for ~8s then deassert to 0 (observed stable sequence). |
| **Modem RESET_N** | 4 | 516 | **Active‑low** | Pulse low ~1s to reset EC200T, then return high. |
| **LED – Front “3G”** | 0 | 512 | **Active‑low** | Turns on when driven low. |
| **LED – WAN/“2G”** | 2 | 514 | **Active‑low** | Front panel legend shows WAN/2G. |
| **LED – LTE/“4G”** | 37 | 549 | **Active‑low** | LTE status LED. |
| **LED – Wi‑Fi** | 44 | 556 | **Active‑low** | WLAN indicator. |
| **Button – RESET** | 38 | 550 | **Active‑low** (input) | Press pulls line low; handled by `gpio-keys` in DTS. |
| **Button – WPS** | (TBD) | (TBD) | (TBD) | Not confirmed yet. |
| **Switch port LEDs** | — | — | — | Driven by MT7628 ESW hardware, not GPIO; see below. |

### ESW (switch) LED control
The MT7628 internal switch drives per‑port LEDs via registers (not GPIO). Useful base addresses:
- `ESW_LED_CTRL{0..2}` at **0x10110030** range.
- You can experiment safely with read‑only first: `devmem2 0x10110030` (and +4, +8) or via `swconfig dev switch0 show` if supported.

### Quick test commands
**Toggle a LED that’s active‑low (example: Wi‑Fi LED on GPIO44):**
```sh
# export SoC GPIO 44 (Linux number 512+44=556)
echo 556 > /sys/class/gpio/export
# drive as output and toggle (active‑low means 0=ON, 1=OFF)
echo out > /sys/class/gpio/gpio556/direction
echo 0 > /sys/class/gpio/gpio556/value   # LED ON
sleep 1
echo 1 > /sys/class/gpio/gpio556/value   # LED OFF
```

**Modem power‑cycle sequence (PWR_EN = GPIO1, RESET_N = GPIO4):**
```sh
# PWR_EN
[ -d /sys/class/gpio/gpio513 ] || echo 513 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio513/direction
echo 1 > /sys/class/gpio/gpio513/value   # assert PWR_EN
sleep 8
echo 0 > /sys/class/gpio/gpio513/value   # deassert

# RESET_N (active‑low pulse)
[ -d /sys/class/gpio/gpio516 ] || echo 516 > /sys/class/gpio/export
echo out > /sys/class/gpio/gpio516/direction
echo 0 > /sys/class/gpio/gpio516/value
sleep 1
echo 1 > /sys/class/gpio/gpio516/value
```

### Validation checklist
- [ ] Pressing the **Reset** button changes `/sys/class/gpio/gpio550/value` from `1`→`0` while held.
- [ ] Each listed LED illuminates when its GPIO is driven **low**.
- [ ] ESW LED behavior matches link/activity without GPIO involvement.

> If you want, I can add uci/system LED definitions so these map to `leds/` aliases (e.g., `led_wlan`, `led_4g`) and tie them to triggers like `netdev` or `wwan` events.

