# Observed I²C registers — LincStation N1

**Language / Sprache:** [English](../README.md) | [Deutsch](de/I2C-REGISTER.md)

**Use only on verified hardware.** Controller address on the investigated unit: `0x26`; bus during testing: `0`. This is not a guarantee for all N1 devices.

| LED | White ON | Red ON | White OFF | Red OFF | White blink | Red blink |
|---|---|---|---|---|---|---|
| SATA0 | A0 04 | A0 08 | B0 04 | B0 08 | 52 | 53 |
| SATA1 | A0 10 | A0 20 | B0 10 | B0 20 | 54 | 55 |
| NVMe0 | A1 01 | A1 02 | B1 01 | B1 02 | 58 | 59 |
| NVMe1 | A1 04 | A1 08 | B1 04 | B1 08 | 5A | 5B |
| NVMe2 | A1 10 | A1 20 | B1 10 | B1 20 | 5C | 5D |
| NVMe3 | A1 40 | A1 80 | B1 40 | B1 80 | 5E | 5F |
| Network | A0 40 | A0 80 | B0 40 | B0 80 | 56 | 57 |

Blink register values: `00` = off; `01` = on. For status LEDs, the script writes fixed red/white states; warnings are not displayed by blinking those status LEDs.

## RGB registers

| Register | Meaning |
|---|---|
| `0x90` | Effect: `0` solid, `1` breathing, `2` two-color chasing |
| `0x91` | Brightness `0`–`255` |
| `0x92`–`0x94` | RGB color for solid/breathing |
| `0x95`–`0x97` | First chasing color |
| `0x98`–`0x9A` | Second chasing color |

**Illustration only — DO NOT execute blindly:** `i2cset -y 0 0x26 0x90 0x01` would enable the breathing effect on the tested hardware. Incorrect writes can misconfigure devices, cause instability, or damage hardware.

Addresses `0x08` and `0x44` were also observed on the bus. They are **not** the LED controller and must not receive these LED register writes.
