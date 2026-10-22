# Why the battery ran down on a USB host, and the 500 mA fix

Measured on an iPad2,6 (p106) on 2026-10-22, Linux booted from NFS with XFCE
running, on a PC's USB 2.0 port.  Register meanings are PR #8's decoding of
the 12H321 `AppleD1946PMU` kext (`docs/research/p105-charging.md` there);
p106 runs the same kext and has the same `charger` node.

## What the PMU holds under Linux

Read with `i2cget -f -y 0 0x3c REG`:

| Reg | Value | Meaning |
|---|---|---|
| 0x3d | 0x02 | input current limit, 75 + ceil(2 * 100 / 8) = **100 mA** |
| 0x3f | 0x3f | charge-current ceiling 63 * 40 = 2520 mA; bit 0x40 (inhibit) clear |
| 0x4b..0x53 | 0, 0, 63, 63, 63 | per-temperature slots, as the ADT's `ichg-tbat-max` |
| 0x0a | 0x6f | bit 3 set: a USB source |

The charger is enabled.  What stops it is the 100 mA input limit, below the
system's own draw (380 to 450 mA with XFCE), so the battery supplies the
difference.  iOS on the same cable reports a 500 mA USB-host source.  The
gadget also declared 0 mA (`cdc2.c` sets `USB_CONFIG_ATT_SELFPOWER`, which
makes composite ignore `CONFIG_USB_GADGET_VBUS_DRAW`).

## Test

0x3d = 0x22 (75 + ceil(34 * 100 / 8) = 500 mA) for five minutes, run on the
device with an automatic revert on a temperature above 40 °C, a voltage above
4.25 V or any I2C error:

| | 0x3d = 0x02 | 0x3d = 0x22 |
|---|---|---|
| battery current | -380 to -411 mA | +5 to +27 mA ("Charging") |
| voltage | 4.142 V | 4.178 -> 4.185 V |
| temperature | 34.2 °C | 34.2 -> 34.6 °C |

## What this tree does now

- `g_cdc.usb2_maxpower=500` in the bootargs, with PR #8's
  `patches/tree/0003-usb-gadget-cdc2-usb2-maxpower.patch`: the gadget declares
  the 500 mA it draws.
- `tools/pmu-input-limit.c`, run by stage 2: if 0x0a reports a USB source and
  0x3d is below 0x22, write 0x22.  Nothing is written after a failed read;
  `-n` only reports.

Only the input limit changes.  Charge current, charge voltage, termination
and the PMU's protections stay as iBoot and iOS left them.

## Not done

- A wall charger is still treated as a 500 mA USB source.  iOS identifies
  adapters through Tristar (`brick_id`, ADC channel 6) and allows up to the
  ADT's `usb-input-limit-max` (2100 mA); that needs adapter detection first.
- No handling of unplug and replug after boot: the limit is set once.
