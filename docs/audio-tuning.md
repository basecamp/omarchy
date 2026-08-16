# Speaker tunings

Laptop speakers ship voiced by the vendor's Windows DSP layer, which Linux does
not get. A tuning restores that as a PipeWire filter-chain in front of the
internal speaker sink: a declarative graph hosted by a small PipeWire client, with
no GUI app and no binary blob.

```
default/audio/tunings/<vendor>-<model>/
├── tuning.conf        # description, match, provenance, measurements
└── filter-chain.conf  # the graph, with @SPEAKER_SINK@ substituted on install
```

`on` renders the graph into `~/.config/pipewire/omarchy-speaker-tuning.conf.d/`
(plus the shared host config `omarchy-speaker-tuning.conf`, from
`default/audio/filter-chain-host.conf`) and runs it as its own PipeWire client via
`omarchy-speaker-tuning.service`, rather than
loading it into the audio daemon. The daemon only reads its own config at startup,
so a daemon-loaded tuning could only be switched by restarting PipeWire — which
drops every PulseAudio client's connection, and applications that do not reconnect
(Spotify) then have to be restarted by hand. Hosting it separately makes switching
a start/stop of one small process, and contains failure: a malformed tuning breaks
only that service instead of stopping PipeWire from starting at all.

Tunings apply automatically: `install/hardware/speaker-tuning.sh` installs the
LV2 dependency and `install/user/first-run/audio-tuning.sh` applies the tuning,
both gated on the match. Machines without a matching tuning are untouched.

Switching it on happens at first-run, not at finalize-user time, because finalize-user
also runs in the ISO chroot where there is no audio server: the sink a tuning has
to target does not exist there, so nothing could be written — and nothing would
retry, since the finalizer marks all shipped migrations complete on a fresh
install. Matching itself deliberately does not consult the audio graph, so the
LV2 dependency is still installed in the chroot.

```bash
omarchy audio tuning on        # install the matching tuning
omarchy audio tuning off       # remove it, back to raw speakers
omarchy audio tuning status    # installed? in use? what matches?
```

`match` and `fronted-sink` are also accepted; they exist for the install hooks
and the sink-listing scripts rather than for daily use.

`on` verifies its own work: it waits for the tuning sink to appear and confirms
its output linked to the expected physical sink, and uninstalls everything again
on either failure — so a broken tuning cannot be left half-applied. It also
switches the default sink to the tuning and moves existing app streams onto it
(`off` reverses both). When everything is already installed and linked, `on` is
a no-op; pass `--force` when iterating on a tuning in place.

## Adding a tuning

Add a directory with a `tuning.conf` and a `filter-chain.conf`. No new command is
needed: matching is data. A tuning declares how to recognise its hardware, plus the
`sink_pattern` its graph targets:

| Key | Matches on | Notes |
|---|---|---|
| `match_sku` | DMI product SKU, whole value | Most precise. Vendors key speaker firmware on it, so it identifies the hardware rather than a marketing name |
| `match_dmi` | DMI product name or family, substring | Convenient, but a short string widens fast — `product_family` here is `Dell Laptops` |
| `match_command` | Any predicate you name | For hardware needing a sharper test than either |

`match_sku` and `match_dmi` are lists, so one tuning can cover several models it has
been validated on:

```bash
match_sku=("0DB9" "0DBA")   # XPS 14 and XPS 16
```

Only the first *defined* key is consulted, in the order `match_command`,
`match_sku`, `match_dmi` — keys below a defined one are ignored, and a tuning
defining none never matches.

`sink_pattern` is required whichever method you use, since the graph's target sink
is substituted from it. The graph must also keep two fixed properties: the sink
node is named `omarchy_speaker_tuning` (the install checks for that exact name,
so renaming it silently fails verification), and its output stream sets
`node.dont-fallback` alongside `node.dont-move`, so WirePlumber cannot link it
somewhere else when the target sink is absent at host start.

Gate narrowly and widen as models are validated; a tuning aimed at the wrong
drivers can sound worse than none and can stress them. When a tuning covers a model
it was not measured on, say so in `tuning.conf` — the provenance fields are there to
keep that distinction visible rather than implied.

Two hard requirements:

- **End in a limiter.** Peaks must stay under 0 dBFS with headroom.
- **Do not boost what the drivers cannot deliver.** The XPS 14 tuning
  deliberately *cuts* 40 Hz by around 18 dB. Excursion down there buys nothing
  and costs distortion.

## Building one

Measuring a laptop and fitting a filter-chain to it is a separate job with its own
tools, in [omarchy-audio-tuner](https://github.com/omacom-io/omarchy-audio-tuner).
It is not installed by default — almost nobody authoring a tuning, and it needs
python, ffmpeg and mpv.

```bash
omarchy pkg add omarchy-audio-tuner
```

Its README is the walkthrough, and covers both cases: copying a reference that
already sounds right (how the XPS 14 tuning was made, no microphone needed), and
designing from scratch, which needs a *calibrated* measurement mic and a target
curve that measurement alone cannot give you.

## What a tuning must report

A tuning is not reviewable on "sounds better to me". Record these, measured, in
`tuning.conf`:

| Field | What it is |
|---|---|
| `magnitude_rms_db` | Deviation from the reference or target it was fitted to |
| `bass_group_delay_swing_ms` | Max minus min group delay, 30–300 Hz |
| `limiter_headroom_db` | Worst-case peak against the limiter threshold |
| `dynamic_range_delta_lu` | LRA change against the reference |

Measure electrically by capturing the physical speaker sink's monitor, which sits
upstream of the volume control, so results are independent of listening level.

## How this fits the audio graph

Two things about the surrounding system are worth knowing, because both caused
real bugs:

- **Volume lives downstream of the tuning.** A tuning is a virtual sink that
  becomes the default output, and changing *its* volume would alter the level
  going into the processing — moving the display while the speakers stay put, and
  changing the tone of anything with a compressor or limiter in it.
  `omarchy-audio-output-sink` is the single definition of "which sink does this
  output's volume really use": it resolves a sink through any DSP sink to the
  physical one, and with no argument resolves the current default output. The
  volume keys, the output switcher's OSD and the audio panel all use it, so they
  cannot disagree. Resolving the *current default* rather than "whatever a tuning
  fronts" is what keeps it correct when headphones or HDMI are selected while a
  tuning still exists.
- **The fronted sink is hidden.** The tuning and the physical speakers both exist
  in the graph, and selecting the physical one would only bypass the tuning. So
  `omarchy-audio-sink-availability` reports it unavailable and
  `omarchy-audio-output-switch` skips it, leaving one speaker entry in the panel.
  A WirePlumber smart filter would remove the need for both — it leaves the real
  device as the default output — but on PipeWire 1.6.8 / WirePlumber 0.5.15 the
  graph loads and links correctly as a smart filter and then passes audio through
  unprocessed. Revisit when that is understood.
- **EasyEffects cannot coexist with a tuning.** It moves any stream that follows
  the default sink to its own sink, so it would grab audio back from a
  filter-chain. `on` refuses while it is running rather than installing a graph
  that would be bypassed.
- **The tuning's own output must not be moved.** A filter-chain's output is a
  playback stream like any other, so anything rerouting "all streams" to a newly
  selected output would drag the processing with it — onto headphones, or into the
  tuning's own sink, which is a cycle. The tuning sets `node.dont-move`, and
  `omarchy-audio-output-set-default` moves only streams that carry an
  `application.name`.
