#!/usr/bin/env bash
set -euo pipefail

# Resolve repo root and wrapper path.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP_SCRIPT="${REPO_ROOT}/wrap_mt76x8_images.sh"

if [[ ! -x "${WRAP_SCRIPT}" ]]; then
    echo "error: ${WRAP_SCRIPT} not found or not executable." >&2
    exit 1
fi

WIN_PATH='C:\tftp'
if command -v wslpath >/dev/null 2>&1; then
    DEST_DIR="$(wslpath -u "${WIN_PATH}" 2>/dev/null || true)"
fi

DEST_DIR="${DEST_DIR:-/mnt/c/tftp}"

exec "${WRAP_SCRIPT}" --dest "${DEST_DIR}" "$@"
