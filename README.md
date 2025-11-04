OpenWrt MT7628NN Build — STA + 4G (Lyca DK)

Profile and Target
- Target: `ramips/mt76x8`
- Built profile: `7links_wlr-1230` (fallback: `mediatek_mt7628an-eval`)
- Kernel/ABI: from your source tree

Network Design
- Wi‑Fi: STA‑only to upstream AP (DK, HT20, no legacy rates)
- WAN: priority order — `wwan` (DHCP over STA), `cell` (PPP /dev/ttyUSB3), `usb` (ECM/RNDIS usb0)
- LAN: 192.168.1.1/24 with DHCP server

Credentials and APN
- STA SSID: `H158-381_814D`
- STA Key: `EMq4aMNTeDL`
- APN (Lyca Mobile DK): `data.lycamobile.dk` (username/password blank)

Overlay Files (baked into image)
- `files/etc/config/wireless` — STA to the SSID above
- `files/etc/config/network` — sets `wwan`, `cell` (PPP), `usb` (DHCP)
- `files/etc/config/firewall` — `lan` → `wan` (masq)
- `files/etc/config/dhcp` — DHCP on `lan` only
- `files/etc/ppp/*` — peers/chat for PPP dial (`*99#`) with APN
- `files/etc/hotplug.d/usb/10-modem-bind` — binds 1286:4e3c and 2c7c:6026 to `option`

Artifacts (wrapped to legacy uImage, magic 0x27151967)
- `bin/targets/ramips/mt76x8/openwrt-ramips-mt76x8-7links_wlr-1230-initramfs-kernel-jbc.bin` (~6.5 MB)
- `bin/targets/ramips/mt76x8/openwrt-ramips-mt76x8-7links_wlr-1230-squashfs-sysupgrade-jbc.bin` (~6.6 MB)
- Checksums: `sha256sums.txt` (repo root)

Flashing (safe path via U‑Boot + TFTP)
1) RAM‑boot initramfs (optional for first boot)
   - `tftpboot 0x82000000 openwrt-ramips-mt76x8-7links_wlr-1230-initramfs-kernel-jbc.bin`
   - `bootm 0x82000000`
2) On OpenWrt shell, copy the sysupgrade image to `/tmp` then flash clean:
   - `sysupgrade -n /tmp/openwrt-ramips-mt76x8-7links_wlr-1230-squashfs-sysupgrade-jbc.bin`

First‑boot Checks (QA)
- `ifstatus wwan` shows DHCP lease from upstream AP
- `pppd call cell` brings up `ppp0` if Wi‑Fi is unavailable
- `ifup usb` gets DHCP on `usb0` if modem exposes ECM/RNDIS
- LuCI reachable at `http://192.168.1.1/` (user: root, no password)

Changing Credentials / APN later
- STA Wi‑Fi: `uci set wireless.@wifi-iface[0].ssid='YOUR_SSID'; uci set wireless.@wifi-iface[0].key='YOUR_PASS'; uci commit wireless; wifi reload`
- APN: `uci set network.cell.apn='data.lycamobile.dk'; uci commit network; ifdown cell; ifup cell`
- Chat PDP line: edit `/etc/ppp/chat-connect` AT+CGDCONT if needed
