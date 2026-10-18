# Architektur: Bash, Python, Flask, HTML und systemd

## Datenfluss

1. `lincstation-led-control.timer` startet ca. alle 30 Sekunden den oneshot-Dienst `lincstation-led-control.service`.
2. `controller/lincstation-led-control.sh` liest `smartctl -j`, `lsblk`, sysfs-Netzwerk-Carrier und die gespeicherten RGB-Einstellungen aus `rgb.json`.
3. Das Skript prüft die **explizite I²C-Hardwarefreigabe** unter `/etc/lincstation-led.conf` und sendet erst dann Schreibzugriffe an Adresse `0x26`.
4. Aktuelle Statusdaten landen als JSON unter `/run/lincstation-led/status.json`. LED-/RGB-Zustands-Caches unter `/run` vermeiden unnötige wiederholte Schreibzugriffe. Nach einem Neustart ist dieser Cache leer.
5. `web/app.py` ist ein Python-3-Flask-Webserver auf TCP 8088; `web/templates/index.html` enthält die Weboberfläche samt clientseitigem JavaScript. Die Oberfläche liest `/api/state` und speichert Farb- und Sicherheitsänderungen über die API.

## Python-Module

- `flask`: HTTP-Server, JSON-API, Template-Ausgabe.
- `werkzeug.security`: Passwort-Hashing und Verifizierung. **Passwörter werden nicht als Klartext in `security.json` gespeichert.**
- Standardbibliothek `json`, `os`, `secrets`, `pathlib`: Konfigurationsdateien und sichere temporäre Dateinamen.

Installation über Debian-/Ubuntu-Pakete `python3`, `python3-flask`, `python3-werkzeug`; kein `pip` und keine virtuelle Python-Umgebung erforderlich. Die Python-Anwendung wird durch systemd als eingeschränkter Benutzer `lincledweb` gestartet. Der Controller selbst läuft mit root-Rechten, weil SMART und I²C dies erfordern können.

## HTTP-Endpunkte

| Methode | Pfad | Zweck |
|---|---|---|
| GET | `/` | HTML-Oberfläche |
| GET | `/api/state` | RGB-Konfiguration und LED-/SMART-Status |
| POST | `/api/rgb` | RGB-Modus, Helligkeit und Farben speichern |
| GET | `/api/security` | Passwortschutzstatus abfragen |
| POST | `/api/security` | Passwortschutz ändern oder Passwort aktualisieren |

HTTP Basic Auth schützt die Oberfläche, wenn aktiviert. **Basic Auth ist ohne HTTPS nicht verschlüsselt**; deshalb nur in einem vertrauenswürdigen lokalen Netzwerk betreiben, nicht ins Internet freigeben. Der enthaltene Flask-Server ist nicht als öffentlich erreichbarer Produktionsserver ausgelegt.

## Dateien und Berechtigungen

| Datei/Verzeichnis | Zweck |
|---|---|
| `/usr/local/sbin/lincstation-led-control.sh` | Installiertes Bash-Steuerungsskript |
| `/opt/lincstation-led-web/app.py` | Python-Webserver |
| `/opt/lincstation-led-web/templates/index.html` | HTML, CSS und JavaScript |
| `/opt/lincstation-led-web/data/rgb.json` | Dauerhafte RGB-Einstellungen |
| `/opt/lincstation-led-web/data/security.json` | Dauerhafter Passwort-Hash und Schalter |
| `/root/lincstation-led-web-password.txt` | Generiertes Erstpasswort, nur root; nach Passwortänderung nicht mehr aktuell |
| `/etc/lincstation-led.conf` | Freigegebene Bus-/PCI-Zuordnung |
| `/run/lincstation-led/` | Flüchtige Laufzeitdaten |
| `/etc/systemd/system/lincstation-led-*.service` | Systemd-Dienste |
| `/etc/systemd/system/lincstation-led-control.timer` | 30-Sekunden-Timer |

## Linux-Abhängigkeiten

`i2c-tools` (`i2cset`, `i2cdetect`), `smartmontools` (`smartctl`), `jq`, `util-linux` (`flock`, `lsblk`), `pciutils` (`lspci`), `python3`, `python3-flask`, `python3-werkzeug`. `readlink`, `sed`, `awk`, `sha256sum` und weitere Basiswerkzeuge stammen aus üblichen Debian-Coreutils/Basispaketen. `systemd` wird vorausgesetzt.

## Installation und Aktivierung

```bash
sudo bash install.sh       # Pakete, Python, HTML, Dienste; KEIN I2C-Schreiben
sudo bash enable-leds.sh   # Hardwarepfad prüfen und ausdrücklich freigeben
```

Die Weboberfläche ist danach unter `http://<NAS-IP>:8088` erreichbar. Vor der Busfreigabe läuft nur die Weboberfläche, der LED-Timer bleibt deaktiviert.
