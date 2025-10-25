#!/usr/bin/env bash
set -euo pipefail

# Locate repo root even when invoked via relative path.
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAP_SCRIPT="${REPO_ROOT}/scripts/jbonecloud_wrap.py"
DEFAULT_TARGET_DIR="${REPO_ROOT}/bin/targets/ramips/mt76x8"

usage() {
    cat <<'EOF'
Usage: wrap_mt76x8_images.sh [OPTIONS] [IMAGE_DIR]

Wrap all non-JBC MT7628 images in IMAGE_DIR (defaults to bin/targets/ramips/mt76x8)
with the legacy uImage header required by the EC200T bootloader.

Options:
  -d, --dest DIR   Output directory for wrapped images (defaults to IMAGE_DIR).
  -h, --help       Show this help text.
EOF
}

# Parse options.
DEST_DIR=""
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            usage
            exit 0
            ;;
        -d|--dest)
            if [[ $# -lt 2 ]]; then
                echo "error: --dest requires a directory argument." >&2
                exit 1
            fi
            DEST_DIR="$2"
            shift 2
            ;;
        --dest=*)
            DEST_DIR="${1#*=}"
            shift 1
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "error: unknown option '$1'." >&2
            usage
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done
set -- "${POSITIONAL[@]}"

if [[ ! -f "${WRAP_SCRIPT}" ]]; then
    echo "error: ${WRAP_SCRIPT} not found; run from the OpenWrt source tree." >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "error: python3 not found in PATH." >&2
    exit 1
fi

IMAGE_DIR="${1:-${DEFAULT_TARGET_DIR}}"
IMAGE_DIR="$(realpath -m "${IMAGE_DIR}")"

if [[ ! -d "${IMAGE_DIR}" ]]; then
    echo "error: image directory '${IMAGE_DIR}' does not exist." >&2
    exit 1
fi

if [[ -n "${DEST_DIR}" ]]; then
    DEST_DIR="$(realpath -m "${DEST_DIR}")"
    mkdir -p "${DEST_DIR}"
else
    DEST_DIR="${IMAGE_DIR}"
fi

if [[ ! -w "${DEST_DIR}" ]]; then
    echo "error: destination directory '${DEST_DIR}' is not writable." >&2
    exit 1
fi

mapfile -t images < <(find "${IMAGE_DIR}" -maxdepth 1 -type f -name '*.bin' ! -name '*-jbc.bin' -print | sort)

if [[ "${#images[@]}" -eq 0 ]]; then
    echo "No wrapable *.bin images found under ${IMAGE_DIR}." >&2
    exit 1
fi

echo "Wrapping ${#images[@]} image(s) from ${IMAGE_DIR} into ${DEST_DIR}..."
for image in "${images[@]}"; do
    basename="$(basename "${image}")"
    output="${DEST_DIR}/${basename}-jbc.bin"
    python3 "${WRAP_SCRIPT}" "${image}" -o "${output}"
done
