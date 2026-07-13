#!/bin/bash
# uac2-gadget.sh — Create UAC2 USB audio gadget via configfs
# Laptop sees Pi as a high-res USB audio device (up to 384kHz/32-bit)

set -euo pipefail

CONFIGFS=/sys/kernel/config/usb_gadget
GADGET_NAME=pi-dac
FUNC=uac2.0
UDC=""

log() { echo "[uac2-gadget] $*"; }

# === Get clean serial number (strip null bytes) ===
get_serial() {
    local sn
    sn=$(tr -d '\0' < /proc/device-tree/serial-number 2>/dev/null) || sn="000001"
    echo "$sn"
}

# === Find UDC ===
find_udc() {
    for udc in /sys/class/udc/*; do
        [ -d "$udc" ] && UDC=$(basename "$udc") && return 0
    done
    return 1
}

# === Clean stale gadget if present (must be done in reverse dependency order) ===
cleanup_gadget() {
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
    log "Cleaned up stale gadget"
}

# === Main ===
cleanup_gadget

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

# UAC2 function: receive audio FROM host (ALSA capture on Pi)
# c_* = capture = host → Pi (laptop sends, Pi receives via USB)
# p_* = playback = Pi → host (disabled — we don't send audio back)
mkdir -p "functions/$FUNC"
echo 0               > "functions/$FUNC/p_chmask"
echo 4               > "functions/$FUNC/p_ssize"
echo "44100"         > "functions/$FUNC/p_srate"
echo 3               > "functions/$FUNC/c_chmask"
echo 4               > "functions/$FUNC/c_ssize"
echo "44100,48000,88200,96000,176400,192000,352800,384000" > "functions/$FUNC/c_srate"

# Config
mkdir -p configs/c.1
echo 120 > configs/c.1/MaxPower
mkdir -p configs/c.1/strings/0x409
echo "UAC2 Audio" > configs/c.1/strings/0x409/configuration
ln -sf "functions/$FUNC" "configs/c.1/"

# Bind
echo "$UDC" > UDC
log "Gadget '$GADGET_NAME' bound to $UDC — 32-bit stereo, up to 384kHz"
