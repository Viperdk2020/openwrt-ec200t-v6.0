# Repository Guidelines


## Hardware Notes & GPIO Map
MT7628 LEDs are active-low on `gpio0` (3G/front), `gpio2` (WAN/“2G”), `gpio37` (LTE/“4G”), and `gpio44` (Wi-Fi). Keep `gpio1` high—forcing it low power-cycles the Quectel EC200T—while `gpio4` is currently unused. The reset button is wired to `gpio38` (active-low). Switch-port LEDs are driven by the ESW block; program `ESW LED_CTRL{0..2}` at `0x10110030` via `devmem2`/`swconfig` to light LAN0/LAN1. The SIM slot feeds the EC200T directly, so SIM presence and PIN state must be queried through the modem’s USB control ports (`/dev/ttyUSB*`, `wwan0`).

## Modem Init & Diagnostics (ML352/EC200 family on OpenWrt APK)

- GPIO mapping
  - Sysfs uses base 512 + SoC GPIO number (e.g., SoC `GPIO1` → sysfs `gpio513`).
  - On this board: `GPIO1` controls modem power (PWR_EN), `GPIO4` is modem reset (RESET_N, active‑low).
    - Power‑on (observed stable sequence): `echo 1 > /sys/class/gpio/gpio513/value; sleep 8; echo 0 > /sys/class/gpio/gpio513/value`.
    - Reset pulse (active‑low): export `gpio516`, `direction=out`, then `echo 0; sleep 1; echo 1` to `/sys/class/gpio/gpio516/value`.

- USB enumeration and drivers
  - Typical VID:PID seen on this unit: Marvell/ASR `1286:4e3c` (serial composition). Option driver creates `/dev/ttyUSB0..2`.
  - Load/bind safely (idempotent):
    - `modprobe usbserial option cdc_acm 2>/dev/null || true`
    - `echo '1286 4e3c ff' > /sys/bus/usb-serial/drivers/option/new_id 2>/dev/null || true`
    - If Quectel‑like: also try `echo '2c7c 6026 ff' > .../option/new_id`.

- Finding the responsive AT port (uses BusyBox socat or microcom)
  - socat probe: `for p in /dev/ttyUSB3 /dev/ttyUSB2 /dev/ttyUSB1 /dev/ttyUSB0; do printf 'ATE0\r\nATI\r\nAT+CPIN?\r\n' | socat -T 8 - "OPEN:$p,raw,echo=0,crnl" && break; done`.
  - Common working ports on this hardware: `ttyUSB3` or `ttyUSB1`.

- Read SIM number (if provisioned) and USSD fallback
  - SIM record: `printf 'ATE0\r\nAT+CNUM\r\n' | socat -T 8 - "OPEN:$AT_PORT,raw,echo=0,crnl"`.
  - Network USSD (Lycamobile examples):
    - `AT+CUSD=1,"*132#",15` then cancel with `AT+CUSD=2`.
    - Alternates: `*#100#`, `97#`, `*100#` (country‑dependent).
  - EF_MSISDN (often empty):
    - FCP/meta: `AT+CRSM=192,28480,0,0,15`; record read: `AT+CRSM=178,28480,1,4,32`.

- Data bring‑up (no QMI/MBIM on ML352)
  - ECM/NCM present → DHCP on `usb0`: `ip link set usb0 up; udhcpc -n -q -i usb0`.
  - Otherwise PPP over serial. Minimal peers/chat:
    - `/etc/ppp/peers/wwan`:
      - `device /dev/ttyUSB3`
      - `115200`
      - `noipdefault\nusepeerdns\nipcp-accept-remote\nipcp-accept-local\nnovj\nnobsdcomp\nnodeflate\npersist\nmaxfail 0\nholdoff 5\nlcp-echo-interval 30\nlcp-echo-failure 6\nlcp-echo-adaptive\ndefaultroute`
      - `connect "/usr/sbin/chat -v -s -S -t 45 -f /etc/ppp/chatscripts/wwan.chat"`
    - `/etc/ppp/chatscripts/wwan.chat`:
      - `ABORT "BUSY"\nABORT "NO CARRIER"\nABORT "NO DIALTONE"\nABORT "ERROR"\nABORT "NO ANSWER"\n"" ATZ\nOK 'AT+CGDCONT=1,"IP","<your-apn>"'\nOK ATD*99#\nCONNECT ""`
    - Bring up: `pppd call wwan`.

- Troubleshooting tips
  - If `/dev/ttyUSB*` don’t appear but dmesg shows `usb 1-1` attach: ensure PWR_EN is held in the ON state and re‑bind `option` with the current VID:PID.
  - If USSD payload is UCS2 hex, decode with `iconv` (or paste into the repo notes and decode offline).
  - This OpenWrt uses `apk`; if `socat` is missing, install when WAN is up: `apk update; apk add socat` (or use BusyBox `microcom`).

