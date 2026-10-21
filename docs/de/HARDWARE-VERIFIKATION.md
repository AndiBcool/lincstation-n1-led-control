# Hardware-Nachweis: LincStation N1 (untersuchte Maschine)

**Sprache / Language:** [English](../../README.md) | [Deutsch](README.de.md)


## Warum Bus 0?

Die LED- und RGB-Steuerung funktioniert auf dem untersuchten N1 über `/dev/i2c-0`, Geräteadresse `0x26`. Das Herstellerskript benutzt ebenfalls Bus 0 und Adresse 0x26. Dies ist ein **funktionaler Nachweis**, kein ausgelesener Chip-Identifikationscode.

**Beobachtete Ausgaben** (Linux/OMV/Debian):

```text
i2c-0   i2c   Synopsys DesignWare I2C adapter
readlink -f /sys/class/i2c-dev/i2c-0
/sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-dev/i2c-0
lspci -nnk -s 00:15.0
00:15.0 Serial bus controller [0c80]: Intel Corporation Serial IO I2C Host Controller [8086:4de8] (rev 01)
        Kernel driver in use: intel-lpss
        Kernel modules: intel_lpss_pci
```

Der physische Intel Serial-IO-I²C-Host-Controller befindet sich an PCI `0000:00:15.0`, Vendor/Device `8086:4de8`. Der Kernel bindet ihn über Intel LPSS an den DesignWare-I²C-Adapter an, der auf dem untersuchten System als `i2c-0` erscheint. Die Adresse `0x26` ist die **I²C-Slave-Adresse**, nicht die PCI-ID.

Andere Adapter auf derselben N1 können ebenfalls `Synopsys DesignWare I2C adapter` heißen. Der Adaptername allein genügt **nicht** zur Identifizierung.

## Gefahrlos selbst nachprüfen (nur Metadaten, keine I²C-Transaktion)

```bash
i2cdetect -l
readlink -f /sys/class/i2c-dev/i2c-0
cat /sys/class/i2c-dev/i2c-0/name
lspci -nnk -s 00:15.0
cat /sys/bus/pci/devices/0000:00:15.0/vendor
cat /sys/bus/pci/devices/0000:00:15.0/device
```

`i2cdetect -l` **listet Adapter** und führt keinen Adressscan aus. `i2cdetect -y 0` ist dagegen ein aktiver Scan und nicht generell risikofrei. Keine unbekannten Register per `i2cset` testen.

## Installer-Prüfung

`enable-leds.sh` prüft `/sys/class/i2c-dev/i2c-N` und dessen aufgelösten Pfad, PCI `0000:00:15.0`, die ID `8086:4de8` und den Adapternamen. Erst nach ausdrücklichem `JA` wird der Timer aktiviert. Der Controller prüft diese Angaben bei jedem Lauf erneut. Wenn der Bus nach Kernel-Änderung umnummeriert wird, stoppt die Steuerung sicher. **Es gibt keine automatische Bus-Umschaltung.** Eine andere Busnummer muss anhand des PCI-Pfads neu überprüft und ausdrücklich freigegeben werden.

**Grenze:** Der PCI-Pfad beweist den Host-Controller, nicht, dass an Slave-Adresse `0x26` tatsächlich ein LED-Gerät hängt. Die Zuordnung beruht auf Herstellersteuerung und den Funktionstests an der untersuchten N1. Hardware-/Firmwarevarianten sind nicht ausgeschlossen.
