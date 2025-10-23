# MT7628NN 4G Router — OpenWrt Source Build

Minimal OpenWrt from **source** for MediaTek **MT7628NN** devices (ZBT WE5931-class).
Design: **Wi-Fi STA-only** WAN + **4G PPP** fallback (EC200T-class) + **USB ECM/RNDIS** fallback.
Bootloader requires legacy uImage **magic `0x27151967`** — we wrap images post-build.

---

## Features

* Target: `ramips/mt76x8` (MT7628NN)
* Wi-Fi: 2.4 GHz (mt76), STA-only (no local AP)
* WAN priority: `wwan` (DHCP) → `cell` (PPP on `/dev/ttyUSB3`) → `usb0` (ECM/RNDIS DHCP)
* Lean userspace: LuCI, firewall4/nftables, dnsmasq-full, swconfig; IPv6/storage stacks removed
* Region defaults: `country=DK`, HT20, legacy rates off, power save off
* Wrapper: converts OpenWrt uImage to vendor legacy header (magic + CRCs)

---

## Repo Layout

```
scripts/
  build_fast.sh            # fast build (toolchain prewarmed by Setup Script)
  jbonecloud_wrap.py       # legacy uImage wrapper (0x27151967, hcrc/dcrc)

(openwrt-src/)             # OpenWrt source tree (cloned by Setup Script)
```

> The **Setup Script** (in your Codex Cloud Environment) pre-clones sources, installs feeds, creates the `.config` and `FILES/` overlay, downloads sources, and builds **tools + toolchain** to make builds fast.

---

## Quick Start (Codex Cloud)

### 1) One-time: Environment → Setup Script

Use the provided `codex-env-setup.v2.sh` (from this project’s docs). It will:

* Install host deps (apt/apk)
* Configure timezone, ccache, optional swap
* Clone OpenWrt (`openwrt-src/`) + update/install feeds (with mirror fallback)
* Write `.config` (STA-only + PPP/ECM/RNDIS, no IPv6/storage)
* Create `FILES/` overlay with defaults
* Pre-warm toolchain: `make download`, `make tools/install toolchain/install`
* Drop helper scripts into `scripts/`

### 2) Start a fast build

From the repo root:

```bash
PROFILE=zbt-we5931 \
SRC_DIR="$PWD/openwrt-src" \
SCRIPTS_DIR="$PWD/scripts" \
./scripts/build_fast.sh
```

The script will fall back to `mediatek_mt7628an-eval` if the primary profile fails.

### 3) Find outputs

```
openwrt-src/bin/targets/ramips/mt76x8/
  ...sysupgrade.bin
  ...sysupgrade-jbc.bin      # wrapped (legacy header)
  ...initramfs-...-jbc.bin   # if built
  sha256sums.txt
```

---

## What the build script does

1. `make defconfig`
2. `make -j$(nproc) V=s`
3. Wrap each image → legacy uImage (magic `0x27151967`, recompute **hcrc/dcrc**)
4. Emit `sha256sums.txt`

Wrapper usage (stand-alone):

```bash
python3 scripts/jbonecloud_wrap.py <in-sysupgrade.bin> <out-sysupgrade-jbc.bin>
```

---

## Defaults (baked into FILES/)

* **Wireless (`/etc/config/wireless`)**

  * `country 'DK'`, `channel '6'`, `htmode 'HT20'`, `legacy_rates '0'`, `powersave '0'`
  * STA joins `UPSTREAM_SSID` / `UPSTREAM_PASSWORD`

* **Network (`/etc/config/network`)**

  * `lan`: 192.168.1.1/24 (bridge on `eth0`)
  * `wwan`: DHCP (metric 10)
  * `cell`: PPP on `/dev/ttyUSB3`, APN `YOUR_APN`, dial `*99#` (metric 20)
  * `wan_usb`: `usb0` DHCP (metric 30)

* **Firewall (`/etc/config/firewall`)**

  * `lan` → `wan` masquerade; zones: `lan`, `wan(wwan+cell+wan_usb)`

* **PPP (`/etc/ppp/peers/cell`, `etc/chatscripts/cell-connect`)**

  * Standard guards; configures `+CGDCONT` APN; dials `*99#`

* **USB hotplug (`/etc/hotplug.d/usb/10-modem-bind`)**

  * Loads `usbserial`, `option`, `cdc_ether`, `rndis_host`
  * Binds IDs `1286:4e3c` (seen on this unit) and optional `2c7c:6026`

> Edit SSID/PSK/APN via UCI or regenerate the overlay in Setup.

---

## Flashing (safe path)

1. **U-Boot (57600 8N1)**
   Ensure `bootcmd=tftp`, `ipaddr`, `serverip` are set.

2. **RAM-boot** (optional but safe)

   ```
   tftpboot 0x82000000 <initramfs-jbc.bin>
   bootm 0x82000000
   ```

3. **Sysupgrade from RAM system**

   ```
   sysupgrade -n /tmp/<sysupgrade-jbc.bin>
   ```

Images ending in `-jbc.bin` are already wrapped for the vendor bootloader.

---

## Troubleshooting

* **Feeds failed in Setup:** use mirror fallback (GitHub) and retry; ensure network egress.
* **Kernel ABI mismatch for kmods:** build from the **same source branch**; avoid mixing SDK/ImageBuilder outputs.
* **No WAN via Wi-Fi:** check upstream SSID/PSK; `logread | grep wpa`, `iw dev wlan0 link`, `ifstatus wwan`.
* **PPP doesn’t connect:** confirm `/dev/ttyUSB3`, `chat -V -s -f /etc/chatscripts/cell-connect`, correct APN.
* **ECM/RNDIS missing:** verify modem exposes those interfaces; hotplug binds `cdc_ether`/`rndis_host`.

---

## Hardware Notes (short)

* SoC: MT7628NN (ramips/mt76x8)
* Bootloader: Ralink U-Boot 1.1.3 (expects legacy uImage magic `0x27151967`)
* Modem control (observed): `GPIO1` → PWR_EN, `GPIO4` → RESET_N (active-low)
* LEDs: active-low; switch port LEDs are ESW-driven (not GPIO)

---

## Contributing

* Open a PR with a clear title/description.
* Include build logs (last ~200 lines), your env vars, and `sha256sums.txt`.

---

## License

* OpenWrt components are GPL-2.0; repository scripts are provided under the same unless noted.

---

### Appendix: Manual build (without Setup)

```bash
# Deps (Debian/Ubuntu)
sudo apt-get update && sudo apt-get install -y \
  build-essential g++ gawk wget unzip rsync python3 git gettext \
  libncurses5-dev zlib1g-dev file flex bison patch xz-utils tar curl ccache

# Clone & feeds
git clone --depth 1 --branch openwrt-24.10 https://git.openwrt.org/openwrt/openwrt.git openwrt-src
cd openwrt-src
./scripts/feeds update -a && ./scripts/feeds install -a

# .config (ramips/mt76x8 + packages as in this repo’s Setup)
make defconfig
make -j"$(nproc)" V=s

# Wrap
python3 ../scripts/jbonecloud_wrap.py bin/targets/ramips/mt76x8/*sysupgrade*.bin \
  bin/targets/ramips/mt76x8/openwrt-sysupgrade-jbc.bin
```
