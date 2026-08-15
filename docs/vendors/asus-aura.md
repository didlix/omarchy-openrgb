# ASUS Aura (motherboards)

Verified with a ROG STRIX Z790-I GAMING WIFI.

## One device, several zones

Case ARGB strips plug into the motherboard's addressable headers, so OpenRGB
shows a single *motherboard* device containing zones — e.g. `Aura Mainboard`
(the LED on the board itself) plus `Aura Addressable 1/2` (the headers your
case strips are on). The plugin's DEVICES list shows controllers, so all of
it appears (and toggles) as one entry, and every zone gets the same colour.

## Behaviour

- Has a proper **Static** mode: colour persists on the controller across
  reboots and shell restarts. Best-case hardware for this plugin.
- Has a native **Off** mode — "off" genuinely turns the LEDs off rather than
  going black.
- The USB Aura controller needs no i2c setup. Aura devices attached via
  **SMBus** (some boards, RGB DRAM) additionally need the `i2c-dev` and
  `i2c-i801`/`i2c-piix4` kernel modules — see the OpenRGB docs.

## Gotcha: device order is not stable

Across boots, OpenRGB may enumerate devices in a different order (a mouse
can become device 0). Never rely on device indices — the plugin matches by
name for exactly this reason.
