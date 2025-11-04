#!/usr/bin/env bash
set -euo pipefail

# Ensure legacy MT7628 switch + Ethernet support is built into the image
# Adds: kmod-rt305x-esw, swconfig, kmod-mii, kmod-bridge, kmod-8021q

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ ! -f .config ]; then
  echo ".config not found; run inside OpenWrt tree" >&2
  exit 1
fi

bak=".config.bak.eth.$(date +%s)"
cp -v .config "$bak"

add_pkg() {
  local p="$1"; local sym="PACKAGE_${p//-/_}"
  sed -i "/^CONFIG_${sym}=.*/d" .config || true
  echo "CONFIG_${sym}=y" >> .config
}

add_pkg kmod-rt305x-esw
add_pkg swconfig
add_pkg kmod-mii
add_pkg kmod-bridge
add_pkg kmod-8021q

echo "Refreshing config..."
make defconfig >/dev/null

echo "Rebuilding images..."
make -j"$(nproc)" V=s

if [ -x scripts/build_and_wrap.sh ]; then
  scripts/build_and_wrap.sh
fi

echo "Done. Previous config backup: $bak"

