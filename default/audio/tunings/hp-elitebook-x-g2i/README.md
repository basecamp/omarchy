# HP EliteBook X G2i speaker tuning (Omarchy)

Omarchy `omarchy-audio-tuning` profile for the HP EliteBook X G2i
(HP subsystem ID `8E86103C`, measured on SKU `D4DU1UT#ABA`), whose four
TAS2783 smart amps sound boxy on Linux because the DSP voicing that Windows
applies in the DTS:X Ultra APO is absent.

This tuning carries **HP's own factory EQ, bit-exact** — not a re-creation by
ear. Every biquad coefficient comes straight out of the per-board DTS tuning
data extracted from this machine's Windows partition:

    extracted-windows/audio-dts-tuning-8E86/HPCMIT8E86103C/

## What was decoded

`dts_apo4_oem_config_8E86103C.xml` (plain text) declares, for the internal
stereo speakers, that the default content mode is `APO4-Music`
(`APO4-ContentMode-Default`), and that this mode enables:

| DTS stage | Setting | Carried here as |
|---|---|---|
| `EFX:Eagle-HPF` | Enable=1, Freq=100, Order=2 | `bq_highpass` 100 Hz, Q 0.7071 (Butterworth 2nd order) |
| `EFX:Eagle-AEQ` / GPEQ | blobs `dts_gpeq_mode1_{48k,44k}` , In/Out gain 0 dB | 13 `bq_raw` sections, coefficients verbatim |
| `EFX:Eagle-MBHL` | multiband protection/loudness (envelope mode) | LSP lookahead limiter (Omarchy standard), not a multiband recreation |
| `SFX:Eagle-TBHDX` | bass enhancer, **Enable=0** in Music mode | omitted (disabled at the factory too) |

Mode-to-blob map from the XML (internal speakers): Music→mode1, Movie→mode2,
Voice→mode3 (HPF 160 Hz), Game1/2/3→mode4/5/6, Custom→mode7. Music being the
default for media/notifications, mode1 is what Windows plays music through.

## GPEQ blob format

Established by decoding both sample-rate variants of every mode to mutually
consistent curves. The decoder is a one-off analysis tool that reads a vendor
blob this repository does not carry, so it lives with the hardware enablement
work rather than here; the format below is the whole of its output that matters:

- int32 LE words; the 4720-byte file holds **two identical banks** (L/R),
  the second starting at the exact midpoint.
- Bank: `word0` = section count (24), `word1` = 0, then per section six words
  `[qflag, b0, b1, b2, a1, a2]`.
- `qflag` = 0 marks an unused section; otherwise coefficients are
  **Q(32-qflag) fixed point** (`value / 2^(32-qflag)`; qflag 2 → Q2.30 for
  the peaking sections, qflag 1 → Q1.31 for the HF tilt sections).
- Feedback convention `y[n] = Σ b_i·x[n-i] + a1·y[n-1] + a2·y[n-2]`, i.e.
  `H(z) = (b0 + b1·z⁻¹ + b2·z⁻²) / (1 − a1·z⁻¹ − a2·z⁻²)`; a1/a2 are negated
  in `filter-chain.conf` for PipeWire's RBJ convention.

The decode is self-validating: the 44.1 kHz and 48 kHz banks produce the same
analog-domain curve, and each section lands on a tuning-engineer-round value:

| # | Type | fc | Gain | Q |
|---|---|---|---|---|
| 0 | peaking | 118 Hz | +2.0 dB | 2.8 |
| 1 | peaking | 158 Hz | −3.0 dB | 3.3 |
| 2 | peaking | 254 Hz | −4.5 dB | 2.3 |
| 3 | peaking | 368 Hz | −3.5 dB | 2.0 |
| 4 | peaking | 624 Hz | −6.0 dB | 1.7 |
| 5 | peaking | 848 Hz | −5.0 dB | 1.8 |
| 6 | peaking | 1.37 kHz | −7.0 dB | 2.3 |
| 7 | peaking | 1.78 kHz | +3.0 dB | 3.6 |
| 8 | peaking | 2.90 kHz | −5.0 dB | 1.9 |
| 9 | peaking | 3.98 kHz | −3.5 dB | 5.1 |
| 10 | peaking | 5.53 kHz | −2.0 dB | 2.9 |
| 11 | peaking | 13.6 kHz | −5.0 dB | 3.3 |
| 12 | 1st-order HF tilt | — | +3.5 dB LF → −6 dB @ Nyquist | — |

The deep 600 Hz–1.4 kHz cuts are exactly the "boxy" band; HP's engineers cut
it 5–7 dB and added presence back at 1.8 kHz.

Rather than re-fitting these to `Freq/Q/Gain` sections, `filter-chain.conf`
uses PipeWire's `bq_raw` with the decoded coefficients for both 48000 and
44100 Hz, so the EQ stage is bit-identical to Windows' at either rate. (As
shipped by DTS, the 44.1 kHz bank sits ~2.1 dB hotter overall — a quirk of
their tilt section; the limiter absorbs it. The speaker sink runs at 48 kHz.)

## Headroom / limiter

The full cascade (high-pass included) peaks at **+3.66 dB at 1.86 kHz** on the
48 kHz bank. Limiter input gain is set to −4.66 dB (`g_in = 0.585`) so a
full-scale sine at the worst frequency lands exactly at the −1 dBFS threshold
(`th = 0.891`), with `alr`/`boost` disabled per Omarchy convention. The
−12 dB hardware safety trim on the `tas2783-N Speaker Volume` controls is
independent of this and stays in place.

## Not decoded / out of scope

- `dts_peq_ui_settings_8E86103C.bin` (gzip, 216 KB raw) and
  `dts_ctc_ui_settings_8E86103C.bin` decompress to protobuf-style binary UI
  state, not tuning curves.
- `dts_ctc_*.bin` — crosstalk cancellation matrices; not reproduced.
- `dts_hpeq_*.bin` — headphone EQ; this tuning only fronts the speaker sink.
- MBHL's program-dependent multiband loudness ("Boost 25", makeup gains) is a
  dynamics processor, deliberately not imitated by a static EQ.

## Activating

The profile ships with Omarchy, so there is nothing to copy into place. On a
machine whose DMI product name matches, `install/hardware/speaker-tuning.sh` pulls in
`lsp-plugins-lv2` for the limiter and the tuning is available as:

```
omarchy audio tuning status
omarchy audio tuning on
```
