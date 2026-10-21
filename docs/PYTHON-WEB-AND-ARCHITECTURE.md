# Architecture: Bash, Python, Flask, HTML and systemd

**Language / Sprache:** [English](../README.md) | [Deutsch](de/PYTHON-WEB-UND-ARCHITEKTUR.md)

## Data flow

1. `lincstation-led-control.timer` starts the one-shot `lincstation-led-control.service` approximately every 30 seconds.
2. `controller/lincstation-led-control.sh` reads `smartctl -j`, `lsblk`, network carrier state from sysfs, and RGB settings from `rgb.json`.
3. Before writing to address `0x26`, the script verifies the **explicitly approved I²C host** recorded in `/etc/lincstation-led.conf`.
4. It writes status JSON to `/run/lincstation-led/status.json`. Temporary LED/RGB state caches under `/run` prevent redundant writes and are cleared at reboot.
5. `web/app.py` runs a Python 3 Flask web server on TCP port 8088. `web/templates/index.html` provides the UI and client-side JavaScript. The UI reads `/api/state` and submits color/security settings through the API.

## Python dependencies

- `flask`: HTTP server, JSON API and templates.
- `werkzeug.security`: password hashing and verification. **`security.json` does not store plaintext passwords.**
- Python standard library `json`, `os`, `secrets`, `pathlib`: configuration and secure temporary filenames.

Installed from Debian/Ubuntu packages `python3`, `python3-flask`, `python3-werkzeug`; no `pip` or virtual environment required. The web app runs as restricted user `lincledweb`. The controller runs as root because SMART and I²C access may require elevated permissions.

## HTTP endpoints

| Method | Path | Purpose |
|---|---|---|
| GET | `/` | HTML interface |
| GET | `/api/state` | RGB configuration and LED/SMART status |
| POST | `/api/rgb` | Save RGB mode, brightness and colors |
| GET | `/api/security` | Read password-protection state |
| POST | `/api/security` | Change password protection or update password |

HTTP Basic Authentication protects the UI when enabled. **Basic Auth without HTTPS is not encrypted**; operate only on a trusted LAN and do not expose directly to the internet. The bundled Flask development server is not intended as a public production server.

## Files and permissions

| Path | Purpose |
|---|---|
| `/usr/local/sbin/lincstation-led-control.sh` | Installed Bash controller |
| `/opt/lincstation-led-web/app.py` | Python web application |
| `/opt/lincstation-led-web/templates/index.html` | HTML/CSS/JavaScript UI |
| `/opt/lincstation-led-web/data/rgb.json` | Persistent RGB settings |
| `/opt/lincstation-led-web/data/security.json` | Persistent password hash and enable switch |
| `/root/lincstation-led-web-password.txt` | Generated initial password (root-only; outdated after changing password) |
| `/etc/lincstation-led.conf` | Approved I²C host adapter |
| `/run/lincstation-led/` | Runtime state and cache |

For additional implementation details and exact code, consult the unchanged executable source files in `controller/`, `web/`, and the repository root. The original detailed German architecture document is retained under [docs/de/](de/PYTHON-WEB-UND-ARCHITEKTUR.md).
