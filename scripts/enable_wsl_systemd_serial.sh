#!/usr/bin/env bash
set -euo pipefail

echo "==> Enabling systemd in WSL and adding udev rule for serial ports"

if ! grep -qi microsoft /proc/version 2>/dev/null; then
  echo "This does not look like WSL. Exiting to avoid modifying a non-WSL system." >&2
  exit 1
fi

need_sudo() {
  if [ "${EUID:-$(id -u)}" -ne 0 ]; then
    echo "This script needs root. Re-running with sudo..."
    exec sudo -E "$0" "$@"
  fi
}

need_sudo "$@"

echo "-- Checking /etc/wsl.conf"
touch /etc/wsl.conf

if ! grep -q '^\[boot\]' /etc/wsl.conf; then
  echo "Adding [boot] section with systemd=true"
  cat >> /etc/wsl.conf <<'EOF'

# Added by enable_wsl_systemd_serial.sh
[boot]
systemd=true
EOF
else
  if awk '/^\[boot\]/{f=1;next} /^\[/{f=0} f && /^systemd=true$/{found=1} END{exit !found}' /etc/wsl.conf; then
    echo "systemd=true already present under [boot]"
  else
    echo "Ensuring systemd=true under [boot]"
    # Insert after [boot] line if not present in that section
    sed -i '/^\[boot\]/{:a;n;/^\[/q;ba};/^\[boot\]/{n;h;:b;/^\[/!{x;/systemd=true/!{x;ba};x}}' /etc/wsl.conf || true
    # If the above sed is too strict, append as a fallback
    awk 'BEGIN{boot=0;done=0} /^\[boot\]/{boot=1;print;next} /^\[/{if(boot && !done){print "systemd=true";done=1} boot=0} {print} END{if(boot && !done) print "systemd=true"}' /etc/wsl.conf > /etc/wsl.conf.tmp && mv /etc/wsl.conf.tmp /etc/wsl.conf
  fi
fi

echo "-- Installing udev rule to grant dialout access to ttyUSB* and ttyACM*"
install -d /etc/udev/rules.d
cat > /etc/udev/rules.d/50-serial-dialout.rules <<'EOF'
# Allow dialout group access to common USB serial devices
KERNEL=="ttyUSB[0-9]*", GROUP="dialout", MODE="0660"
KERNEL=="ttyACM[0-9]*", GROUP="dialout", MODE="0660"
EOF

chmod 0644 /etc/udev/rules.d/50-serial-dialout.rules

echo "-- Detecting init system (PID 1)"
pid1=$(ps -p 1 -o comm= 2>/dev/null || echo unknown)
echo "PID 1: $pid1"

if command -v udevadm >/dev/null 2>&1 && systemctl >/dev/null 2>&1; then
  # If systemd is live already (WSL with systemd enabled), reload rules
  if systemctl is-system-running >/dev/null 2>&1; then
    echo "systemd appears active; reloading udev rules"
    udevadm control --reload || true
    udevadm trigger || true
  else
    echo "systemd tooling present but not active. A WSL restart is still required." 
  fi
else
  echo "systemd/udev not active (expected on default WSL)."
fi

echo
echo "Next steps:"
echo "  1) From Windows PowerShell:   wsl --shutdown"
echo "  2) Reopen this distro; verify with:  ps -p 1 -o comm=  (should say systemd)"
echo "  3) Unplug/replug your USB device or run: sudo udevadm trigger (if available)"
echo
echo "Quick fallback (without systemd): run this when needed to fix permissions:"
echo "  sudo chgrp dialout /dev/ttyUSB0 && sudo chmod 660 /dev/ttyUSB0"
echo
echo "Done."

