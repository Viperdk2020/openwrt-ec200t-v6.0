# TODO – EC200T OpenWrt Build

## Done
- Added USB modem stack: `kmod-usb-core`, `usb2`, `ohci`, serial (option/qcserial), CDC-ether/NCM/QMI, `usb-wdm`.
- Enabled switch module packaging (`kmod-rt3050-esw`) and custom version metadata (`CONFIG_VERSIONOPT`).
- Ran full rebuild (`build_and_wrap.sh`); produced new wrapped/unwrapped images.
- Flashed current build; verified banner and `/etc/openwrt_release` advertise `OpenWrt ec200t-v1, r31588+1-0861bb7405`.
- Pushed fresh `/etc/config/network` and `/etc/config/wireless`; created `br-lan`, set LAN IP, and populated Wi-Fi STA profile.

## Remaining
- Confirm switch driver loads (`rt3050-esw`) and resolve MDIO/netdev watchdog errors.
- Get Wi-Fi STA operational (`ifstatus wwan`, `ubus call network reload` still failing) and ensure netifd restarts cleanly.
- Verify wwan DHCP, wired LAN connectivity, and exercise USB-modem support once network stack stabilizes.
- General smoke test: ping WAN, confirm LuCI/ssh reachability, check logs for remaining regressions.
