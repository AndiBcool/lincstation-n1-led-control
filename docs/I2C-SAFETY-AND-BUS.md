# I²C safety and bus changes

**Language / Sprache:** [English](../README.md) | [Deutsch](de/SICHERHEIT-UND-BUS.md)

**Never write to unidentified I²C devices.** An incorrect bus, address, or register can disrupt or damage hardware. Even active address scans may affect some devices.

On the tested LincStation N1, vendor scripts and functional testing associated the LED controller with `0x26` on `i2c-0`. The bus connects through Intel PCI `0000:00:15.0` (ID `8086:4de8`) and `i2c_designware.0`.

`install.sh` performs **no active I²C scan or writes**. `enable-leds.sh` only lists adapters with `i2cdetect -l` and checks Linux metadata: `/sys/class/i2c-dev/i2c-N`, PCI path, and PCI ID. It enables the timer only after explicit `JA` confirmation.

The controller checks this binding before every write cycle and stops if the bus is renumbered or the PCI association changes. **There is no automatic search for `0x26` on other buses.**

The PCI path proves the **host adapter**, not the identity of the slave at `0x26`. The operator must independently establish that the expected N1 hardware is present.

Before changing anything, stop the timer:

```bash
sudo systemctl disable --now lincstation-led-control.timer
i2cdetect -l
readlink -f /sys/class/i2c-dev/i2c-0
sudo cat /etc/lincstation-led.conf
```

Re-enable only after verification. Do not blindly copy configuration files or execute unrelated `i2cset` examples.
