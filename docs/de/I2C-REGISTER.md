# Ermittelte I²C-Register – LincStation N1

**Sprache / Language:** [English](../../README.md) | [Deutsch](README.de.md)


**Nur an verifizierter Hardware verwenden.** Controller-Adresse in der untersuchten LincStation: `0x26`, Bus während der Tests: `0`. Diese Angaben sind keine allgemeine Zusicherung.

| LED | Weiß EIN | Rot EIN | Weiß AUS | Rot AUS | Weiß blinken | Rot blinken |
|---|---|---|---|---|---|---|
| SATA0 | A0 04 | A0 08 | B0 04 | B0 08 | 52 | 53 |
| SATA1 | A0 10 | A0 20 | B0 10 | B0 20 | 54 | 55 |
| NVMe0 | A1 01 | A1 02 | B1 01 | B1 02 | 58 | 59 |
| NVMe1 | A1 04 | A1 08 | B1 04 | B1 08 | 5A | 5B |
| NVMe2 | A1 10 | A1 20 | B1 10 | B1 20 | 5C | 5D |
| NVMe3 | A1 40 | A1 80 | B1 40 | B1 80 | 5E | 5F |
| Netzwerk | A0 40 | A0 80 | B0 40 | B0 80 | 56 | 57 |

Werte bei Blinkregistern: `00` = aus, `01` = an. Bei Status-LEDs schreibt das Skript feste Rot-/Weiß-Zustände; eine Warnung wird nicht blinkend dargestellt.

## RGB-Register

| Register | Bedeutung |
|---|---|
| `0x90` | Effekt: `0` Dauerlicht, `1` Atmen, `2` Zweifarben-Lauflicht |
| `0x91` | Helligkeit `0`–`255` |
| `0x92`–`0x94` | RGB-Farbe für Dauerlicht/Atmen |
| `0x95`–`0x97` | Farbe 1 für Lauflicht |
| `0x98`–`0x9A` | Farbe 2 für Lauflicht |

**Beispiel nur zur Illustration, NICHT blind ausführen:** `i2cset -y 0 0x26 0x90 0x01` würde auf der getesteten Hardware den Atemeffekt aktivieren. Falsche Schreibzugriffe können andere Geräte fehlkonfigurieren, instabil machen oder in ungünstigen Fällen beschädigen.

Die Geräteadressen `0x08` und `0x44` wurden ebenfalls auf dem untersuchten Bus gesehen; sie gehören **nicht** zur LED-Steuerung und dürfen nicht mit den LED-Registerbefehlen beschrieben werden.
