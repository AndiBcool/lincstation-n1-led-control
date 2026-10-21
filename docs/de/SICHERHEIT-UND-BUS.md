# I²C-Sicherheit und Busänderungen

**Sprache / Language:** [English](../../README.md) | [Deutsch](README.de.md)


**Keine unbekannten I²C-Geräte beschreiben.** Falscher Bus, falsche Adresse oder falsches Register können Hardware stören oder beschädigen. Selbst aktive Adressscans können bei manchen Geräten Nebenwirkungen haben.

Bei der untersuchten LincStation N1 liegt der LED-Controller nach Herstellerskript und Funktionstest an `0x26` auf `i2c-0`. Der Bus ist an Intel PCI `0000:00:15.0` (ID `8086:4de8`) über `i2c_designware.0` angebunden.

Der Installer `install.sh` führt **keinen aktiven I²C-Scan und keine Schreibbefehle** aus. `enable-leds.sh` zeigt Adapter nur mit `i2cdetect -l` an und prüft dann ausschließlich Linux-Metadaten: `/sys/class/i2c-dev/i2c-N`, PCI-Gerätepfad und PCI-ID. Erst nach explizitem `JA` aktiviert er den Timer.

Die Steuerung prüft diese Bindung vor jedem Schreibdurchlauf. Bei einer Bus-Umnummerierung oder abweichenden PCI-Zuordnung bricht sie ab. **Keine automatische Suche nach `0x26` auf anderen Bussen!**

Wichtig: Der PCI-Pfad identifiziert den **Host-Controller**, nicht das an `0x26` angeschlossene Gerät. Der Betreiber muss sicher sein, dass es sich um die erwartete N1-Hardware handelt.

Bei Änderungen zuerst den Timer stoppen:

```bash
sudo systemctl disable --now lincstation-led-control.timer
i2cdetect -l
readlink -f /sys/class/i2c-dev/i2c-0
sudo cat /etc/lincstation-led.conf
```

Eine erneute Freigabe sollte erst nach Prüfung erfolgen. Konfigurationsdateien nicht blind kopieren; keine fremden `i2cset`-Beispiele ausprobieren.
