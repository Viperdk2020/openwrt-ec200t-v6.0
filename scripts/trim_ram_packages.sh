#!/usr/bin/env bash
set -euo pipefail

# Exclude RAM-hungry services from the permanent image
# - mwan3, relayd, uhttpd (and its ubus module)
# Keeps your 64MB MT7628 build leaner.

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

if [ ! -f .config ]; then
  echo ".config not found in current directory" >&2
  exit 1
fi

bak=".config.bak.trim.$(date +%s)"
cp -v .config "$bak"

# Packages to force off
pkgs=(
  uhttpd
  uhttpd-mod-ubus
  relayd
  mwan3
  mwan3helper
)

for p in "${pkgs[@]}"; do
  sym=PACKAGE_"${p//-/_}"
  sed -i "/^CONFIG_${sym}=.*/d" .config || true
  echo "CONFIG_${sym}=n" >> .config
done

echo "Refreshing config (defconfig) ..."
make defconfig >/dev/null

echo "Rebuilding images ..."
make -j"$(nproc)" V=s

# Wrap and copy using existing helper if present
if [ -x scripts/build_and_wrap.sh ]; then
  echo "Wrapping and copying images ..."
  scripts/build_and_wrap.sh
else
  echo "Note: scripts/build_and_wrap.sh not executable or missing; skipping wrap/copy."
fi

echo "Done. Previous config backup: $bak"

