#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Als root ausführen (sudo bash install.sh)'; exit 1; }
ROOT=$(cd "$(dirname "$0")" && pwd)
[[ -f "$ROOT/controller/lincstation-led-control.sh" ]] || { echo 'Repository unvollständig'; exit 1; }
command -v apt-get >/dev/null || { echo 'Nur Debian/Ubuntu mit apt unterstützt'; exit 1; }
# Vor Änderungen erkennen, ob bereits eine Installation existiert.
if [[ -e /usr/local/sbin/lincstation-led-control.sh || -e /etc/lincstation-led.conf || -e /opt/lincstation-led-web/app.py || -e /etc/systemd/system/lincstation-led-control.service || -e /etc/systemd/system/lincstation-led-web.service ]]; then
 echo 'Bestehende Installation erkannt: Abbruch vor Paketinstallation und Dateiveränderungen.'
 exit 1
fi
echo 'ACHTUNG: Nur LincStation N1 mit verifizierter I2C-Belegung!'
echo 'Keine automatische Bus-Erkennung und keine Hardware-Schreibtests im Installer.'
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y i2c-tools smartmontools jq python3 python3-flask python3-werkzeug util-linux pciutils
for tool in i2cset smartctl jq lsblk flock; do command -v "$tool" >/dev/null || exit 1; done
python3 -c 'import flask,werkzeug'
mkdir -p /opt/lincstation-led-web/{templates,data} /usr/local/sbin
install -m 755 "$ROOT/controller/lincstation-led-control.sh" /usr/local/sbin/lincstation-led-control.sh
install -m 644 "$ROOT/web/app.py" /opt/lincstation-led-web/app.py
install -m 644 "$ROOT/web/templates/index.html" /opt/lincstation-led-web/templates/index.html
if ! id lincledweb >/dev/null 2>&1; then useradd --system --home-dir /opt/lincstation-led-web --shell /usr/sbin/nologin lincledweb; fi
python3 - <<'PY2'
from pathlib import Path
import json,secrets
from werkzeug.security import generate_password_hash
p=Path('/opt/lincstation-led-web/data');p.mkdir(parents=True,exist_ok=True)
(p/'rgb.json').write_text(json.dumps({'mode':'loop','brightness':180,'color0':'#00ffff','color1':'#a000ff'})+'\n')
pw=secrets.token_urlsafe(20)
(p/'security.json').write_text(json.dumps({'enabled':True,'password_hash':generate_password_hash(pw)})+'\n')
Path('/root/lincstation-led-web-password.txt').write_text('Benutzer: admin\nPasswort: '+pw+'\n')
PY2
chmod 600 /root/lincstation-led-web-password.txt
chown -R root:root /opt/lincstation-led-web
chown -R lincledweb:lincledweb /opt/lincstation-led-web/data
chmod 750 /opt/lincstation-led-web/data
chmod 600 /opt/lincstation-led-web/data/security.json
chmod 644 /opt/lincstation-led-web/data/rgb.json
install -m 644 "$ROOT/systemd/lincstation-led-control.service" /etc/systemd/system/
install -m 644 "$ROOT/systemd/lincstation-led-control.timer" /etc/systemd/system/
install -m 644 "$ROOT/systemd/lincstation-led-web.service" /etc/systemd/system/
# Nur Web aktivieren; I2C bleibt bis zur expliziten Freigabe AUS.
systemctl daemon-reload
systemctl enable --now lincstation-led-web.service
cat <<'MSG'
Weboberfläche: http://Lincstation:8088
Zugangsdaten: /root/lincstation-led-web-password.txt
LED-TIMER IST NOCH NICHT AKTIV!
Zuerst 'bash enable-leds.sh' nach Prüfung des I2C-Adapters ausführen.
MSG
