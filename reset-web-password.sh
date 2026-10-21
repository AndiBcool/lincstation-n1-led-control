#!/usr/bin/env bash
# LincStation N1 LED Control - reset web login password
set -Eeuo pipefail

APP_DIR="/opt/lincstation-led-web"
SEC_FILE="$APP_DIR/data/security.json"
SERVICE_USER="lincledweb"

if [[ $EUID -ne 0 ]]; then
  echo "Bitte als root ausführen: sudo bash $0" >&2
  exit 1
fi
if ! id "$SERVICE_USER" >/dev/null 2>&1; then
  echo "Fehler: Benutzer $SERVICE_USER existiert nicht." >&2
  exit 1
fi
if [[ ! -f "$SEC_FILE" ]]; then
  echo "Fehler: $SEC_FILE wurde nicht gefunden." >&2
  exit 1
fi
if ! python3 -c 'from werkzeug.security import generate_password_hash' >/dev/null 2>&1; then
  echo "Fehler: Python3 mit Werkzeug wird benötigt." >&2
  exit 1
fi

export LINCLED_SEC_FILE="$SEC_FILE" LINCLED_SERVICE_USER="$SERVICE_USER"
python3 - <<'PY'
import getpass
import json
import os
import pwd
import shutil
import tempfile
from datetime import datetime
from pathlib import Path
from werkzeug.security import generate_password_hash

path = Path(os.environ['LINCLED_SEC_FILE'])
user = os.environ['LINCLED_SERVICE_USER']
account = pwd.getpwnam(user)

try:
    data = json.loads(path.read_text(encoding='utf-8'))
    if not isinstance(data, dict) or not isinstance(data.get('enabled'), bool) or not isinstance(data.get('password_hash'), str):
        raise ValueError('Ungültige Struktur der security.json')
except (OSError, ValueError) as exc:
    raise SystemExit(f'Fehler beim Lesen der Sicherheitsdatei: {exc}')

try:
    password = getpass.getpass('Neues Web-Passwort (10-128 Zeichen): ')
    confirm = getpass.getpass('Passwort wiederholen: ')
except (EOFError, KeyboardInterrupt):
    raise SystemExit('\nAbgebrochen. Keine Änderungen.')

if password != confirm:
    raise SystemExit('Passwörter stimmen nicht überein. Keine Änderungen.')
if not 10 <= len(password) <= 128:
    raise SystemExit('Passwort muss 10 bis 128 Zeichen haben. Keine Änderungen.')

# Back up before modifying anything. The backup contains a password hash: protect it.
backup = path.with_name(path.name + '.bak-' + datetime.now().strftime('%Y%m%d-%H%M%S-%f'))
fd, temp_backup = tempfile.mkstemp(prefix='.security-backup-', dir=path.parent)
try:
    with os.fdopen(fd, 'wb') as dest, path.open('rb') as src:
        shutil.copyfileobj(src, dest)
        dest.flush()
        os.fsync(dest.fileno())
    os.chown(temp_backup, account.pw_uid, account.pw_gid)
    os.chmod(temp_backup, 0o600)
    os.replace(temp_backup, backup)
finally:
    if os.path.exists(temp_backup):
        os.unlink(temp_backup)

data['password_hash'] = generate_password_hash(password)
data['enabled'] = True
fd, temp = tempfile.mkstemp(prefix='.security-', suffix='.tmp', dir=path.parent)
try:
    with os.fdopen(fd, 'w', encoding='utf-8') as dest:
        json.dump(data, dest, ensure_ascii=False)
        dest.write('\n')
        dest.flush()
        os.fsync(dest.fileno())
    os.chown(temp, account.pw_uid, account.pw_gid)
    os.chmod(temp, 0o600)
    os.replace(temp, path)
finally:
    if os.path.exists(temp):
        os.unlink(temp)

print('Passwort erfolgreich zurückgesetzt. Benutzername: admin')
print(f'Sicherung: {backup}')
print('Dateiberechtigungen: lincledweb:lincledweb, 600')
print('Kein Neustart des Webservers erforderlich.')
PY
