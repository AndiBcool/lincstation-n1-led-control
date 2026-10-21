# Complete source code — file reference

**Language / Sprache:** [English](../README.md) | [Deutsch](de/VOLLSTAENDIGER-QUELLCODE.md)

The actual source files in this repository are the authoritative executable versions. The original German [annotated full-source catalog](de/VOLLSTAENDIGER-QUELLCODE.md) is preserved without changing the code samples.

| Source file | Responsibility |
|---|---|
| [`web/app.py`](../web/app.py) | Flask web server, authentication, JSON API and configuration persistence |
| [`web/templates/index.html`](../web/templates/index.html) | Web interface, styling and JavaScript API client |
| [`controller/lincstation-led-control.sh`](../controller/lincstation-led-control.sh) | SMART/network monitoring, I²C LED/RGB control, status JSON |
| [`install.sh`](../install.sh) | Debian/Ubuntu packages, file deployment, account and systemd setup |
| [`enable-leds.sh`](../enable-leds.sh) | Explicit hardware verification and I²C write authorization |
| [`uninstall.sh`](../uninstall.sh) | Service shutdown and removal of installed systemd units |

## Flask routes

| Route | Description |
|---|---|
| `GET /` | Web interface |
| `GET /api/state` | LED/RGB status |
| `GET /api/security` | Password-protection state |
| `POST /api/security` | Change password or protection settings |
| `POST /api/rgb` | Save RGB settings |

**Safety:** Documentation is not a substitute for code review and hardware verification. Enable I²C writes only on verified LincStation N1 hardware.
