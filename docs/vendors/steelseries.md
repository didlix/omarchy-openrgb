# SteelSeries (Aerox / Rival mice)

Verified with an Aerox 3 Wireless.

## What to expect

- OpenRGB exposes the mouse with **Direct** mode only (no Static, no Off).
  The plugin falls back to Direct automatically; the colour holds for as long
  as the SDK server runs, which is what the systemd unit is for.
- "Off" becomes black (no native Off mode).
- Lighting a wireless mouse costs battery.

## The white flash on click

If the mouse lights up **white on every click**, that is the firmware's own
*reactive illumination* feature, not OpenRGB. Turn it off once with
[rivalcfg](https://github.com/flozz/rivalcfg):

```bash
rivalcfg --reactive-color off
```

## Colour doesn't survive sleep

Wireless SteelSeries mice micro-sleep within seconds of inactivity and wake
showing the colour stored in **firmware**, not the Direct-mode colour — and
their firmware ignores OpenRGB's SaveMode. Persist through rivalcfg instead,
via the plugin's `persist_commands` hook in
`~/.local/state/omarchy-rgb/state.json`:

```json
"persist_commands": [
  ["rivalcfg", "--z1", "{color}", "--z2", "{color}", "--z3", "{color}"]
]
```

`{color}` is replaced with the brightness-scaled hex (`#000000` when off).
Persist commands run on discrete actions only (toggles, presets, slider
release) — slider drags skip them to spare the mouse's flash memory.

Zone options differ per model — check `rivalcfg --help` for yours.
