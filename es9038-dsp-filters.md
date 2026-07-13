# ES9038Q2M DSP Filter Reference

The ESS ES9038Q2M DAC chip has 7 selectable reconstruction filters.
Set via: `amixer -c <card> set 'DSP Program' <name>`

## Filter Summary

| # | Name | Frequency Response | Impulse Response | Best For |
|---|------|-------------------|------------------|----------|
| 0 | Linear Phase Fast Roll-off | Flattest passband, sharp cutoff | Symmetric, moderate pre/post-ringing | Measurement accuracy |
| 1 | **Linear Phase Slow Roll-off** ★ | Gradual cutoff, less ringing | Symmetric, minimal ringing | **General listening (recommended)** |
| 2 | Minimum Phase Fast Roll-off | Sharp cutoff | No pre-ringing, post-ringing only | Percussion, transients |
| 3 | Minimum Phase Slow Roll-off | Gradual cutoff | No pre-ringing, natural decay | Natural timbre, vocals |
| 4 | Apodizing Fast Roll-off | Fast cutoff, apodized | Reduced pre-ringing vs fast | Compromise (factory default) |
| 5 | Corrected Minimum Phase Fast | Phase-corrected fast | Corrected phase response | Phase-critical material |
| 6 | Brick Wall | Sharpest cutoff, most ringing | Heavy ringing | Avoid for music |

★ Community consensus from diyAudio and Archimago's measurements: #1 (Linear Phase Slow)
sounds best to most listeners — smooth, low ringing, no audible aliasing in practice.

## Applying

```bash
amixer -c 2 set 'DSP Program' 1
sudo alsactl store
```

## Source

- diyAudio: "ESS Sabre ES9038 family - filter settings" (2019)
- Archimago's Musings: ES9038Q2M filter measurements (2022)
- ESS ES9038Q2M Datasheet v1.4, pp. 55-58
