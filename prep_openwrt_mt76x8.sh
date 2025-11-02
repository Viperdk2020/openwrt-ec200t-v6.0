#!/usr/bin/env bash
set -euo pipefail

printf '\n=== OpenWrt MT76x8 prep (fragment method): starting ===\n'

# Ensure we are in an OpenWrt source tree
if [ ! -f "include/toplevel.mk" ]; then
  echo "Error: run this script from the root of an OpenWrt source tree." >&2
  exit 1
fi

# Keep track of config changes
CONFIG_BAK=".config.pre-mt76x8"
if [ -f .config ]; then
  cp .config "$CONFIG_BAK"
fi

# 1. Feeds update/install
printf '\n[1/7] Updating and installing feeds...\n'
./scripts/feeds update -a
./scripts/feeds install -a

# 2. Target selection and package toggles (via fragment append)
printf '\n[2/7] Adjusting .config selections (fragment)...\n'
FRAG="$(mktemp)"
cat > "$FRAG" <<'EOF_FRAG'
# Target: ramips/mt76x8
CONFIG_TARGET_ramips=y
CONFIG_TARGET_ramips_mt76x8=y

# Core LuCI
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-theme-bootstrap=y

# Network mgmt
CONFIG_PACKAGE_luci-app-mwan3=y

# 4G/QMI stack
CONFIG_PACKAGE_luci-proto-qmi=y
CONFIG_PACKAGE_uqmi=y
CONFIG_PACKAGE_comgt=y
CONFIG_PACKAGE_kmod-usb-net-qmi-wwan=y
CONFIG_PACKAGE_kmod-usb-serial-option=y
CONFIG_PACKAGE_usb-modeswitch=y

# Repeater / AP+STA
CONFIG_PACKAGE_relayd=y
CONFIG_PACKAGE_luci-proto-relay=y
CONFIG_PACKAGE_wpad-mini=y

# VPN + DDNS + stability
CONFIG_PACKAGE_luci-app-wireguard=y
CONFIG_PACKAGE_luci-app-ddns=y
CONFIG_PACKAGE_watchdog=y
CONFIG_PACKAGE_zram-swap=y

# Exclusions: keep RAM/flash light
# (Unset by forcing =n; defconfig will propagate)
CONFIG_PACKAGE_luci-app-statistics=n
CONFIG_PACKAGE_luci-app-adblock=n
CONFIG_PACKAGE_adblock=n
EOF_FRAG

# Ensure a .config exists, then append fragment
touch .config
cat "$FRAG" >> .config
rm -f "$FRAG"

# Regenerate defaults
make defconfig >/dev/null

# 3. Build kernel package set only
printf '\n[3/7] Building kernel (kmods) only...\n'
make package/kernel/linux/compile V=s -j"$(nproc)"

# 4. Verify kmod output
printf '\n[4/7] Verifying required kmods...\n'

# Try to auto-detect the ABI subdir under bin/packages/*/kmods/
KVER="${KVER:-}"
ARCH_DIR=""
if [ -z "${KVER}" ]; then
  if compgen -G "bin/packages/*/kmods/*" > /dev/null; then
    CANDIDATES=(bin/packages/*/kmods/*)
    KVER="$(basename "${CANDIDATES[-1]}")"
    ARCH_DIR="$(basename "$(dirname "${CANDIDATES[-1]}")")"
  else
    KVER="6.12.51"
  fi
fi

if [ -z "${ARCH_DIR}" ]; then
  if compgen -G "bin/packages/*/kmods/${KVER}" > /dev/null; then
    ARCH_DIR="$(basename "$(dirname "$(ls -d bin/packages/*/kmods/${KVER} | head -n1)")")"
  else
    ARCH_DIR="mipsel_24kc"
  fi
fi

KMOD_DIR="bin/packages/${ARCH_DIR}/kmods/${KVER}"
if [ ! -d "$KMOD_DIR" ]; then
  echo "Error: expected kmod directory $KMOD_DIR not found" >&2
  echo "Hint: ensure your kernel ABI is correct or export KVER=<abi> before running." >&2
  exit 1
fi

shopt -s nullglob
REQUIRED_KMODS=(
  kmod-usb-net-qmi-wwan
  kmod-usb-serial-option
)
REQUIRED_PATTERNS=(
  "kmod-nft-*"
  "kmod-ipt-*"
)
missing=()
for pkg in "${REQUIRED_KMODS[@]}"; do
  if ! ls "$KMOD_DIR"/${pkg}_*.ipk >/dev/null 2>&1; then
    missing+=("$pkg")
  fi
done
for pat in "${REQUIRED_PATTERNS[@]}"; do
  files=("$KMOD_DIR"/${pat}.ipk)
  if [ ${#files[@]} -eq 0 ]; then
    missing+=("${pat}")
  fi
done
shopt -u nullglob

if [ ${#missing[@]} -ne 0 ]; then
  printf 'Error: missing expected kmods: %s\n' "${missing[*]}" >&2
  exit 1
fi

# 5. Stage deployable kmod repo
printf '\n[5/7] Staging kmods to deploy/kmods/%s ...\n' "$KVER"
DEPLOY_DIR="deploy/kmods/${KVER}"
mkdir -p "$DEPLOY_DIR"
rsync -a "$KMOD_DIR"/ "$DEPLOY_DIR"/

# 6. Provide publishing hints
printf '\n[6/7] Publish instructions:\n'
printf '  scp -r %q root@<ROUTER_IP>:/www/kmods/\n' "$DEPLOY_DIR"
printf '  /etc/apk/repositories -> add: http://<ROUTER_IP>/kmods/%s\n' "$KVER"

# 7. Router post-flash steps
printf '\n[7/7] Post-flash router commands to run:\n'
cat <<'POST'
apk update
apk add \
  luci luci-compat luci-theme-bootstrap \
  luci-app-mwan3 luci-proto-qmi uqmi comgt \
  kmod-usb-net-qmi-wwan kmod-usb-serial-option usb-modeswitch \
  luci-app-wireguard luci-app-ddns \
  relayd luci-proto-relay wpad-mini \
  watchdog zram-swap

/etc/init.d/uhttpd enable && /etc/init.d/uhttpd start
passwd
/etc/init.d/zram enable && /etc/init.d/zram start
apk cache clean
free -h
df -h | grep overlay
POST

# Show config delta for review
printf '\n--- Config delta (scripts/diffconfig.sh) ---\n'
./scripts/diffconfig.sh || true

# Summary checklist
cat <<SUMMARY

Checklist:
  [x] Feeds updated & installed
  [x] Target set to ramips/mt76x8 (fragment)
  [x] Requested LuCI/QMI/DDNS/relay/WG packages enabled
  [x] Heavy telemetry/adblock packages excluded
  [x] Kernel modules compiled
  [x] Kmods staged under deploy/kmods/${KVER}

Next steps on your router:
  1. scp -r deploy/kmods/${KVER} root@<ROUTER_IP>:/www/kmods/
  2. Add http://<ROUTER_IP>/kmods/${KVER} to /etc/apk/repositories
  3. Run the printed apk add/enable commands after flashing
SUMMARY

printf '\n=== OpenWrt MT76x8 prep: done ===\n'
