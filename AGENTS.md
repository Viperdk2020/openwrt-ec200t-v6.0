# AGENTS.md — Source Build Mode (MT7628NN)

Operational playbook for Codex Cloud **source builds** of OpenWrt for the MT7628NN 4G router. This replaces ImageBuilder-centric flows.

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

* **Inputs:** `OPENWRT_GIT`, `OPENWRT_BRANCH`
* **Output:** Ready source tree in `${SRC_DIR}`
* **Prompt template:**

```
You are the Repo Agent. Clone the OpenWrt repo (branch ${OPENWRT_BRANCH}) into ${SRC_DIR}. Run `./scripts/feeds update -a && ./scripts/feeds install -a`. Print commit and feed refs.
```

### B) **Config Agent** — *Generate .config + FILES overlay*

**Goal:** Produce `.config` targeting `ramips/mt76x8` and our package set; create `FILES/` overlay for STA-only + PPP/ECM/RNDIS.

* **Inputs:** `TARGET`, `SUBTARGET`, `PROFILE`, SSID/PSK placeholders, `APN`
* **Output:** `.config`, `files/etc/config/{wireless,network,firewall,dhcp}`, `files/etc/ppp/*`, `files/etc/hotplug.d/usb/10-modem-bind`
* **Prompt template:**

```
You are the Config Agent. Write .config enabling: luci, firewall4/nft, mt76, wpad-basic-mbedtls, ppp/chat, USB serial + ACM, USB net (cdc-ether, rndis). Explicitly omit IPv6, storage, QMI/MBIM. Generate FILES overlay for STA-only (DK), wwan dhcp metric 10, ppp cell on /dev/ttyUSB3 metric 20, usb0 dhcp metric 30, firewall lan->wan, dhcp on lan only, chatscripts with APN placeholder, usb hotplug binding 1286:4e3c and optional 2c7c:6026. Print all files.
```

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

* **Prompt hint:** run lightweight updates and `./scripts/feeds update -a && install -a` if `${SRC_DIR}` exists.

---

## 2) Environment & Variables

Set as Codex env vars or inline in prompts:

```
OPENWRT_GIT=https://git.openwrt.org/openwrt/openwrt.git
OPENWRT_BRANCH=openwrt-24.10
TARGET=ramips
SUBTARGET=mt76x8
PROFILE=zbt-we5931            # fallback: mediatek_mt7628an-eval
SRC_DIR=$PWD/openwrt-src
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

### Workflow A — Fresh **source** build

1. **Repo Agent** → clone + feeds
2. **Config Agent** → `.config` + `FILES/`
3. **Build Agent** → compile (fallback profile if needed)
4. **Wrapper Agent** → `*-jbc.bin`
5. **QA Agent** → sanity checks
6. **Release Agent** → checksums + README

### Workflow B — Config-only tweak

1. Update overlay; 2. re-`make` (no toolchain rebuild); 3. wrap; 4. QA; 5. release

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
