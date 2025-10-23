# Repository Guidelines

## Project Structure & Module Organization
Raw flash dumps (`mtd0.bin` – `mtd7.bin`) live at the top level for quick reference. Derived artifacts are grouped by type: decompiled kernel routines in `kernel_*.c`, userland routines in `rc_*.c`, and CSV/string dumps in `String_CSV.cvs`. Ghidra project state is separated by target: `RouterHeadlessProj.*` (kernel analysis), `RouterMtkProj.*` (Mediatek libs), and `RouterUserProj.*` (userland). Automation helpers (`DecompileFunctionHeadless.py`, `DumpXrefs.py`, etc.) sit alongside for easy reuse; keep any new scripts here and name them by action (`DumpFoo.py`).

## Build, Test, and Analysis Commands
Ghidra headless workflows run via `analyzeHeadless`. Example:  
`ghidra/support/analyzeHeadless RouterHeadlessProj.gpr RouterHeadlessProj -import mtd3_vmlinux.bin -scriptPath . -postScript ListFuncs.py`  
Use `python3 DumpXrefs.py <symbol> <out.json>` from inside Ghidra (Window ▶ Script Manager) to export cross-references. To decompile a function non-interactively:  
`python3 DecompileFunctionHeadless.py FUN_803136f4 kernel_FUN_803136f4.c` (run through Ghidra’s headless interpreter). When pulling new dumps, keep originals immutable and place experiments in a `work/` subdirectory to avoid overwriting source material. For OpenWrt firmware builds, run `wrap_mt7628_initramfs.sh <image.bin>` (initramfs and sysupgrade) before TFTP or flashing so the MediaTek RAM-boot header matches stock U-Boot expectations.

## Coding Style & Naming Conventions
Python tooling stays compatible with Ghidra’s Jython runtime—avoid Python 3–only syntax (f-strings, pathlib) unless guarded. Name exports after the symbol being examined (`kernel_<addr>.c`, `rc_<func>.c`) and include comment headers with source offsets if you regenerate files. For CSV notes, prefer ASCII and comma-delimited records so they open cleanly in both spreadsheets and scripts.

## Testing Guidelines
Before committing automation changes, dry-run scripts against `mtd3_vmlinux.bin` and confirm they produce the expected artifacts in `tmp/`. Validate decompilation scripts by diffing regenerated `kernel_*.c` outputs with existing versions. If you introduce parsing logic, add a small fixture under `tests/` (create the directory if needed) and script a `python3 -m pytest` check; keep fixtures under 10 KB to ease sharing.

## Commit & Pull Request Guidelines
Use descriptive Conventional Commit prefixes (`feat:`, `fix:`, `docs:`). Commits should capture a single conceptual change: e.g., `feat: add gpio xref dumper`. Provide PR descriptions covering 1) target firmware component, 2) scripts/commands used, 3) verification steps (logs, diff summaries), and 4) follow-up tasks. Avoid checking in proprietary or licensed vendor binaries beyond the minimal firmware segments already tracked; if a new dump is necessary, document its source and checksum in the PR.

## Hardware Notes & GPIO Map
MT7628 LEDs are active-low on `gpio0` (3G/front), `gpio2` (WAN/“2G”), `gpio37` (LTE/“4G”), and `gpio44` (Wi-Fi). Keep `gpio1` high—forcing it low power-cycles the Quectel EC200T—while `gpio4` is currently unused. The reset button is wired to `gpio38` (active-low). Switch-port LEDs are driven by the ESW block; program `ESW LED_CTRL{0..2}` at `0x10110030` via `devmem2`/`swconfig` to light LAN0/LAN1. The SIM slot feeds the EC200T directly, so SIM presence and PIN state must be queried through the modem’s USB control ports (`/dev/ttyUSB*`, `wwan0`).

## Field Work Tips
Record all bootloader interactions (TFTP logs, UART captures) in `bootlog.txt` to keep lab context. When experimenting with RAM boots, note the exact image and load/entry addresses used so others can reproduce the state machine quickly.
- Latest custom OpenWrt artifacts live at `openwrt/bin/targets/ramips/mt76x8/` (`openwrt-ramips-mt76x8-custom_ec200t-*.bin`). Always wrap initramfs and sysupgrade with `wrap_mt7628_initramfs.sh` to get the MTK RAM header before TFTP/flash; the wrapped outputs share the same directory.
- Before flashing, capture full flash backups. Options: 1) use evaluation initramfs (`openwrt-ramips-mt76x8-mediatek_mt7628an-eval-board-initramfs-kernel-ramboot.bin`) and `dd if=/dev/mtdX of=/tmp/mtdX.bin` followed by `tftp -pl mtdX.bin <host>`, or 2) slice reads in U-Boot via `spi read 0x81000000 <offset> <length> ; tftpput ...`. Store copies under `C:\tftp`.
- Bootloader artefacts: `Router/mtd0_env_defaults.txt` holds the factory U-Boot environment (bootcmd=tftp, baudrate 57600, placeholder MAC, `ipaddr=192.168.188.1`, `serverip=192.168.188.103`) pulled straight from `mtd0.bin`. `Router/mtd0_bootloader_info.txt` captures the Ralink/JBoneCloud U-Boot banner, dual-slot menu text, and embedded HTTP upgrader HTML. Keep both alongside the raw dump for easy re-seeding of `mtd1` or reference while wrapping images.
- HTTP updater reference: `Router/mtd0-http-update-strings.txt` lists the HTTP upgrader strings with offsets, and `Router/http_update_analysis.md` summarizes form field names, validation rules, and IP defaults for quick access during lab work.
- Flash write mapping: `Router/mtd0_flash_write_map.md` walks the HTTP upgrader code paths (entry at `0xBFC011A4`, multipart parser, SPI erase/copy loop) and links the key strings to the relevant `addiu` sites so you can jump straight into the flash-write routine in disassembly.
- Upstream delta: the same map now carries a comparison against mainline mt7628 U-Boot (lines under “Upstream Comparison”) to help spot what would need rework if we backport the HTTP upgrader to a modern tree.
- Header packer: use `python3 jbonecloud_wrap.py <sysupgrade.bin> -o <output.bin>` to rewrite the uImage magic to `0x27151967` and refresh both header/data CRCs before flashing; optional flags allow adjusting name/load/entry if the upstream image changes.
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

