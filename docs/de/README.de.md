# LincStation N1 – Linux LED & RGB Control Center

**Language / Sprache:** [English](../../README.md) | **Deutsch**

**Community-Projekt / inoffiziell. Keine Verbindung zu LincPlus.**

Auf der **LincStation N1 von LincPlus** können bei der Nutzung eines anderen Betriebssystems statt des mitgelieferten Unraid blinkende Status-LEDs auffallen. Bei der untersuchten N1 wurden die LEDs **nicht automatisch durch das BIOS** entsprechend Laufwerks- und Netzwerkzustand verwaltet, sondern durch eine Softwareansteuerung eines I²C-Controllers. Das Verhalten kann je nach Firmware/OS variieren.

Dieses Projekt steuert sieben kleine Laufwerks-/Netzwerk-LEDs und den RGB-Streifen unter Linux. Entwickelt und praktisch erprobt unter **OpenMediaVault auf Debian**. **Ubuntu und andere Linux-Distributionen sind denkbar, aber hier nicht getestet**; das Installationsskript unterstützt ausschließlich Debian-/Ubuntu-Systeme mit `apt`.

## Funktionen

- Status-LEDs: Weiß = erkannt/OK, Rot = Störung, Aus = nicht vorhanden, Unbekannt = keine Umschaltung.
- SMART-Auswertung für **zwei fest zugeordnete NVMe-Laufwerke**, PCI-Pfade `0000:05:00.0` und `0000:04:00.0` (vor Ort verifizieren).
- Andere NVMe-/SATA-Steckplätze werden **nicht geraten**: Wenn ihre Zuordnung nicht eindeutig ist, bleibt ihr Status `UNBEKANNT`.
- Netzwerk-Carrier-Prüfung für PCI `0000:01:00.0`.
- RGB: Aus, Dauerlicht, Atmen, zwei Farben im Lauflicht, Helligkeit, gespeicherte Einstellungen.
- SMART-Warnung: gelbes Atmen; kritische NVMe-Meldung: rotes Atmen. Unlesbare SMART-Werte werden als Warnung behandelt.
- Weboberfläche auf Port 8088, Passwortschutz optional, Passwort über UI änderbar.
- systemd-Timer alle ca. 30 Sekunden; RAM-Zwischenspeicher unter `/run/lincstation-led/` vermeidet wiederholte identische I²C-Schreibzugriffe.

<img src="../../Webpage N1.PNG"
     alt="LincStation N1 Weboberfläche"
     width="600">

## Vor der Installation – unbedingt lesen

**I²C-Zugriffe sind hardwareabhängig und können bei falschem Bus, falscher Adresse oder falschem Register Schäden oder Fehlfunktionen auslösen.** Kein allgemeines Plug-and-Play-Tool. Lies [Hardware-Nachweis](HARDWARE-VERIFIKATION.md), [Bus-Sicherheit](SICHERHEIT-UND-BUS.md), [Register](I2C-REGISTER.md) und [Python/Web-Architektur](PYTHON-WEB-UND-ARCHITEKTUR.md). Das Programm darf nur auf einer identifizierten LincStation N1 mit überprüfter Controllerzuordnung verwendet werden.

Die untersuchte Maschine verwendete **Bus 0, Controller-Adresse `0x26`**. Weitere Geräte `0x08` und `0x44` waren sichtbar. `0x26` allein beweist nicht, dass das gefundene Gerät der LED-Controller ist.

## Installation – neue Installation

1. Repository als ZIP herunterladen und entpacken oder mit `git clone` beziehen.
2. Ins Repository wechseln und als root installieren:

   ```bash
   sudo bash install.sh
   ```

   Das Skript führt `apt-get update` aus und installiert `i2c-tools`, `smartmontools`, `jq`, `python3`, `python3-flask`, `python3-werkzeug`, `util-linux` und `pciutils`. Es richtet `/opt/lincstation-led-web/`, `/usr/local/sbin/lincstation-led-control.sh`, die systemd-Units und einen eingeschränkten Web-Benutzer ein. Es aktiviert **nur die Weboberfläche**. Es schreibt **noch nichts** an I²C.

3. Weboberfläche: `http://Lincstation:8088` (ggf. IP-Adresse statt Hostname). Einmalige Zugangsdaten stehen in `/root/lincstation-led-web-password.txt` (nur root). Passwort im Web ändern.
4. **Nur nach unabhängiger Überprüfung des I²C-Busses und des Controllers**:

   ```bash
   sudo bash enable-leds.sh
   ```

   Das Skript zeigt `i2cdetect -l`, fragt die geprüfte Busnummer ab, kontrolliert den sysfs-Pfad samt PCI-Controller `0000:00:15.0` und ID `8086:4de8` und verlangt eine ausdrückliche Bestätigung. Es speichert Busnummer, Adaptername und PCI-Daten in `/etc/lincstation-led.conf` und aktiviert erst dann den LED-Timer.

5. Status prüfen:

   ```bash
   systemctl status lincstation-led-web.service
   systemctl status lincstation-led-control.timer
   journalctl -u lincstation-led-control.service -n 50 --no-pager
   ```

**Bestehende Installationen:** `install.sh` bricht absichtlich ab, wenn eine bestehende Web- oder Controller-Installation erkannt wird. Keine automatische Migration oder Überschreibung deiner funktionierenden LincStation. Erst Backup und bewusste Übernahme der Konfiguration.

## Was bleibt gespeichert?

| Ort | Inhalt |
|---|---|
| `/opt/lincstation-led-web/data/rgb.json` | Gewählter RGB-Modus, Farben und Helligkeit (dauerhaft) |
| `/opt/lincstation-led-web/data/security.json` | Passwortschutz und Passwort-Hash (dauerhaft, kein Klartext) |
| `/etc/lincstation-led.conf` | Freigegebene I²C-Busnummer und Adaptername (dauerhaft) |
| `/run/lincstation-led/` | Temporärer LED-/RGB-Zustandsvergleich (nach Neustart weg) |

Die LED-Hardware kann ihren letzten Zustand behalten. Nach Neustart setzt der erste erfolgreiche Timerlauf die gespeicherten Einstellungen erneut.

## Grenzen und Portabilität

- **Debian/OMV:** Entwickelt und getestet; versionsabhängige Abweichungen möglich.
- **Ubuntu:** Linux-Tools sind grundsätzlich verfügbar, aber noch nicht auf einem Ubuntu-N1 getestet.
- **Andere Linux-Systeme:** Controller-Skript benötigt Bash, `smartctl`, `jq`, `i2c-tools`, `lsblk`, `flock`, `systemd`; Installation dort manuell.
- **NVMe-Slotzuordnung:** Aktuell nur zwei PCI-Pfade explizit implementiert. Andere Belegungen müssen geprüft und angepasst werden.
- **SATA-LEDs:** Bei vorhandenen SATA-Datenträgern keine automatische Slotzuordnung, solange nicht verifiziert.
- **Web:** Flask-Entwicklungsserver für ein vertrauenswürdiges Heimnetz, nicht für eine direkte Internetfreigabe. Bei deaktiviertem Passwortschutz können Geräte im erreichbaren Netz RGB-Einstellungen ändern. Zugriff über Firewall einschränken.
- **Bus-Schutz:** PCI-Pfad und PCI-ID bieten eine stärkere Host-Adapter-Prüfung, beweisen aber nicht die Identität des Slave-Geräts `0x26`. Siehe Sicherheitsdokument.

## Deinstallation

```bash
sudo bash uninstall.sh
```

Stoppt/deaktiviert die von diesem Paket eingerichteten Dienste und entfernt deren Unit-Dateien. Persönliche Einstellungen und Programmdateien werden absichtlich nicht gelöscht.

## Aufbau

```
controller/lincstation-led-control.sh
web/app.py
web/templates/index.html
systemd/lincstation-led-control.service
systemd/lincstation-led-control.timer
systemd/lincstation-led-web.service
docs/I2C-REGISTERS.md
docs/I2C-SAFETY-AND-BUS.md
docs/HARDWARE-VERIFICATION.md
docs/PYTHON-WEB-AND-ARCHITECTURE.md
docs/SOURCE-CODE-REFERENCE.md
docs/de/README.de.md
docs/de/I2C-REGISTER.md
docs/de/SICHERHEIT-UND-BUS.md
docs/de/HARDWARE-VERIFIKATION.md
docs/de/PYTHON-WEB-UND-ARCHITEKTUR.md
docs/de/VOLLSTAENDIGER-QUELLCODE.md
install.sh
enable-leds.sh
uninstall.sh
```

## Lizenz

Im Repository liegt eine `LICENSE`-Datei mit dem Text der **GNU GPL Version 3**. Die Rechte an sämtlichen Bestandteilen sollten vom Repository-Inhaber geprüft werden.

## Technischer Nachweis des I²C-Adapters

Die untersuchte N1 zeigt den PCI-Host-Controller `0000:00:15.0` (Intel `8086:4de8`, Treiber `intel-lpss`) und den sysfs-Pfad `/sys/devices/pci0000:00/0000:00:15.0/i2c_designware.0/i2c-0/i2c-dev/i2c-0`. Das erklärt, **warum der Linux-Bus in dieser Konfiguration `i2c-0` heißt**. Die Zuordnung der Adresse `0x26` zum LED-Controller stammt ergänzend aus Herstellersteuerung und praktischen Funktionstests. Siehe [Hardware-Verifikation](HARDWARE-VERIFIKATION.md).

## Python, HTML und automatische Installation

Die komplette Python-Anwendung liegt in `web/app.py`, die HTML/CSS/JavaScript-Oberfläche in `web/templates/index.html`. Beide werden von `install.sh` automatisch nach `/opt/lincstation-led-web/` kopiert. Python-Abhängigkeiten werden über `apt` installiert; es ist keine separate `pip`-Installation nötig. Weitere Einzelheiten: [Python/Web/Architektur](PYTHON-WEB-UND-ARCHITEKTUR.md).

## Vollständiger Quellcode zum Nachlesen

Alle Python-, HTML-/CSS-/JavaScript- und Bash-Quelldateien sind im [vollständigen Quellcode-Katalog](VOLLSTAENDIGER-QUELLCODE.md) abgedruckt. Die ausführbaren Originaldateien liegen in `web/`, `controller/` und im Projektverzeichnis. Die Architektur wird in [`docs/PYTHON-WEB-UND-ARCHITEKTUR.md`](PYTHON-WEB-UND-ARCHITEKTUR.md) erläutert.

## Weiteres Projekt

[LincStation S1 LCD & LED Control](https://github.com/AndiBcool/lincstation-s1-lcd-led-control) – separates Projekt für die **S1**. Programme und Hardwareanleitungen der N1 und S1 nicht austauschen.
