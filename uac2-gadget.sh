#!/bin/bash
# uac2-gadget.sh — Create USB audio gadget via configfs or g_audio
# Supports three modes for cross-platform compatibility:
#
#   uac2   Linux host only (p_chmask=0) — 384kHz/32-bit max
#   dual   Linux + macOS + iOS + Windows (p_chmask=3, c_sync=adaptive) — 384kHz/32-bit
#   uac1   Android + universal fallback (g_audio module) — 48kHz/16-bit
#
# Usage: uac2-gadget.sh [--mode uac2|dual|uac1]
# Default: dual (most compatible)

set -euo pipefail

# ============================================================================
# Configuration
# ============================================================================
CONFIGFS=/sys/kernel/config/usb_gadget
GADGET_NAME=pi-dac
FUNC=uac2.0
UDC=""
MODE="dual"  # default: cross-platform

# ============================================================================
# Parse args
# ============================================================================
while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode) MODE="$2"; shift 2 ;;
        -m)     MODE="$2"; shift 2 ;;
        *)      echo "Usage: $0 [--mode uac2|dual|uac1]"; exit 1 ;;
    esac
done

case "$MODE" in
    uac2|dual|uac1) ;;
    auto) MODE="dual" ;;  # auto → safest cross-platform default
    *) echo "ERROR: Unknown mode '$MODE'. Valid: uac2, dual, uac1"; exit 1 ;;
esac

log() { echo "[uac2-gadget:$MODE] $*"; }

# ============================================================================
# Helpers
# ============================================================================
get_serial() {
    local sn
    sn=$(tr -d '\0' < /proc/device-tree/serial-number 2>/dev/null) || sn="000001"
    echo "$sn"
}

find_udc() {
    for udc in /sys/class/udc/*; do
        [ -d "$udc" ] && UDC=$(basename "$udc") && return 0
    done
    return 1
}

# ============================================================================
# Cleanup — configfs gadget
# ============================================================================
cleanup_configfs_gadget() {
    local g="$CONFIGFS/$GADGET_NAME"
    [ -d "$g" ] || return 0
    cd "$g"
    echo "" > UDC 2>/dev/null || true
    rm -f configs/c.1/"$FUNC" 2>/dev/null || true
    rmdir configs/c.1/strings/0x409 2>/dev/null || true
    rmdir configs/c.1 2>/dev/null || true
    rmdir "functions/$FUNC" 2>/dev/null || true
    rmdir strings/0x409 2>/dev/null || true
    rmdir os_desc 2>/dev/null || true
    rmdir webusb 2>/dev/null || true
    cd "$CONFIGFS"
    rmdir "$GADGET_NAME" 2>/dev/null || true
    log "Cleaned up configfs gadget"
}

# ============================================================================
# Cleanup — g_audio module
# ============================================================================
cleanup_g_audio() {
    if lsmod | grep -q "^g_audio "; then
        modprobe -r g_audio 2>/dev/null || true
        log "Unloaded g_audio module"
    fi
    modprobe -r usb_f_uac2 2>/dev/null || true
    modprobe -r u_audio 2>/dev/null || true
}

# ============================================================================
# Mode: uac2 (Linux-only, capture only, high-res)
# ============================================================================
setup_uac2() {
    if ! find_udc; then
        log "ERROR: No UDC found. Is dwc2 loaded? Check config.txt."
        exit 1
    fi
    log "UDC: $UDC"

    modprobe libcomposite 2>/dev/null || true
    modprobe usb_f_uac2 2>/dev/null || true

    mkdir -p "$CONFIGFS/$GADGET_NAME"
    cd "$CONFIGFS/$GADGET_NAME"

    echo 0x1d6b > idVendor
    echo 0x0104 > idProduct
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB
    echo 0xEF   > bDeviceClass
    echo 0x02   > bDeviceSubClass
    echo 0x01   > bDeviceProtocol

    mkdir -p strings/0x409
    echo "InnoMaker"    > strings/0x409/manufacturer
    echo "Pi DAC Pro"    > strings/0x409/product
    echo "$(get_serial)" > strings/0x409/serialnumber

    mkdir -p "functions/$FUNC"
    # Playback: disabled (no endpoint back to host)
    echo 0       > "functions/$FUNC/p_chmask"
    echo 4       > "functions/$FUNC/p_ssize"
    echo "44100" > "functions/$FUNC/p_srate"
    # Capture: host → Pi, async feedback
    echo 3       > "functions/$FUNC/c_chmask"
    echo 4       > "functions/$FUNC/c_ssize"
    echo "44100,48000,88200,96000,176400,192000,352800,384000" > "functions/$FUNC/c_srate"
    echo "async"  > "functions/$FUNC/c_sync" 2>/dev/null || true

    mkdir -p configs/c.1
    echo 120 > configs/c.1/MaxPower
    mkdir -p configs/c.1/strings/0x409
    echo "UAC2 Audio" > configs/c.1/strings/0x409/configuration
    ln -sf "functions/$FUNC" "configs/c.1/"

    echo "$UDC" > UDC
    log "UAC2 gadget bound — Linux-only, capture only, up to 384kHz"
}

# ============================================================================
# Mode: dual (Linux + macOS + iOS + Windows, both directions)
# ============================================================================
setup_dual() {
    if ! find_udc; then
        log "ERROR: No UDC found. Is dwc2 loaded? Check config.txt."
        exit 1
    fi
    log "UDC: $UDC"

    modprobe libcomposite 2>/dev/null || true
    modprobe usb_f_uac2 2>/dev/null || true

    mkdir -p "$CONFIGFS/$GADGET_NAME"
    cd "$CONFIGFS/$GADGET_NAME"

    echo 0x1d6b > idVendor
    echo 0x0104 > idProduct
    echo 0x0100 > bcdDevice
    echo 0x0200 > bcdUSB
    echo 0xEF   > bDeviceClass
    echo 0x02   > bDeviceSubClass
    echo 0x01   > bDeviceProtocol

    mkdir -p strings/0x409
    echo "InnoMaker"    > strings/0x409/manufacturer
    echo "Pi DAC Pro"    > strings/0x409/product
    echo "$(get_serial)" > strings/0x409/serialnumber

    mkdir -p "functions/$FUNC"
    # Playback: ENABLED — dummy endpoint satisfies macOS/iOS/Windows descriptor validation
    echo 3       > "functions/$FUNC/p_chmask"
    echo 4       > "functions/$FUNC/p_ssize"
    echo "44100,48000,96000" > "functions/$FUNC/p_srate"
    # Capture: host → Pi, adaptive sync (more reliable on Windows)
    echo 3       > "functions/$FUNC/c_chmask"
    echo 4       > "functions/$FUNC/c_ssize"
    echo "44100,48000,88200,96000,176400,192000,352800,384000" > "functions/$FUNC/c_srate"
    echo "adaptive" > "functions/$FUNC/c_sync" 2>/dev/null || true

    mkdir -p configs/c.1
    echo 120 > configs/c.1/MaxPower
    mkdir -p configs/c.1/strings/0x409
    echo "UAC2 Audio" > configs/c.1/strings/0x409/configuration
    ln -sf "functions/$FUNC" "configs/c.1/"

    echo "$UDC" > UDC
    log "UAC2 dual gadget bound — cross-platform, up to 384kHz"
}

# ============================================================================
# Mode: uac1 (Android + universal fallback, g_audio module)
# ============================================================================
setup_uac1() {
    # g_audio parameters (UAC1):
    #   c_chmask=3  stereo capture (host → Pi)
    #   c_srate=48000
    #   c_ssize=2   16-bit S16_LE
    #   p_chmask=0  no playback to host
    modprobe g_audio \
        c_chmask=3 c_srate=48000 c_ssize=2 \
        p_chmask=0 \
        2>/dev/null || {
        log "ERROR: Failed to load g_audio module."
        log "  Is CONFIG_USB_GADGET or CONFIG_USB_AUDIO enabled?"
        log "  Check: modprobe -c | grep g_audio"
        exit 1
    }
    log "UAC1 g_audio gadget loaded — Android-compatible, 48kHz/16-bit"
}

# ============================================================================
# Main
# ============================================================================
log "Starting in '$MODE' mode"

# Always clean both — we might be switching modes
cleanup_configfs_gadget
cleanup_g_audio

case "$MODE" in
    uac2) setup_uac2 ;;
    dual) setup_dual ;;
    uac1) setup_uac1 ;;
esac

log "Done."
