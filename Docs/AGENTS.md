# AGENTS.md — Codex Cloud for MT7628NN Router

> Operational playbook for running Codex Cloud agents to build, wrap, validate, and release OpenWrt firmware for the MT7628NN 4G router project.

## 0) Project Snapshot (shared context)

* **Target:** ramips/mt76x8 (MT7628NN)
* **Bootloader:** Ralink U‑Boot 1.1.3; expects legacy uImage magic `0x27151967`
* **WAN design:** Wi‑Fi **STA‑only** + 4G PPP fallback (`/dev/ttyUSBx`) + USB ECM/RNDIS fallback
* **Regulatory:** `country=DK`
* **Artifacts we ship:** `*-sysupgrade-jbc.bin` (+ optional `*-initramfs-ramboot-jbc.bin`) and README

## 1) Agents (roles & responsibilities)

### A. Build Agent — *ImageBuilder orchestrator*

**Goal:** Produce a lean OpenWrt image with the exact package set and `FILES/` overlay.

* **Inputs:** Profile, package list, `FILES/` overlay tree
* **Output:** `bin/targets/.../*sysupgrade.bin` (+ initramfs if requested)
* **Constraints:** Keep IPv6/storage stacks out; include LuCI; Wi‑Fi STA‑only
* **Prompt Template:**

```text
You are the Build Agent. Using OpenWrt ImageBuilder for ramips/mt76x8:
1) Select the closest profile (zbt-we5931 or mt7628an-eval). Report which was used.
2) Build with PACKAGES exactly as listed, and include FILES=files/.
3) Print the final artifact paths and sha256sums.
4) Do not wrap images; leave that to the Wrapper Agent.
```

### B. Wrapper Agent — *JBoneCloud uImage header fixer*

**Goal:** Wrap the generated images to legacy uImage with magic `0x27151967`, validate hcrc/dcrc.

* **Inputs:** raw `*sysupgrade.bin` (and/or initramfs)
* **Output:** `*-jbc.bin` images with fixed magic & CRCs
* **Prompt Template:**

```text
You are the Wrapper Agent. Run the Python wrapper:
python3 jbonecloud_wrap.py <in-sysupgrade.bin> -o <out-sysupgrade-jbc.bin>
Repeat for initramfs if present. Print magic/hcrc/dcrc/size summary lines.
```

### C. Config Agent — *Default configs & overlays*

**Goal:** Generate `FILES/` overlay for STA-only Wi‑Fi + PPP/ECM/RNDIS fallbacks and firewall.

* **Inputs:** SSID/PSK placeholders, APN, device nodes
* **Output:** `files/etc/config/{wireless,network,firewall,dhcp}`, ppp peers/chatscripts, usb hotplug rules
* **Prompt Template:**

```text
You are the Config Agent. Create a files/ overlay with:
- STA-only wireless (country DK), no AP.
- network: lan bridge @ 192.168.1.1/24; wwan (dhcp, metric 10); cell (ppp on /dev/ttyUSB3, metric 20); wan_usb (usb0 dhcp, metric 30).
- firewall: lan->wan masquerade, zones {lan,wan} (wwan/cell/wan_usb).
- dhcp: LAN only.
- ppp: peers/chatscripts for APN=YOUR_APN, *99#.
- hotplug.d/usb: load option, cdc_ether, rndis_host; bind IDs 1286:4e3c and optionally 2c7c:6026.
Package the tree and print file contents inline.
```

### D. QA Agent — *Boot & connectivity checks*

**Goal:** Validate images and defaults before release; ensure both Wi‑Fi and 4G paths work.

* **Inputs:** jbc‑wrapped images, device boot logs, `ifstatus`/`logread`
* **Output:** A checklist report with pass/fail and next steps
* **Prompt Template:**

```text
You are the QA Agent. Verify:
- Wrapper summary shows magic 0x27151967, valid hcrc/dcrc.
- First boot: wlan STA associates and obtains DHCP (ifstatus wwan).
- Fallback: with Wi‑Fi down, `pppd call cell` brings up ppp0; with ECM/RNDIS modem, usb0 DHCP works.
- LuCI reachable at 192.168.1.1.
Produce a PASS/FAIL report and paste key log excerpts.
```

### E. Release Agent — *Packaging & notes*

**Goal:** Emit final deliverables & concise README with flashing steps.

* **Inputs:** final images, QA report
* **Output:**

  * `*-sysupgrade-jbc.bin` (and initramfs‑jbc if applicable)
  * `README.md` with: profile, Wi‑Fi defaults, flashing via TFTP RAM‑boot + `sysupgrade -n`, recovery tip
* **Prompt Template:**

```text
You are the Release Agent. Publish artifact filenames with sha256sums and sizes. Generate a README:
- Exact PROFILE used
- Wi‑Fi STA placeholder SSID/KEY
- 4G APN placeholder and where to change it
- Bootloader flow: tftpboot to RAM then sysupgrade -n
- Recovery section (enter U-Boot, tftpboot, etc.)
```

## 2) Standard Inputs & Environment

* **Profiles to try:** `zbt-we5931` → `mt7628an-eval` (fallback)
* **Kernel ABI:** derive from ImageBuilder release in use
* **Time zone:** Europe/Copenhagen
* **Output directory convention:** `bin/targets/ramips/mt76x8/`

## 3) Canonical Package Set

Add: `ppp chat kmod-usb-core kmod-usb2 kmod-usb-serial kmod-usb-serial-option kmod-usb-acm usb-modeswitch kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-mt76 wpad-basic-mbedtls firewall4 nftables kmod-nft-nat dnsmasq-full dropbear logd ip-full swconfig luci luci-ssl uhttpd ca-bundle luci-mod-network luci-app-firewall luci-proto-ppp`

Remove: `odhcp6c luci-proto-ipv6 kmod-ipv6 ppp-mod-pppoe ppp-mod-pppoa kmod-usb-storage block-mount kmod-fs-ext4 kmod-fs-vfat uqmi umbim kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim relayd kmod-ath9k kmod-ath10k-ct kmod-brcmfmac`

## 4) Core Workflows

### Workflow A — Fresh build

1. **Config Agent** produces `files/` overlay.
2. **Build Agent** runs ImageBuilder with PACKAGES + `FILES=files/`.
3. **Wrapper Agent** wraps sysupgrade/initramfs → `*-jbc.bin`.
4. **QA Agent** validates.
5. **Release Agent** emits README and checksums.

### Workflow B — Config tweak only

1. Update overlay files. 2. Re‑ImageBuilder. 3. Wrap. 4. QA. 5. Release.

## 5) Checklists

**Build Agent**

* [ ] Correct profile selected & reported
* [ ] Package diff matches canonical set
* [ ] `sha256sums` recorded

**Wrapper Agent**

* [ ] Magic `0x27151967`
* [ ] hcrc/dcrc valid
* [ ] Sizes sensible

**QA Agent**

* [ ] `ifstatus wwan` has lease
* [ ] `ppp0` comes up with APN
* [ ] `usb0` DHCP works (if modem exposes ECM/RNDIS)
* [ ] LuCI reachable, firewall zones correct

**Release Agent**

* [ ] Filenames/versioning
* [ ] README covers TFTP RAM‑boot + `sysupgrade -n`
* [ ] Recovery notes present

## 6) Command Snippets (ready to paste)

**ImageBuilder (example)**

```sh
make image PROFILE="zbt-we5931" \
  PACKAGES="ppp chat kmod-usb-core kmod-usb2 kmod-usb-serial kmod-usb-serial-option kmod-usb-acm usb-modeswitch kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-mt76 wpad-basic-mbedtls firewall4 nftables kmod-nft-nat dnsmasq-full dropbear logd ip-full swconfig luci luci-ssl uhttpd ca-bundle luci-mod-network luci-app-firewall luci-proto-ppp" \
  FILES=files/
```

**Wrap to legacy uImage (magic 0x27151967)**

```sh
python3 jbonecloud_wrap.py bin/targets/*/*/*-sysupgrade.bin \
  -o bin/targets/.../openwrt-sysupgrade-jbc.bin
```

**Quick verify**

```sh
# Expect wrapper summary lines to show magic 0x27151967 and valid hcrc/dcrc
sha256sum bin/targets/.../*jbc.bin
```

## 7) Conventions & Style

* Prefer STA‑only Wi‑Fi (no AP) to keep RF stable.
* Keep logs concise; paste only the decisive 10–20 lines.
* Use placeholders: `UPSTREAM_SSID`, `UPSTREAM_PASSWORD`, `YOUR_APN`.

## 8) Glossary

* **ImageBuilder:** Prebuilt SDK to assemble images without full source build
* **jbc wrap:** Our legacy uImage header fix for the vendor bootloader
* **STA:** Wi‑Fi station (client) mode
* **ECM/RNDIS:** USB networking modes exposed by some modems

---

*Edit this file as the single source of truth for how Codex agents should operate on this project.*
