#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[%(%Y-%m-%dT%H:%M:%S%z)T] %s\n' -1 "$*"
}

die() {
    log "ERROR: $*"
    exit 1
}

TARGET=${TARGET:-ramips}
SUBTARGET=${SUBTARGET:-mt76x8}
PROFILE=${PROFILE:-zbt-we5931}
PROFILE_FALLBACK=${PROFILE_FALLBACK:-mediatek_mt7628an-eval}
OPENWRT_VERSION=${OPENWRT_VERSION:-24.10.0-rc1}
OPENWRT_IMAGEBUILDER_URL=${OPENWRT_IMAGEBUILDER_URL:-}
TZ=${TZ:-Europe/Copenhagen}
STA_SSID=${STA_SSID:-UPSTREAM_SSID}
STA_KEY=${STA_KEY:-UPSTREAM_PASSWORD}
APN=${APN:-YOUR_APN}
PACKAGES="ppp chat kmod-usb-core kmod-usb2 kmod-usb-serial kmod-usb-serial-option kmod-usb-acm usb-modeswitch kmod-usb-net kmod-usb-net-cdc-ether kmod-usb-net-rndis kmod-mt76 wpad-basic-mbedtls firewall4 nftables kmod-nft-nat dnsmasq-full dropbear logd ip-full swconfig luci luci-ssl uhttpd ca-bundle luci-mod-network luci-app-firewall luci-proto-ppp"

REPO_ROOT=$(pwd)
WORK_ROOT="$REPO_ROOT/tmp/ec200t-imagebuilder"
IMAGEBUILDER_DIR="$WORK_ROOT/imagebuilder"
OVERLAY_SRC="$REPO_ROOT/files"
OVERLAY_DIR="$WORK_ROOT/overlay"
WRAPPER_SCRIPT="$REPO_ROOT/scripts/jbonecloud_wrap.py"

mkdir -p "$WORK_ROOT"
rm -rf "$IMAGEBUILDER_DIR" "$OVERLAY_DIR"

if [[ -z "$OPENWRT_IMAGEBUILDER_URL" ]]; then
    archive="openwrt-imagebuilder-${TARGET}-${SUBTARGET}.Linux-x86_64.tar.xz"
    case "${OPENWRT_VERSION,,}" in
        snapshot|snapshots)
            base_url="https://downloads.openwrt.org/snapshots/targets/${TARGET}/${SUBTARGET}"
            version_label="SNAPSHOT"
            ;;
        *)
            base_url="https://downloads.openwrt.org/releases/${OPENWRT_VERSION}/targets/${TARGET}/${SUBTARGET}"
            version_label="$OPENWRT_VERSION"
            ;;
    esac
    OPENWRT_IMAGEBUILDER_URL="${base_url}/${archive}"
else
    archive=$(basename "$OPENWRT_IMAGEBUILDER_URL")
    version_label=${OPENWRT_VERSION:-custom}
fi

DOWNLOAD_PATH="$WORK_ROOT/${archive}"
if [[ ! -f "$DOWNLOAD_PATH" ]]; then
    log "Downloading ImageBuilder from $OPENWRT_IMAGEBUILDER_URL"
    curl -fL "$OPENWRT_IMAGEBUILDER_URL" -o "$DOWNLOAD_PATH" || die "failed to download ImageBuilder"
else
    log "Reusing existing ImageBuilder archive $DOWNLOAD_PATH"
fi

log "Extracting ImageBuilder"
tar -C "$WORK_ROOT" -xf "$DOWNLOAD_PATH"
EXTRACTED_DIR=$(tar -tf "$DOWNLOAD_PATH" | head -n1 | cut -d/ -f1)
mv "$WORK_ROOT/$EXTRACTED_DIR" "$IMAGEBUILDER_DIR"

if [[ ! -d "$OVERLAY_SRC" ]]; then
    die "overlay directory $OVERLAY_SRC not found"
fi

log "Preparing overlay with templated defaults"
rsync -a "$OVERLAY_SRC/" "$OVERLAY_DIR/"
python3 - "$OVERLAY_DIR" <<'PY2'
import os
import sys
from pathlib import Path

overlay = Path(sys.argv[1])
subs = {
    "UPSTREAM_SSID": os.environ.get("STA_SSID", "UPSTREAM_SSID"),
    "UPSTREAM_PASSWORD": os.environ.get("STA_KEY", "UPSTREAM_PASSWORD"),
    "YOUR_APN": os.environ.get("APN", "YOUR_APN"),
}
for path in overlay.rglob('*'):
    if not path.is_file():
        continue
    text = path.read_text()
    for needle, value in subs.items():
        text = text.replace(needle, value)
    path.write_text(text)
PY2

export TZ

pushd "$IMAGEBUILDER_DIR" >/dev/null
log "Running ImageBuilder for profile $PROFILE"
if make image PROFILE="$PROFILE" PACKAGES="$PACKAGES" FILES="$OVERLAY_DIR" >/tmp/imagebuilder.log 2>&1; then
    profile_used="$PROFILE"
else
    if [[ "$PROFILE_FALLBACK" != "$PROFILE" ]]; then
        log "Primary profile $PROFILE failed, retrying with $PROFILE_FALLBACK"
        if make image PROFILE="$PROFILE_FALLBACK" PACKAGES="$PACKAGES" FILES="$OVERLAY_DIR" >>/tmp/imagebuilder.log 2>&1; then
            profile_used="$PROFILE_FALLBACK"
        else
            tail -n 50 /tmp/imagebuilder.log
            popd >/dev/null
            die "ImageBuilder failed for both profiles"
        fi
    else
        tail -n 50 /tmp/imagebuilder.log
        popd >/dev/null
        die "ImageBuilder failed for profile $PROFILE"
    fi
fi
popd >/dev/null

OUTDIR="$IMAGEBUILDER_DIR/bin/targets/${TARGET}/${SUBTARGET}"
[[ -d "$OUTDIR" ]] || die "expected output directory $OUTDIR missing"

log "Wrapping images with legacy uImage header"
shopt -s nullglob
for img in "$OUTDIR"/*sysupgrade*.bin "$OUTDIR"/*initramfs*.bin; do
    [[ -e "$img" ]] || continue
    python3 "$WRAPPER_SCRIPT" "$img" -o "${img%.bin}-jbc.bin"
done
shopt -u nullglob

if compgen -G "$OUTDIR/*jbc.bin" >/dev/null; then
    (cd "$OUTDIR" && sha256sum *jbc.bin > sha256sums.txt)
fi

log "Generating README"
cat <<EOF > "$OUTDIR/README.md"
# MT7628NN sysupgrade (wrapped)
**Target:** ${TARGET}/${SUBTARGET}
**OpenWrt release:** ${version_label}
**Profile used:** ${profile_used}
**Timezone:** ${TZ}

## Defaults
- Wi-Fi STA: SSID=\`${STA_SSID}\`, WPA2-PSK=\`${STA_KEY}\`
- WAN priority: wwan (DHCP, metric 10) → cell (PPP /dev/ttyUSB3, APN=${APN}, metric 20) → wan_usb (DHCP usb0, metric 30)
- Country: DK (HT20, legacy rates disabled)
- Firewall: lan → wan masquerade

## Flashing (safe path)
1. Enter U-Boot recovery and configure TFTP if required.
2. RAM-boot the initramfs (if available):
   tftpboot 0x82000000 <initramfs-jbc.bin>; bootm 0x82000000
3. From the RAM session: sysupgrade -n /tmp/<sysupgrade-jbc.bin>

## Recovery
- Serial console 57600 8N1.
- From U-Boot: tftpboot the desired image then bootm.

## Integrity
Checksums for wrapped images are listed in `sha256sums.txt`.
EOF

log "Build outputs"
ls -lh "$OUTDIR"

if [[ -f "$OUTDIR/sha256sums.txt" ]]; then
    log "SHA256 checksums"
    cat "$OUTDIR/sha256sums.txt"
fi

log "Done. Artifacts in $OUTDIR"
