# Build OpenWrt MT7628NN image (STA-only Wi-Fi + 4G/USB fallback, no local AP)

**Copy-paste this entire prompt into Codex Cloud.**

---

**Title:** Build OpenWrt MT7628NN image (STA-only Wi-Fi + 4G/USB fallback, no local AP)

**Prompt for Codex Cloud:**

> You are a build assistant. Create an OpenWrt firmware for a MediaTek MT7628NN router with these constraints:
> – Target: ramips/mt76x8 (MT7628NN). Use the most compatible PROFILE (e.g., zbt-we5931 or mt7628an-eval) and report which you used.  
> – Bootloader: Ralink U-Boot 1.1.3 (legacy uImage flow). Final images must be wrapped to legacy uImage with magic **0x27151967** and valid header/data CRCs.  
>
> ### Goals
> 1) **Wi-Fi WAN only (STA)**: the radio connects upstream to an existing AP. **No local AP**.  
> 2) **4G fallback** via PPP on `/dev/ttyUSBx` (EC200T-class), plus ECM/RNDIS fallback on `usb0`.  
> 3) Include LuCI; keep image lean (drop IPv6 and storage stacks). Set regulatory domain to Denmark.
>
> ### ImageBuilder task
> Use OpenWrt ImageBuilder for `ramips/mt76x8`. Add/remove packages exactly as below and include a `FILES/` overlay with defaults.
>
> **Packages (add/remove):**  
> Add:  
> `ppp chat kmod-usb-core kmod-usb2 kmod-usb-serial kmod-usb-serial-option kmod-usb-acm usb-modeswitch kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-mt76 wpad-basic-mbedtls firewall4 nftables kmod-nft-nat dnsmasq-full dropbear logd ip-full swconfig luci luci-ssl uhttpd ca-bundle luci-mod-network luci-app-firewall luci-proto-ppp`  
> Remove:  
> `odhcp6c luci-proto-ipv6 kmod-ipv6 ppp-mod-pppoe ppp-mod-pppoa kmod-usb-storage block-mount kmod-fs-ext4 kmod-fs-vfat uqmi umbim kmod-usb-net-qmi-wwan kmod-usb-net-cdc-mbim relayd kmod-ath9k kmod-ath10k-ct kmod-brcmfmac`
>
> **FILES/etc/config/wireless (STA-only):**
> ```uci
> config wifi-device 'radio0'
>     option type 'mac80211'
>     option path 'platform/10300000.wmac'
>     option band '2g'
>     option htmode 'HT40'
>     option channel 'auto'
>     option country 'DK'
>     option disabled '0'
>
> # Single STA interface (no AP section)
> config wifi-iface
>     option device 'radio0'
>     option mode 'sta'
>     option network 'wwan'
>     option ssid 'UPSTREAM_SSID'
>     option encryption 'psk2'
>     option key 'UPSTREAM_PASSWORD'
>     option ieee80211w '0'
> ```
>
> **FILES/etc/config/network:**
> ```uci
> config interface 'loopback'
>     option ifname 'lo'
>     option proto 'static'
>     option ipaddr '127.0.0.1'
>     option netmask '255.255.255.0'
>
> # LAN over Ethernet only (no wireless AP)
> config interface 'lan'
>     option type 'bridge'
>     option ifname 'eth0'
>     option proto 'static'
>     option ipaddr '192.168.1.1'
>     option netmask '255.255.255.0'
>
> # Wi-Fi WAN (DHCP)
> config interface 'wwan'
>     option proto 'dhcp'
>     option metric '10'
>
> # 4G PPP fallback (adjust /dev/ttyUSBx after first boot if needed)
> config interface 'cell'
>     option proto 'ppp'
>     option device '/dev/ttyUSB3'
>     option apn 'YOUR_APN'
>     option username ''
>     option password ''
>     option dialnumber '*99#'
>     option peerdns '1'
>     option ipv6 '0'
>     option metric '20'
>
> # USB ECM/RNDIS fallback
> config interface 'wan_usb'
>     option ifname 'usb0'
>     option proto 'dhcp'
>     option metric '30'
> ```
>
> **FILES/etc/config/dhcp (LAN only):**
> ```uci
> config dhcp 'lan'
>     option interface 'lan'
>     option start '100'
>     option limit '150'
>     option leasetime '12h'
> ```
>
> **FILES/etc/config/firewall:**
> ```uci
> config defaults
>     option input 'ACCEPT'
>     option output 'ACCEPT'
>     option forward 'REJECT'
>     option synflood_protect '1'
>
> config zone
>     option name 'lan'
>     list   network 'lan'
>     option input 'ACCEPT'
>     option output 'ACCEPT'
>     option forward 'ACCEPT'
>
> config zone
>     option name 'wan'
>     list   network 'wwan'
>     list   network 'cell'
>     list   network 'wan_usb'
>     option input 'REJECT'
>     option output 'ACCEPT'
>     option forward 'REJECT'
>     option masq '1'
>     option mtu_fix '1'
>
> config forwarding
>     option src 'lan'
>     option dest 'wan'
> ```
>
> **PPP chat/peers (FILES/etc/ppp/):**  
> - `peers/cell` referencing `/dev/ttyUSB3`, `usepeerdns persist noauth defaultroute replacedefaultroute`.  
> - `chatscripts/cell-connect` with `ABORT`/`TIMEOUT` guards and `AT+CGDCONT=1,"IP","YOUR_APN"`, then `ATD*99#`.  
>
> **USB hotplug (FILES/etc/hotplug.d/usb/10-modem-bind):**  
> Load `usbserial option cdc_ether rndis_host`; bind known IDs (e.g., `1286:4e3c`, optionally `2c7c:6026`).
>
> **Run ImageBuilder (example; adjust PROFILE):**
> ```
> make image PROFILE="zbt-we5931" \
>   PACKAGES="ppp chat kmod-usb-core kmod-usb2 kmod-usb-serial kmod-usb-serial-option kmod-usb-acm usb-modeswitch kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-mt76 wpad-basic-mbedtls firewall4 nftables kmod-nft-nat dnsmasq-full dropbear logd ip-full swconfig luci luci-ssl uhttpd ca-bundle luci-mod-network luci-app-firewall luci-proto-ppp" \
>   FILES=files/
> ```
>
> ### Post-build: vendor header wrap
> Use the provided Python wrapper to emit legacy uImage with magic 0x27151967 and fresh CRCs:
> ```
> python3 jbonecloud_wrap.py bin/targets/*/*/*-sysupgrade.bin \
>   -o bin/targets/.../openwrt-sysupgrade-jbc.bin
> ```
> Repeat for initramfs if produced. Print the wrapper’s summary lines.
>
> ### Deliverables
> 1) `*-sysupgrade-jbc.bin` (and initramfs-jbc if applicable).  
> 2) README with: chosen PROFILE, STA-only Wi-Fi defaults (SSID/password placeholders), and quick start:
>    - TFTP RAM-boot if needed (bootloader uses `bootcmd=tftp`), then `sysupgrade -n /tmp/*jbc.bin`.
>
> ### Quick verification checklist (echo at the end)
> – Wrapper reports magic 0x27151967 and valid hcrc/dcrc.  
> – `ifstatus wwan` shows DHCP lease.  
> – `pppd call cell` brings up `ppp0` if Wi-Fi is unavailable.  
> – `usb0` can obtain DHCP when modem exposes ECM/RNDIS`.

