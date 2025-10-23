# 4G Router / Wi-Fi Repeater — Final Working Configuration

**Hardware:** Custom MT7628 EC200T LTE Router  
**Firmware:** OpenWrt (custom build)

---

## 📶 Wireless
**/etc/config/wireless**
```bash
config wifi-device 'radio0'
        option type 'mac80211'
        option path 'platform/10300000.wmac'
        option band '2g'
        option channel '9'
        option htmode 'HT20'
        option country 'DK'

# Upstream STA (Wi-Fi client)
config wifi-iface 'sta'
        option device 'radio0'
        option mode 'sta'
        option network 'wwan'
        option ssid 'H158-381_814D'
        option encryption 'psk2'
        option key 'EMq4aMNTeDL'
        option ieee80211w '0'

# Local AP (for clients)
config wifi-iface 'ap'
        option device 'radio0'
        option mode 'ap'
        option network 'lan'
        option ssid 'OpenWrt_Ext'
        option encryption 'psk2'
        option key 'MyRepeater123'
        option ieee80211w '0'
```
✅ both AP + STA auto-sync to the same channel (single-radio repeater).

---

## 🌐 Network
**/etc/config/network (relevant parts)**
```bash
config interface 'lan'
        option type 'bridge'
        option ifname 'eth0.1 phy0-ap0'
        option proto 'static'
        option ipaddr '192.168.1.1'
        option netmask '255.255.255.0'

config interface 'wwan'
        option proto 'dhcp'
        option ifname 'phy0-sta0'
```

---

## 🔄 Automatic Wi-Fi Channel Sync
**/etc/hotplug.d/iface/95-wwan-autosync**
```bash
#!/bin/sh
[ "$ACTION" = "ifup" ] || exit 0
[ "$INTERFACE" = "wwan" ] || exit 0
STA_DEV="phy0-sta0"
CHAN="$(iw dev "$STA_DEV" info 2>/dev/null | awk '/channel/ {print $2}')"
[ -n "$CHAN" ] || exit 0
uci set wireless.radio0.channel="$CHAN"
uci set wireless.radio0.htmode='HT20'
uci commit wireless
logger -t autosync "wwan ifup: syncing AP channel to $CHAN"
wifi reload
```

---

## 🧩 Connectivity Watchdog
**/usr/bin/wwan-watchdog.sh**
```bash
#!/bin/sh
IFACE="$(uci -q get network.wwan.ifname || echo phy0-sta0)"
GW="$(ip -4 route show dev "$IFACE" | awk '/^default/ {print $3; exit}')"
for T in ${GW:+$GW} 8.8.8.8 1.1.1.1; do
  ping -I "$IFACE" -c1 -W2 "$T" >/dev/null 2>&1 && exit 0
done
logger -t wwan-watchdog "link check failed on $IFACE (gw=${GW:-none}); cycling wwan"
ifdown wwan 2>/dev/null
sleep 2
ifup wwan
```

---

## ⏰ Cron Jobs
**/etc/crontabs/root**
```
*/1 * * * * /usr/bin/wwan-watchdog.sh
0 5 * * * reboot
```
✅ self-healing every minute  
✅ clean daily reboot (5 AM)

---

## 🧾 Operational Summary
- Router joins **H158-381_814D** on ch9.  
- Rebroadcasts as **OpenWrt_Ext (MyRepeater123)**.  
- NAT and DHCP working on 192.168.1.1.  
- Auto-sync keeps both on same channel after reboots.  
- Watchdog repairs link if upstream fails.  
- Full persistence across power cycles.
