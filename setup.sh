#!/bin/bash
# setup.sh — One-shot setup for Pi USB DAC gadget (ES9038Q2M)
# Run on a fresh Raspberry Pi OS install with the InnoMaker DAC PRO HAT attached.
#
# Usage: sudo bash setup.sh

set -euo pipefail

DAC_OVERLAY="allo-katana-dac-audio"
DAC_NAME="Katana"

log()  { echo "[setup] $*"; }
warn() { echo "[setup] WARN: $*"; }

log "Setting up Pi USB DAC — InnoMaker DAC PRO HAT (ES9038Q2M)"

# === 1. System config ===
log "Configuring /boot/firmware/config.txt..."

CONFIG=/boot/firmware/config.txt
# Disable built-in audio, enable I2S
sed -i 's/^dtparam=audio=on$/dtparam=audio=off/' "$CONFIG"
sed -i 's/^#dtparam=i2s=on$/dtparam=i2s=on/' "$CONFIG"
# If i2s wasn't there as commented, add it
grep -q '^dtparam=i2s=on' "$CONFIG" || echo "dtparam=i2s=on" >> "$CONFIG"
# Add DAC overlay
grep -q "dtoverlay=$DAC_OVERLAY" "$CONFIG" || echo "dtoverlay=$DAC_OVERLAY" >> "$CONFIG"
# Add dwc2 peripheral under [pi5]
if grep -q '^\[pi5\]' "$CONFIG"; then
    grep -q 'dtoverlay=dwc2,dr_mode=peripheral' "$CONFIG" || \
        sed -i '/^\[pi5\]/a dtoverlay=dwc2,dr_mode=peripheral' "$CONFIG"
else
    echo -e "\n[pi5]\ndtoverlay=dwc2,dr_mode=peripheral" >> "$CONFIG"
fi

log "Configuring /boot/firmware/cmdline.txt..."
CMDLINE=/boot/firmware/cmdline.txt
grep -q 'modules-load=dwc2' "$CMDLINE" || \
    sed -i 's/rootwait/rootwait modules-load=dwc2/' "$CMDLINE"

# === 2. Install CamillaDSP ===
log "Installing CamillaDSP..."
if ! command -v camilladsp &>/dev/null; then
    LATEST=$(curl -sI https://github.com/HEnquist/camilladsp/releases/latest | \
             grep -i location | sed 's/.*tag\///' | tr -d '\r')
    curl -sLo /tmp/camilladsp.tar.gz \
        "https://github.com/HEnquist/camilladsp/releases/download/${LATEST}/camilladsp-linux-aarch64.tar.gz"
    tar xzf /tmp/camilladsp.tar.gz -C /tmp
    cp /tmp/camilladsp /usr/local/bin/
    chmod +x /usr/local/bin/camilladsp
    rm /tmp/camilladsp /tmp/camilladsp.tar.gz
    log "CamillaDSP ${LATEST} installed"
else
    log "CamillaDSP already installed"
fi

# === 3. Deploy scripts and configs ===
SKILL_DIR="$(cd "$(dirname "$0")" && pwd)"

log "Deploying UAC2 gadget script..."
cp "$SKILL_DIR/uac2-gadget.sh" /usr/local/sbin/
chmod +x /usr/local/sbin/uac2-gadget.sh

log "Deploying CamillaDSP config and wrapper..."
mkdir -p /etc/camilladsp /var/lib/camilladsp
cp "$SKILL_DIR/camilladsp-config.yml" /etc/camilladsp/config.yml
cp "$SKILL_DIR/camilladsp-wrapper" /usr/local/bin/
chmod +x /usr/local/bin/camilladsp-wrapper

# === 4. Install systemd services ===
log "Installing systemd services..."
cp "$SKILL_DIR/uac2-gadget.service" /etc/systemd/system/
cp "$SKILL_DIR/camilladsp.service" /etc/systemd/system/
cp "$SKILL_DIR/audio-optimize.service" /etc/systemd/system/

systemctl daemon-reload
systemctl enable uac2-gadget camilladsp audio-optimize

# === 5. Apply ALSA settings ===
log "Applying DAC settings..."
# Wait a moment for sound cards to appear if services just started
sleep 2

# Find the DAC card
DAC_CARD=""
for card in /proc/asound/card*; do
    if grep -qi "Katana\|allo" "$card/id" 2>/dev/null; then
        DAC_CARD=$(basename "$card" | sed 's/card//')
        break
    fi
done

if [ -n "$DAC_CARD" ]; then
    # Master volume to 100% (0dB)
    amixer -c "$DAC_CARD" set Master 255,255 2>/dev/null || true
    # DSP filter: Linear Phase Slow Roll-off (#1) — audiophile-preferred
    amixer -c "$DAC_CARD" set 'DSP Program' 'Linear Phase Slow Roll-off Filter' 2>/dev/null || true
    alsactl store
    log "DAC card $DAC_CARD configured"
else
    warn "DAC card not found — ALSA settings skipped. Re-run after reboot."
fi

# === 6. Done ===
log ""
log "Setup complete. Reboot to apply all changes:"
log "  sudo reboot"
log ""
log "After reboot, connect USB cable to laptop. Laptop sees 'Pi DAC Pro'."
log "Verify with: systemctl status uac2-gadget camilladsp"
