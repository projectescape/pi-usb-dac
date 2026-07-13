# Pi USB DAC

Turn a Raspberry Pi 5 into a high-resolution USB DAC — laptop connects via USB-C, audio streams bit-perfect through a DAC HAT to speakers/amp.

## Hardware

- Raspberry Pi 5 (Pi 4 also works)
- DAC HAT:
  - **InnoMaker DAC PRO HAT** (ES9038Q2M) — 32-bit/384kHz + DSD
  - **InnoMaker HiFi DAC HAT** (PCM5122) — 24-bit/192kHz

## Quick Start

```bash
git clone https://github.com/aniket965/pi-usb-dac.git
cd pi-usb-dac
sudo bash setup.sh katana   # ES9038Q2M
# or: sudo bash setup.sh boss   # PCM5122
sudo reboot
```

After reboot, connect Pi to laptop via USB cable (USB-A to C recommended). Laptop sees "Pi DAC Pro" as a USB audio output.

## What It Does

```
Laptop ──USB──▶ Pi ──CamillaDSP──▶ DAC HAT ──▶ Speakers/Amp
                  │       ▲            ▲
              UAC2 gadget  │       allo-katana overlay
                      rate-adjusted   ES9038Q2M
                      bit-perfect     (32-bit/384kHz)
```

- **UAC2 USB gadget** (configfs) — Pi appears as high-res USB sound card
- **CamillaDSP** — rate-adjusted bit-perfect passthrough (no EQ, no resampling)
- **Audio optimizations** — WiFi power save disabled, CPU governor locked to performance
- **DSP filter** — Linear Phase Slow Roll-off (community-preferred)

## Architecture

| Component | File | Purpose |
|-----------|------|---------|
| UAC2 gadget | `uac2-gadget.sh` + `.service` | Creates USB audio device via configfs |
| Audio processor | `camilladsp-config.yml` + `.service` | Rate-adjusted bit-perfect routing |
| System optimizations | `audio-optimize.service` | WiFi PS off, performance governor |
| One-shot installer | `setup.sh` | Handles all config.txt, installs, services |

## Audio Path

```
Lossless file → USB → UAC2 capture → CamillaDSP passthrough → Katana DAC → Analog out
                      (32-bit S32_LE)   (1:1 mix, no EQ,      (ES9038Q2M)
                                         no gain, no resample)  (Linear Phase Slow)
```

Zero digital processing — only the DAC chip's inherent delta-sigma modulation and reconstruction filter.

## Verification

```bash
systemctl status uac2-gadget camilladsp audio-optimize
cat /proc/asound/cards          # Should show Katana + UAC2Gadget
arecord -l | grep UAC2Gadget    # CAPTURE device present
```

## DSP Filter Tuning

The ES9038Q2M has 7 reconstruction filters. List and change:

```bash
amixer -c 2 sget 'DSP Program'                    # current filter
amixer -c 2 set 'DSP Program' 1                   # Linear Phase Slow (recommended)
sudo alsactl store                                 # persist
```

See `es9038-dsp-filters.md` for the full filter reference with measurements.

## Troubleshooting

- **No DAC detected**: Verify physical connection. InnoMaker DAC PRO has no EEPROM — can't be auto-detected.
- **USB-C to C not working**: Known Pi 5 kernel issue. Use USB-A to C cable.
- **Interference/crackles**: WiFi power save or CPU scaling. The audio-optimize service handles both.
- **Low volume**: Master defaults to ~80%. Set to 100%: `amixer -c 2 set Master 255,255 && sudo alsactl store`
