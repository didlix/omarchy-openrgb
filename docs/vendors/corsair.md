# Corsair

Corsair is one of OpenRGB's best-covered vendors (keyboards, mice, RAM,
Lighting Node / Commander controllers, many AIOs). Two things still bite:

## Device present but not detected: permissions

The SDK server runs as your user and needs udev to grant access to the
device's hidraw nodes. OpenRGB's packaged rules cover known product IDs; a
device missing from them shows `crw------- root root` on its `/dev/hidraw*`
nodes. Add a rule — **the details matter**:

```bash
# /etc/udev/rules.d/70-corsair-mydevice.rules   (find the ID with lsusb)
SUBSYSTEMS=="usb|hidraw", ATTRS{idVendor}=="1b1c", ATTRS{idProduct}=="XXXX", TAG+="uaccess"
```

- The file **must sort before 73** (`70-…`, not `99-…`): `TAG+="uaccess"` is
  processed by systemd's `73-seat-late.rules`, so later files are silently
  ignored.
- Re-trigger with `--action=add` (uaccess ignores the default "change"):

```bash
sudo udevadm control --reload-rules
sudo udevadm trigger --action=add --subsystem-match=hidraw
```

Verify with `getfacl /dev/hidrawN` — your user should be listed. Then rescan
(button in the popout's DEVICES section, or `omarchy-rgb rescan`).

## Permissions fine, still not detected: unregistered product ID

OpenRGB detects by exact VID:PID, and Corsair ships regional/revision
variants under different PIDs. Example: the K65 RGB MINI is registered as
`0x1BAF`, but a variant ships as `0x1BBD` — same protocol, invisible to
OpenRGB. Check whether your PID is known:

```bash
lsusb | grep -i corsair
strings /usr/bin/openrgb | grep -i "<your model>"
```

If the model is listed but your PID isn't in OpenRGB's detect tables (check
the `Controllers/Corsair*/…Detect.cpp` files upstream), the fix is a
one-line PID addition and a rebuild — and please submit it upstream at
<https://gitlab.com/CalcProgrammer1/OpenRGB> so the next release has it.

## Wireless and iCUE Link

Some wireless Corsair devices only work wired or have limited dongle
support, and the iCUE Link hub ecosystem is still patchy in OpenRGB. Wired
USB devices from the last several years are the safe bet.
