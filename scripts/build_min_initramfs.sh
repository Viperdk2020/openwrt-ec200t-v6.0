#!/usr/bin/env bash
set -euo pipefail

# Build a slim initramfs for RAM boot on low-RAM MT7628.
# It temporarily disables heavy packages (LuCI, Wi‑Fi, PPP, USB‑net, uHTTPd, dnsmasq-full, firewall4),
# builds only the initramfs kernel image, wraps it, copies to C:\tftp, then restores your .config.

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

rootdir=$(pwd)
conf_bak=".config.bak.slim.$(date +%s)"

cp -v .config "$conf_bak"

# Use OpenWrt helper to toggle package selections
# Disable heavy packages for initramfs by forcing CONFIG_PACKAGE_* to n
disable_pkgs=(
  luci luci-ssl uhttpd uhttpd-mod-ubus
  wpad-basic-mbedtls wpad-basic wpad-mini
  kmod-mt76 kmod-mt7603 kmod-mt76x2 kmod-mt76-core kmod-mt76-connac
  ppp chat ppp-mod-pppoe ppp-mod-pppoa
  kmod-usb-core kmod-usb2 kmod-usb-serial kmod-usb-serial-option kmod-usb-acm
  usb-modeswitch kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis
  dnsmasq-full dnsmasq firewall4 nftables kmod-nft-nat
  dropbear
)
for p in "${disable_pkgs[@]}"; do
  sym=PACKAGE_"${p//-/_}"
  # Remove any existing assignment, then force =n
  sed -i "/^CONFIG_${sym}=.*/d" .config || true
  echo "CONFIG_${sym}=n" >> .config
done

# Ensure base image settings
sed -i "/^CONFIG_TARGET_ROOTFS_INITRAMFS=.*/d" .config || true
echo "CONFIG_TARGET_ROOTFS_INITRAMFS=y" >> .config
sed -i "/^CONFIG_TARGET_INITRAMFS_COMPRESSION_.*/d" .config || true
echo "CONFIG_TARGET_INITRAMFS_COMPRESSION_LZMA=y" >> .config

# Keep target/subtarget/profile as-is, just reconcile config
make defconfig >/dev/null

echo "Building minimal initramfs kernel image..."
make -j"$(nproc)" target/linux/install V=s

imgdir=bin/targets/ramips/mt76x8
in_img="$imgdir"/*initramfs*kernel.bin
if ! ls $in_img >/dev/null 2>&1; then
  echo "Initramfs kernel image not found under $imgdir" >&2
  cp -v "$conf_bak" .config
  make defconfig >/dev/null
  exit 1
fi

# Prepare wrapper (prefer user Windows version if present)
for cand in \
  "/mnt/d/4G/new folder/jbonecloud_wrap.py" \
  "/mnt/d/4G/New folder/jbonecloud_wrap.py"; do
  if [ -f "$cand" ]; then
    mkdir -p scripts
    cp -v "$cand" scripts/jbonecloud_wrap.py
    break
  fi
done
chmod +x scripts/jbonecloud_wrap.py || true

mkdir -p /mnt/c/tftp
shopt -s nullglob
for f in $in_img; do
  out="${f%.bin}-min-jbc.bin"
  echo "Wrapping minimal initramfs: $f -> $out"
  if python3 scripts/jbonecloud_wrap.py --help 2>/dev/null | grep -q -- "-o OUTPUT"; then
    python3 scripts/jbonecloud_wrap.py -o "$out" "$f"
  else
    python3 scripts/jbonecloud_wrap.py "$f" "$out"
  fi
  cp -v "$out" /mnt/c/tftp/
done

echo "Restoring original .config..."
cp -v "$conf_bak" .config
make defconfig >/dev/null

echo "Done. Minimal initramfs wrapped and copied to C:\\tftp."
