# Hardware verification: LincStation N1 (tested unit)

**Language / Sprache:** [English](../README.md) | [Deutsch](de/HARDWARE-VERIFIKATION.md)

## Why bus 0?

On the tested N1, LED/RGB control worked via `/dev/i2c-0` at slave address `0x26`. The vendor control script also used bus 0 and address `0x26`. This is **functional evidence**, not a read-out chip identification code.

Observed Linux/OMV/Debian output:

```text
i2c-0   i2c   Synopsys DesignWare I2C adapter
readlink -f /sys/class/i2c-dev/i2c-0
/sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-dev/i2c-0
lspci -nnk -s 00:15.0
00:15.0 Serial bus controller [0c80]: Intel Corporation Serial IO I2C Host Controller [8086:4de8] (rev 01)
        Kernel driver in use: intel-lpss
        Kernel modules: intel_lpss_pci
```

The physical Intel Serial IO I²C host controller is at PCI `0000:00:15.0`, vendor/device `8086:4de8`. Linux binds it through Intel LPSS to the DesignWare adapter exposed as `i2c-0` on the tested system. `0x26` is an **I²C slave address**, not a PCI ID.

Other adapters on the same N1 may also be named `Synopsys DesignWare I2C adapter`; the adapter name alone is not sufficient.

## Safe metadata-only checks (no I²C transactions)

```bash
i2cdetect -l
readlink -f /sys/class/i2c-dev/i2c-0
cat /sys/class/i2c-dev/i2c-0/name
lspci -nnk -s 00:15.0
cat /sys/bus/pci/devices/0000:00:15.0/vendor
cat /sys/bus/pci/devices/0000:00:15.0/device
```

`i2cdetect -l` lists adapters **without** probing slave addresses. `i2cdetect -y 0` actively probes devices and is not universally risk-free. Never experiment with unknown registers using `i2cset`.

## Installer verification

`enable-leds.sh` checks `/sys/class/i2c-dev/i2c-N`, its resolved path, PCI `0000:00:15.0`, ID `8086:4de8`, and adapter name. Only after explicit `JA` confirmation is the timer enabled. The controller repeats the checks before every run. If the bus number changes after a kernel update, control stops rather than silently switching buses. A new bus must be independently verified and explicitly approved.

**Limit:** The PCI path identifies the host controller, not the device connected at `0x26`. That mapping is based on vendor control and practical tests on the investigated N1. Other hardware/firmware revisions are possible.
