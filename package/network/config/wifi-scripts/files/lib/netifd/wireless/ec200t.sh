#!/bin/sh
# EC200T Wi-Fi driver wrapper built on top of mac80211

set -eu

SCRIPT_DIR="$(dirname "$0")"
BASE_DRIVER="${SCRIPT_DIR}/mac80211.sh"
DRIVER_NAME="ec200t"
BASE_NAME="mac80211"

[ ! -x "$BASE_DRIVER" ] && exit 1

replace_driver_name() {
    local data="$1"
    # Replace only the driver name field in the JSON payload
    echo "$data" | sed "s/\(\"name\"\s*:\s*\)\(\"${BASE_NAME}\"\)/\1\"${DRIVER_NAME}\"/"
}

case "${1-}" in
    dump)
        output="$(${BASE_DRIVER} dump)"
        rc=$?
        [ $rc -eq 0 ] || exit $rc
        replace_driver_name "$output"
        exit 0
        ;;
    setup|teardown)
        exec "${BASE_DRIVER}" "$@"
        ;;
    *)
        exec "${BASE_DRIVER}" "$@"
        ;;
esac
