#!/usr/bin/env bash
set -euo pipefail

# Clean PATH to avoid WSL Windows entries breaking find -execdir
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

# Ensure overlay and scripts exist (already tracked in repo)
chmod +x files/etc/hotplug.d/usb/10-modem-bind || true

# Prefer user-provided Windows wrapper if available, then ensure exec bit
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

# Ensure target profile is set (default to custom_ec200t)
if ! grep -q '^CONFIG_TARGET_ramips_mt76x8_DEVICE_custom_ec200t=y' .config 2>/dev/null; then
  echo "[info] Selecting default device: custom_ec200t (ramips/mt76x8)"
  cat > .config <<'CFG'
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt76x8=y
CONFIG_TARGET_ramips_mt76x8_DEVICE_custom_ec200t=y
CFG
fi

# Prepare and build
make defconfig
# Build only our target device regardless of default profile
make -j"$(nproc)" V=s TARGET_DEVICES=custom_ec200t

# Wrap and copy to Windows TFTP
shopt -s nullglob
outdir="/mnt/c/tftp"
mkdir -p "$outdir"
for f in bin/targets/ramips/mt76x8/*sysupgrade*.bin bin/targets/ramips/mt76x8/*initramfs*; do
  [ -f "$f" ] || continue
  # Skip already-wrapped images
  case "$f" in *-jbc.bin) continue ;; esac
  out="${f%.bin}-jbc.bin"
  # Support both wrapper CLIs: our simple one (<in> <out>) and the Windows one (-o <out> <in>)
  if python3 scripts/jbonecloud_wrap.py --help 2>/dev/null | grep -Fq -- "-o OUTPUT"; then
    python3 scripts/jbonecloud_wrap.py -o "$out" "$f"
  else
    python3 scripts/jbonecloud_wrap.py "$f" "$out"
  fi
  cp -v "$out" "$outdir/"
done

# Checksums
if ls bin/targets/ramips/mt76x8/*-jbc.bin >/dev/null 2>&1; then
  sha256sum bin/targets/ramips/mt76x8/*-jbc.bin | tee sha256sums.txt
fi

echo "Done. Wrapped images copied to $outdir"
