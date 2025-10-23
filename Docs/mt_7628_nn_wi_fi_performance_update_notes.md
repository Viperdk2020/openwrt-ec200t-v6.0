# MT7628NN Wi‑Fi Performance Update Notes

**Scope:** Steps to improve Wi‑Fi performance on the MT7628NN (ramips/mt76x8) in our STA‑only design. Covers quick config wins, driver refresh with OpenWrt SDK, and validation.

---

## 1) Quick wins (no rebuild)
Apply these first; they often yield the biggest gains on 2.4 GHz.

### A. Disable power save on STA
```sh
# one‑shot (until reboot)
iw dev wlan0 set power_save off

# persistent (UCI)
uci set wireless.radio0.powersave='0'
uci commit wireless && wifi reload
```

### B. Use clean channel + sane width
- Prefer **HT20** in busy areas; enable **HT40** only if spectrum is clean.
- Fix the channel to **1, 6, or 11** after a quick scan:
```sh
iw dev wlan0 scan | grep -E 'SSID|primary channel|signal'
uci set wireless.radio0.channel='6'        # pick 1/6/11 based on scan
uci set wireless.radio0.htmode='HT20'
uci commit wireless && wifi reload
```

### C. Drop legacy 802.11b rates (saves airtime)
```sh
uci set wireless.radio0.legacy_rates='0'
uci commit wireless && wifi reload
```

### D. Keep WMM + Short GI on
```sh
uci set wireless.default_radio0.wmm='1'
uci set wireless.radio0.short_gi_20='1'    # 20 MHz SGI
uci commit wireless && wifi reload
```

### E. Country + TX power sanity
```sh
uci set wireless.radio0.country='DK'
uci set wireless.radio0.txpower='20'   # keep legal/EVM‑friendly; try 18–20 dBm
uci commit wireless && wifi reload
```

### F. ACK timing (distance)
If links are long (outdoor), set distance in meters (improves ACK window):
```sh
uci set wireless.radio0.distance='50'   # example: 50 m
uci commit wireless && wifi reload
```

---

## 2) Driver/stack refresh (mt76) — with OpenWrt SDK
**Goal:** Rebuild **kmod‑mt76** (and friends) matching our kernel ABI (**6.12.51**), optionally pulling a newer mt76 from OpenWrt’s branch.

> **Note:** ImageBuilder cannot build kernel modules; use the **OpenWrt SDK** that matches your release & target.

### A. Get the right SDK
```sh
# choose SDK matching ramips/mt76x8 + kernel 6.12.51
# (place the downloaded tar.xz on the build host)
tar -xf openwrt-sdk-*-ramips-mt76x8_6.12.51*.tar.xz
cd openwrt-sdk-*-ramips-mt76x8*
./scripts/feeds update -a && ./scripts/feeds install -a
```

### B. (Optional) Bump mt76 to newer snapshot
- Edit `package/kernel/mt76/Makefile` to a newer commit/hash (advanced). Keep mac80211/compat versions compatible.
- Or stay with the SDK’s default (safer).

### C. Build mt76 and dependencies
```sh
make defconfig
# build all mt76 subdrivers used by MT7628 (mt76, mt7603, mt76x02)
make package/kernel/mt76/compile -j$(nproc)
```
Artifacts will appear under `bin/packages/mipsel_24kc/base/` and `packages/` subdirs.

### D. Install on the router (same kernel ABI)
```sh
# copy over via scp, then:
opkg update
opkg remove kmod-mt76* --force-depends
opkg install ./kmod-mt76_*.ipk ./kmod-mt76x02_*.ipk ./kmod-mt7603_*.ipk
# reboot to load the refreshed modules
reboot
```

> **Heads‑up:** Ensure the `kmod-` packages’ **kernel version** exactly matches `uname -r` (6.12.51). If not, rebuild with the correct SDK or export `KERNEL_PATCHVER` accordingly.

---

## 3) EEPROM/Factory calibration sanity
The MT7628 reads RF calibration from the **factory** partition (64 KB). Before and after a driver update, verify:
```sh
hexdump -C /dev/mtdblock3 | head    # adjust index if factory is mtd4/mtdX
logread | grep -i -E 'eeprom|cal|mt76|mt7603'
```
Expect logs to mention loading EEPROM data; absence or CRC errors will degrade performance.

---

## 4) STA roaming & reliability (wpa_supplicant)
- Increase scan quality without thrashing:
```sh
# example: moderate bgscan
uci set wireless.default_radio0.bgscan='simple:30:-65:300'  # scan every 30s, roam if worse than -65 dBm for 300s
uci commit wireless && wifi reload
```
- If upstream AP is fixed and strong, you can **disable bgscan** entirely for throughput stability (omit the bgscan option).

---

## 5) Validation (before/after)
Run each test **twice** (baseline, then after changes):
```sh
# link quality snapshot
iw dev wlan0 link

# local PHY rate + retries (watch for 1–2 minutes)
iw dev wlan0 station dump | sed -n '1,120p'

# ping/jitter
ping -c 100 <gateway-ip>

# iperf3 (if a server is available on the LAN/WAN side)
iperf3 -R -c <server-ip>   # reverse for DL throughput
```
Capture: RSSI, TX bitrate, MCS, retries, ping avg/99th, and iperf3 Mbps.

---

## 6) Rollback plan
All changes in §1 are UCI‑based — revert by deleting the options and `wifi reload`. For §2 module updates, keep the original `kmod-mt76*.ipk` to reinstall, or reflash the last known‑good sysupgrade.

---

## 7) Troubleshooting tips
- **High retries / rate oscillation:** force HT20, drop legacy rates, reduce TX power by 2–4 dB.
- **Throughput caps at ~20–30 Mbps:** confirm WMM on, power save off, and upstream AP isn’t using 20/40 coexistence penalties.
- **Driver mismatch errors on opkg install:** kernel ABI mismatch — rebuild kmods with matching SDK.
- **EEPROM/Cal errors:** back up `factory` partition and verify it’s readable; do not overwrite it.

---

## 8) Appendix — minimal STA profile (recap)
```uci
config wifi-device 'radio0'
    option type 'mac80211'
    option path 'platform/10300000.wmac'
    option band '2g'
    option channel '6'
    option htmode 'HT20'
    option country 'DK'
    option legacy_rates '0'
    option powersave '0'

config wifi-iface
    option device 'radio0'
    option mode 'sta'
    option network 'wwan'
    option ssid 'UPSTREAM_SSID'
    option encryption 'psk2'
    option key 'UPSTREAM_PASSWORD'
    # optional roaming tune
    # option bgscan 'simple:30:-65:300'
```

