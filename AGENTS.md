# AGENTS.md — Source Build Mode (MT7628NN)

Operational playbook for Codex Cloud source builds of OpenWrt for the MT7628NN 4G router.

remember one step at a time and if you ask a question wait for me to answer
---

## 0) Project Snapshot

* **Target/Subtarget:** `ramips/mt76x8` (MT7628NN)
* **Bootloader:** Ralink U‑Boot 1.1.3, expects legacy uImage **magic `0x27151967`** with valid hcrc/dcrc (we wrap post-build)
* **WAN design:** Wi‑Fi **STA‑only** + 4G PPP (`/dev/ttyUSBx`) + USB ECM/RNDIS fallback
* **Region:** `country=DK`
* **Primary profile:** `zbt-we5931` → fallback `mediatek_mt7628an-eval`
* **Kernel ABI:** from source branch (keep kmods consistent)
* **Artifacts:** `*-sysupgrade-jbc.bin` (+ optional `*-initramfs-ramboot-jbc.bin`), `sha256sums.txt`, `README.md`

---

## 1) Agents (roles & prompts)

### A) **Repo Agent** — *Clone & prepare tree*

**Goal:** Clone OpenWrt sources + feeds on the requested branch.

- **Inputs:** `OPENWRT_GIT`, `OPENWRT_BRANCH`
- **Output:** Ready source tree in `${SRC_DIR}`
- **Prompt template:**

```
You are the Repo Agent. Clone the OpenWrt repo (branch ${OPENWRT_BRANCH}) into ${SRC_DIR}. Run `./scripts/feeds update -a && ./scripts/feeds install -a`. Print commit and feed refs.
```

Steps
- Ensure `${SRC_DIR}` parent exists; create `${SRC_DIR}` if missing.
- Shallow-clone `${OPENWRT_GIT}` at `${OPENWRT_BRANCH}` into `${SRC_DIR}`.
- Enter `${SRC_DIR}`; set `TZ` if provided; print `git rev-parse HEAD`.
- Update/install feeds: `./scripts/feeds update -a && ./scripts/feeds install -a`.
- Print feeds refs: `./scripts/feeds list -sf` and first 10 lines of `feeds.conf.default`.
- Cache toolchain prerequisites (ccache) if available; print `gcc -v` and `ld --version` first line.

Commands (reference)
```sh
mkdir -p "${SRC_DIR}"
git clone -b "${OPENWRT_BRANCH}" --single-branch --depth 1 "${OPENWRT_GIT}" "${SRC_DIR}"
cd "${SRC_DIR}"
git rev-parse HEAD
./scripts/feeds update -a && ./scripts/feeds install -a
./scripts/feeds list -sf | sed -n '1,50p'
head -n 10 feeds.conf.default || true
command -v ccache && ccache -s || true
gcc -v 2>&1 | tail -n 1
ld --version | head -n 1
```

Outputs
- One line with “OpenWrt commit: <sha> (<branch>)”.
- Feeds list shown (names + sources) and no errors.
- Confirmation of `${SRC_DIR}` absolute path.

### B) **Config Agent** — *Generate .config + FILES overlay*

**Goal:** Produce `.config` targeting `ramips/mt76x8` and our package set; create `FILES/` overlay for STA-only + PPP/ECM/RNDIS.

* **Inputs:** `TARGET`, `SUBTARGET`, `PROFILE`, SSID/PSK placeholders, `APN`
* **Output:** `.config`, `files/etc/config/{wireless,network,firewall,dhcp}`, `files/etc/ppp/*`, `files/etc/hotplug.d/usb/10-modem-bind`
* **Prompt template:**

```
You are the Config Agent. Write .config enabling: luci, firewall4/nft, mt76, wpad-basic-mbedtls, ppp/chat, USB serial + ACM, USB net (cdc-ether, rndis). Explicitly omit IPv6, storage, QMI/MBIM. Generate FILES overlay for STA-only (DK), wwan dhcp metric 10, ppp cell on /dev/ttyUSB3 metric 20, usb0 dhcp metric 30, firewall lan->wan, dhcp on lan only, chatscripts with APN placeholder, usb hotplug binding 1286:4e3c and optional 2c7c:6026. Print all files.
```

Steps
- Enter `${SRC_DIR}`; ensure a clean baseline: `rm -f .config` (idempotent) and `make defconfig`.
- Create minimal profile selection in `.config` for `${TARGET}/${SUBTARGET}` and `${PROFILE}`.
- Append package policy: include required packages; explicitly `# unset` excluded ones.
- Run `make defconfig` to expand deps; print selected profile line back.
- Create `files/` overlay with network, wireless, firewall, DHCP, PPP chat, and USB hotplug rules.
- Validate overlay syntax with `uci -c files/etc/config export` (best-effort) and list all created files.

Commands (reference)
```sh
cd "${SRC_DIR}"
rm -f .config
cat > .config <<'CFG'
CONFIG_TARGET_${TARGET}=y
CONFIG_TARGET_${TARGET}_${SUBTARGET}=y
CONFIG_TARGET_DEVICE_${TARGET}_${SUBTARGET}_DEVICE_${PROFILE}=y

# Core services
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-ssl=y
CONFIG_PACKAGE_uhttpd=y
CONFIG_PACKAGE_dnsmasq-full=y
CONFIG_PACKAGE_firewall4=y
CONFIG_PACKAGE_nftables=y
CONFIG_PACKAGE_kmod-nft-nat=y
CONFIG_PACKAGE_dropbear=y
CONFIG_PACKAGE_ip-full=y
CONFIG_PACKAGE_swconfig=y

# Wi-Fi
CONFIG_PACKAGE_kmod-mt76=y
CONFIG_PACKAGE_wpad-basic-mbedtls=y

# USB + modem (serial, ACM, ECM/RNDIS only)
CONFIG_PACKAGE_kmod-usb-core=y
CONFIG_PACKAGE_kmod-usb2=y
CONFIG_PACKAGE_kmod-usb-serial=y
CONFIG_PACKAGE_kmod-usb-serial-option=y
CONFIG_PACKAGE_kmod-usb-acm=y
CONFIG_PACKAGE_usb-modeswitch=y
CONFIG_PACKAGE_kmod-usb-net=y
CONFIG_PACKAGE_kmod-usb-net-cdc-ether=y
CONFIG_PACKAGE_kmod-usb-net-rndis=y

# PPP (fallback over /dev/ttyUSBx)
CONFIG_PACKAGE_ppp=y
CONFIG_PACKAGE_chat=y

# Explicitly omit
# CONFIG_PACKAGE_odhcp6c is not set
# CONFIG_PACKAGE_luci-proto-ipv6 is not set
# CONFIG_PACKAGE_kmod-ipv6 is not set
# CONFIG_PACKAGE_ppp-mod-pppoe is not set
# CONFIG_PACKAGE_ppp-mod-pppoa is not set
# CONFIG_PACKAGE_kmod-usb-storage is not set
# CONFIG_PACKAGE_block-mount is not set
# CONFIG_PACKAGE_kmod-fs-ext4 is not set
# CONFIG_PACKAGE_kmod-fs-vfat is not set
# CONFIG_PACKAGE_uqmi is not set
# CONFIG_PACKAGE_umbim is not set
# CONFIG_PACKAGE_kmod-usb-net-qmi-wwan is not set
# CONFIG_PACKAGE_kmod-usb-net-cdc-mbim is not set
CFG

make defconfig
grep -E "^CONFIG_TARGET_DEVICE_.*${PROFILE}=y" .config || true

# Overlay
install -d files/etc/config files/etc/ppp files/etc/hotplug.d/usb

cat > files/etc/config/wireless <<'UCIW'
config wifi-device 'radio0'
  option type 'mac80211'
  option path 'platform/10300000.wmac'
  option htmode 'HT20'
  option country 'DK'

config wifi-iface 'wwan'
  option device 'radio0'
  option mode 'sta'
  option ssid 'UPSTREAM_SSID'
  option encryption 'psk2'
  option key 'UPSTREAM_PASSWORD'
UCIW

cat > files/etc/config/network <<'UCIN'
config interface 'loopback'
  option device 'lo'
  option proto 'static'
  option ipaddr '127.0.0.1'
  option netmask '255.0.0.0'

config device
  option name 'br-lan'
  option type 'bridge'
  list ports 'eth0.1'

config interface 'lan'
  option device 'br-lan'
  option proto 'static'
  option ipaddr '192.168.1.1'
  option netmask '255.255.255.0'

config interface 'wwan'
  option proto 'dhcp'
  option metric '10'

config interface 'cell'
  option ifname 'ppp0'
  option proto 'ppp'
  option metric '20'
  option peerdns '1'
  option defaultroute '1'
  option delegate '0'
  option ipv6 '0'
  option username '""'
  option password '""'
  option dialnumber '*99#'
  option device '/dev/ttyUSB3'
  option apn 'YOUR_APN'

config interface 'usb0'
  option ifname 'usb0'
  option proto 'dhcp'
  option metric '30'
UCIN

cat > files/etc/config/firewall <<'UCIF'
config defaults
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'REJECT'

config zone
  option name 'lan'
  list network 'lan'
  option input 'ACCEPT'
  option output 'ACCEPT'
  option forward 'ACCEPT'

config zone
  option name 'wan'
  list network 'wwan'
  list network 'cell'
  list network 'usb0'
  option input 'REJECT'
  option output 'ACCEPT'
  option forward 'REJECT'
  option masq '1'
  option mtu_fix '1'

config forwarding
  option src 'lan'
  option dest 'wan'
UCIF

cat > files/etc/config/dhcp <<'UCID'
config dnsmasq
  option domainneeded '1'
  option boguspriv '1'
  option filterwin2k '0'
  option localise_queries '1'
  option rebind_protection '1'
  option rebind_localhost '1'
  option local '/lan/'
  option domain 'lan'
  option expandhosts '1'
  option nonegcache '0'
  option authoritative '1'
  option readethers '1'
  option leasefile '/tmp/dhcp.leases'
  option resolvfile '/tmp/resolv.conf.d/resolv.conf.auto'

config dhcp 'lan'
  option interface 'lan'
  option start '100'
  option limit '150'
  option leasetime '12h'

config dhcp 'wan'
  option interface 'wan'
  option ignore '1'
UCID

cat > files/etc/ppp/chat-connect <<'CHATC'
ABORT   "NO CARRIER"
ABORT   "ERROR"
ABORT   "NO DIALTONE"
ABORT   "BUSY"
ABORT   "NO ANSWER"
REPORT  CONNECT
TIMEOUT 10
""      AT
OK      ATE1
OK      AT+CFUN=1
OK      AT+CGDCONT=1,\"IP\",\"YOUR_APN\"
OK      ATD*99#
CONNECT \c
CHATC
chmod 0644 files/etc/ppp/chat-connect

cat > files/etc/ppp/peers/cell <<'PEER'
connect "/usr/sbin/chat -v -f /etc/ppp/chat-connect"
noauth
defaultroute
usepeerdns
persist
nodetach
debug
call-provider
PEER

cat > files/etc/hotplug.d/usb/10-modem-bind <<'HP'
#!/bin/sh
[ "$ACTION" = add ] || exit 0
VIDPID="${PRODUCT%%/*}" # not used; use full triple
case "$PRODUCT" in
  1286/4e3c/*|2c7c/6026/*)
    logger -t modem-bind "Binding EC200x class modem ($PRODUCT)"
    echo 1 > /sys/bus/usb/devices/$DEVPATH/authorized
    ;;
esac
HP
chmod +x files/etc/hotplug.d/usb/10-modem-bind

echo "FILES overlay created under: $(pwd)/files"
find files -type f -maxdepth 4 -print | sed -n '1,200p'
```

Outputs
- `.config` includes `${TARGET}/${SUBTARGET}` and `${PROFILE}` selections.
- `files/` tree with config snippets for STA-only + PPP/ECM/RNDIS.
- A printed list of all created files.

### C) **Build Agent** — *Compile from source*

**Goal:** Build OpenWrt with the produced `.config`.

* **Inputs:** source tree, toolchain, `.config`
* **Output:** `bin/targets/ramips/mt76x8/*sysupgrade.bin` (+ initramfs if configured)
* **Prompt template:**

```
You are the Build Agent. Run `make defconfig` then `make -j$(nproc) V=s`. If the selected PROFILE fails, switch to `mediatek_mt7628an-eval`, re-run defconfig and build. Print the artifact directory and sizes.
```

### D) **Wrapper Agent** — *Legacy uImage header fix*

**Goal:** Wrap images to legacy uImage (magic 0x27151967) and recompute both CRCs.

* **Inputs:** raw sysupgrade/initramfs images, `jbonecloud_wrap.py`
* **Output:** `*-jbc.bin`
* **Prompt template:**

```
You are the Wrapper Agent. For each sysupgrade/initramfs image, run `python3 scripts/jbonecloud_wrap.py <in> <out>`. Print the summary (magic, hcrc, dcrc, size).
```

### E) **QA Agent** — *Sanity & connectivity*

**Goal:** Verify header wrap + boot/connectivity basics.

* **Inputs:** wrapper summaries, first-boot logs/commands
* **Output:** PASS/FAIL report with next steps
* **Prompt template:**

```
You are the QA Agent. Confirm wrapper reported magic 0x27151967 and valid CRCs. On device: ensure STA gets DHCP (`ifstatus wwan`), PPP fallback works (`pppd call cell` → ppp0), ECM/RNDIS DHCP on usb0 works when exposed, LuCI reachable at 192.168.1.1. Paste key log lines only.
```

### F) **Release Agent** — *Publish & document*

**Goal:** Emit checksums and README with flashing instructions.

* **Inputs:** wrapped images, QA status
* **Output:** `sha256sums.txt`, `README.md`
* **Prompt template:**

```
You are the Release Agent. Produce sha256sums for all *jbc.bin files. Generate README with: profile used; Wi‑Fi STA placeholders; APN placeholder and where to change; safe flashing path (U‑Boot tftp RAM‑boot → sysupgrade -n); recovery note. List final artifact names and sizes.
```

### G) **Maintenance Agent** — *Cached container refresh (optional)*

**Goal:** On cached containers, refresh minimal tools, feeds, ccache, optional swap.

**Prompt hint:** run lightweight updates and `./scripts/feeds update -a && install -a` if `${SRC_DIR}` exists.

---

## 2) Environment & Variables

Set as Codex env vars or inline in prompts:

```
OPENWRT_GIT=https://git.openwrt.org/openwrt/openwrt.git
OPENWRT_BRANCH=openwrt-24.10
TARGET=ramips
SUBTARGET=mt76x8
PROFILE=zbt-we5931            # fallback: mediatek_mt7628an-eval
SRC_DIR=$PWD                  # Build from repo root
STA_SSID=UPSTREAM_SSID
STA_KEY=UPSTREAM_PASSWORD
APN=YOUR_APN
TZ=Europe/Copenhagen
```

**Host deps (apt):** `build-essential g++ gawk wget unzip rsync python3 git gettext libncurses5-dev zlib1g-dev file flex bison patch xz-utils tar curl ccache ca-certificates time`

---

## 3) Canonical Package Policy

* **Include:** luci, luci-ssl, uhttpd, dnsmasq-full, firewall4, nftables, kmod-nft-nat, dropbear, ip-full, swconfig, kmod-mt76, wpad-basic-mbedtls, ppp, chat, kmod-usb-core, kmod-usb2, kmod-usb-serial, kmod-usb-serial-option, kmod-usb-acm, usb-modeswitch, kmod-usb-net, kmod-usb-net-cdc-ether, kmod-usb-net-rndis
* **Exclude:** odhcp6c, luci-proto-ipv6, kmod-ipv6, ppp-mod-pppoe, ppp-mod-pppoa, kmod-usb-storage, block-mount, kmod-fs-ext4, kmod-fs-vfat, uqmi, umbim, kmod-usb-net-qmi-wwan, kmod-usb-net-cdc-mbim, relayd, ath/brcm wifi kmods

---

## 4) Workflows

### Workflow A — Fresh **source** build (root tree)

1. **Repo Agent** → clone into current repo root + feeds
2. **Config Agent** → `.config` + `FILES/` in root
3. **Build Agent** → compile (fallback profile if needed)
4. **Wrapper Agent** → `*-jbc.bin`
5. **QA Agent** → sanity checks
6. **Release Agent** → checksums + README

### Workflow B — Config-only tweak

1. Update overlay; 2. re-`make` (no toolchain rebuild); 3. wrap; 4. QA; 5. release

---

## Quick Build (root)

- Ensure deps installed, then from repo root run:
- `./scripts/feeds update -a && ./scripts/feeds install -a`
- `printf "%s\n" "CONFIG_TARGET_ramips=y" "CONFIG_TARGET_ramips_mt76x8=y" "CONFIG_TARGET_DEVICE_ramips_mt76x8_DEVICE_custom_ec200t=y" > .config`
- `make defconfig`
- `scripts/build_and_wrap.sh`
  (or set the correct symbol directly: `CONFIG_TARGET_ramips_mt76x8_DEVICE_custom_ec200t=y`)
- Wrapped images copy to `C:\tftp` (WSL path `/mnt/c/tftp`).
- Artifacts also in `bin/targets/ramips/mt76x8/`.

Note: To rebuild quickly after config-only changes, rerun `scripts/build_and_wrap.sh`.

---

## 5) Checklists

**Repo Agent**

* [ ] Correct branch cloned; feeds updated/installed

**Config Agent**

* [ ] `.config` targets ramips/mt76x8; profile set
* [ ] Packages match policy; FILES overlay complete

**Build Agent**

* [ ] `make defconfig` successful; build completes
* [ ] Fallback profile attempted if primary fails

**Wrapper Agent**

* [ ] Magic `0x27151967` shown
* [ ] hcrc/dcrc valid; sizes sensible

**QA Agent**

* [ ] `ifstatus wwan` has DHCP lease
* [ ] `ppp0` comes up with APN
* [ ] `usb0` DHCP works when modem exposes ECM/RNDIS
* [ ] LuCI reachable; firewall zones correct

**Release Agent**

* [ ] sha256sums emitted
* [ ] README includes flashing + recovery
* [ ] Filenames and sizes listed

---

## 6) Standard Commands (reference)

```sh
# Build
make defconfig
make -j"$(nproc)" V=s

# Wrap to legacy uImage
python3 scripts/jbonecloud_wrap.py bin/targets/*/*/*sysupgrade*.bin \
  bin/targets/.../openwrt-sysupgrade-jbc.bin

# Verify
sha256sum bin/targets/.../*jbc.bin
```

---

## 7) Conventions

* Keep logs concise; paste only decisive lines.
* Use placeholders (`UPSTREAM_SSID`, `UPSTREAM_PASSWORD`, `YOUR_APN`).
* Prefer **HT20** unless spectrum is clean; disable powersave & legacy rates by default.

---

*Save this file at the repo root as `AGENTS.md`.*
