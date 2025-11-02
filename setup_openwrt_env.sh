#!/usr/bin/env bash
set -euo pipefail

# Configurable vars
OPENWRT_GIT="${OPENWRT_GIT:-https://git.openwrt.org/openwrt/openwrt.git}"
OPENWRT_BRANCH="${OPENWRT_BRANCH:-openwrt-24.10}"
SRC_DIR="${SRC_DIR:-$PWD/openwrt-src}"

# Mirrors to try in order
MIRRORS=(
  "http://mirrors.edge.kernel.org/ubuntu"
  "http://azure.archive.ubuntu.com/ubuntu"
)

APT_FIX_CONF=/etc/apt/apt.conf.d/99hash-fix

require_sudo() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    sudo -v
  fi
}

apt_fix_hash_mismatch() {
  require_sudo
  echo "[*] Applying apt hash-mismatch mitigations"
  sudo rm -rf /var/lib/apt/lists/* || true
  sudo mkdir -p /var/lib/apt/lists/partial
  sudo apt-get clean || true
  sudo tee "$APT_FIX_CONF" >/dev/null <<'EOF'
Acquire::http::Pipeline-Depth "0";
Acquire::http::No-Cache "true";
Acquire::Retries "5";
Acquire::CompressionTypes::Order "gz";
Acquire::GzipIndexes "false";
Acquire::PDiffs "false";
EOF
}

apt_set_mirror() {
  local mirror="$1"
  require_sudo
  echo "[*] Switching apt mirror to: $mirror"
  sudo sed -i "s|http://archive.ubuntu.com/ubuntu|$mirror|g" /etc/apt/sources.list || true
  sudo sed -i "s|http://security.ubuntu.com/ubuntu|$mirror|g" /etc/apt/sources.list || true
}

apt_update_with_retries() {
  require_sudo
  echo "[*] Running apt-get update (IPv4, retries/timeouts)"
  sudo apt-get -o Acquire::ForceIPv4=true \
               -o Acquire::Retries=10 \
               -o Acquire::http::Timeout=45 \
               -o Acquire::PDiffs=false \
               -o Acquire::GzipIndexes=false \
               update
}

install_deps() {
  require_sudo
  echo "[*] Installing build dependencies"
  sudo apt-get install -y --fix-missing \
    build-essential gcc g++ make pkg-config \
    gawk wget curl git rsync unzip bzip2 xz-utils file patch \
    python3 ca-certificates time ccache \
    gettext libncurses5-dev libz-dev zlib1g-dev libssl-dev \
    flex bison tar
}

prepare_openwrt_tree() {
  echo "[*] Preparing OpenWrt source tree at: $SRC_DIR"
  if [[ ! -d "$SRC_DIR/.git" ]]; then
    git clone --branch "$OPENWRT_BRANCH" "$OPENWRT_GIT" "$SRC_DIR"
  fi
  cd "$SRC_DIR"
  ./scripts/feeds update -a
  ./scripts/feeds install -a
}

print_tools() {
  echo
  echo "--- Tool versions ---"
  (gcc --version | head -n1) || true
  (g++ --version | head -n1) || true
  (make --version | head -n1) || true
}

main() {
  apt_fix_hash_mismatch

  local updated=0
  for m in "${MIRRORS[@]}"; do
    apt_set_mirror "$m"
    if apt_update_with_retries; then
      updated=1
      break
    else
      echo "[!] Update failed on mirror: $m — trying next"
    fi
  done

  if [[ "$updated" -ne 1 ]]; then
    echo "[FATAL] All mirror attempts failed. Check network/proxy and rerun."
    exit 1
  fi

  if ! install_deps; then
    echo "[!] Initial install failed — retrying after one more update"
    apt_update_with_retries
    install_deps
  fi

  prepare_openwrt_tree
  print_tools

  echo
  echo "Environment ready. Next steps (manual):"
  echo "  cd \"$SRC_DIR\""
  echo "  make defconfig"
  echo "  make -j\"$(nproc)\" V=s"
  echo
  echo "No build has been executed per your request."
}

main "$@"
