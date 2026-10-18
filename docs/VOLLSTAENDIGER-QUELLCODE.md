# Vollständiger Quellcode – kommentierter Dateikatalog

Dieses Dokument enthält die **unveränderten vollständigen Quelldateien** aus diesem Repository. Die ausführbaren Originale liegen in den jeweils angegebenen Pfaden. Änderungen bitte an den Originaldateien durchführen, nicht an den Codekopien in dieser Dokumentation.

## Aufbau und Zusammenspiel

- `web/app.py`: Flask-Webserver, Passwortschutz, JSON-API und Konfigurationsspeicherung.
- `web/templates/index.html`: Oberfläche, Darstellung, Styles und JavaScript zur API-Kommunikation.
- `controller/lincstation-led-control.sh`: SMART-/Netzwerkstatus, I²C-LEDs, RGB und Status-JSON.
- `install.sh`: Debian-/Ubuntu-Pakete, Dateien, Benutzer und systemd-Dienste.
- `enable-leds.sh`: explizite Prüfung und Freigabe der Hardware vor I²C-Schreibzugriffen.
- `uninstall.sh`: Deinstallationsroutine.

## Flask-Routen im Python-Code

| Route | Funktion |
|---|---|
| `GET /` | HTML-Oberfläche |
| `GET /api/state` | LED-/RGB-Status |
| `GET /api/security` | Passwortschutzstatus |
| `POST /api/security` | Passwort/Schutz ändern |
| `POST /api/rgb` | RGB-Einstellungen speichern |

**Hinweis:** Die Dokumentation ersetzt weder Codeprüfung noch Hardwaretests. Insbesondere I²C-Schreibzugriffe nur auf verifizierter LincStation-N1-Hardware freigeben.

## Python-Webserver
Originaldatei: `web/app.py`

```python
import json, os, secrets
from pathlib import Path
from flask import Flask, request, jsonify, render_template, Response
from werkzeug.security import check_password_hash, generate_password_hash

P=Path('/opt/lincstation-led-web'); C=P/'data/rgb.json'; S=Path('/run/lincstation-led/status.json')
SEC=P/'data/security.json'; OLD=P/'password.hash'
app=Flask(__name__)
app.config['MAX_CONTENT_LENGTH']=4096

def security():
    try:
        d=json.loads(SEC.read_text())
        if type(d.get('enabled')) is bool and isinstance(d.get('password_hash'),str): return d
    except (OSError,ValueError): pass
    try: h=OLD.read_text().strip()
    except OSError: h=''
    return {'enabled':bool(h),'password_hash':h}

def write_security(d):
    tmp=SEC.with_name('security.'+secrets.token_hex(8)+'.tmp')
    try:
        with open(tmp,'x') as f:
            json.dump(d,f);f.write('\n');f.flush();os.fsync(f.fileno())
        os.chmod(tmp,0o600);os.replace(tmp,SEC)
    finally: tmp.unlink(missing_ok=True)

def authenticated(d):
    a=request.authorization
    return bool(a and a.username=='admin' and d['password_hash'] and check_password_hash(d['password_hash'],a.password or ''))

@app.before_request
def auth():
    if request.method not in ('GET','HEAD','OPTIONS'):
        origin=request.headers.get('Origin')
        if origin:
            from urllib.parse import urlsplit
            o=urlsplit(origin)
            if o.scheme!=request.scheme or o.netloc!=request.host:
                return jsonify(error='Ungültige Herkunft der Anfrage'),403
    d=security()
    if d['enabled'] and not authenticated(d):
        return Response('Anmeldung erforderlich',401,{'WWW-Authenticate':'Basic realm="LincStation LED"'})

@app.get('/')
def index(): return render_template('index.html')

@app.get('/api/state')
def state():
    try: s=json.loads(S.read_text())
    except (OSError,ValueError): s={}
    try: c=json.loads(C.read_text())
    except (OSError,ValueError): c={'mode':'off','brightness':0,'color0':'#000000','color1':'#000000'}
    return jsonify(settings=c,status=s)

@app.get('/api/security')
def get_security():
    d=security()
    return jsonify(enabled=d['enabled'],has_password=bool(d['password_hash']))

@app.post('/api/security')
def set_security():
    d=security(); x=request.get_json(silent=True)
    if not isinstance(x,dict) or type(x.get('enabled')) is not bool:
        return jsonify(error='Ungültige Einstellung'),400
    enabled=x['enabled']; old=x.get('current_password',''); new=x.get('new_password','')
    if not isinstance(old,str) or not isinstance(new,str): return jsonify(error='Ungültiges Passwort'),400
    changing=(enabled!=d['enabled']) or bool(new)
    if not changing: return jsonify(ok=True,enabled=enabled)
    # Existing credentials are required to change/disable a protected account.
    if d['enabled'] and not check_password_hash(d['password_hash'],old):
        return jsonify(error='Aktuelles Passwort stimmt nicht'),403
    if enabled and not d['password_hash'] and not new:
        return jsonify(error='Bitte neues Passwort eingeben'),400
    if new:
        if not 10<=len(new)<=128: return jsonify(error='Passwort muss 10 bis 128 Zeichen haben'),400
        d['password_hash']=generate_password_hash(new)
    d['enabled']=enabled
    write_security(d)
    return jsonify(ok=True,enabled=enabled,message='Sicherheitseinstellung gespeichert')

@app.post('/api/rgb')
def save():
    d=request.get_json(silent=True)
    if not isinstance(d,dict): return jsonify(error='JSON fehlt'),400
    if d.get('mode') not in ('off','normal','breath','loop') or type(d.get('brightness'))!=int or not 0<=d['brightness']<=255: return jsonify(error='Modus/Helligkeit ungültig'),400
    for k in ('color0','color1'):
        v=d.get(k)
        if not isinstance(v,str) or len(v)!=7 or v[0]!='#' or any(x not in '0123456789abcdefABCDEF' for x in v[1:]): return jsonify(error='Farbe ungültig'),400
    clean={k:d[k] for k in ('mode','brightness','color0','color1')}
    tmp=C.with_name('rgb.'+secrets.token_hex(6)+'.tmp')
    try: tmp.write_text(json.dumps(clean)+'\n');os.replace(tmp,C)
    finally: tmp.unlink(missing_ok=True)
    return jsonify(ok=True,message='Gespeichert – Übernahme beim nächsten Timerlauf')
```

## HTML-Oberfläche mit CSS und JavaScript
Originaldatei: `web/templates/index.html`

```html
<!doctype html><html lang="de"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>LincStation LED</title>
<style>body{font:16px system-ui;background:#101827;color:#eef4ff;margin:0}main{max-width:850px;margin:40px auto;padding:0 20px}section{background:#1e2a3f;padding:22px;margin:18px 0;border-radius:18px}h1{margin-bottom:0}small,p{color:#b7c5d8}label{display:block;margin:16px 0 5px}.grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(210px,1fr));gap:14px}select,input[type=range],input[type=color]{width:100%}input[type=color]{height:48px}button{background:#4789f5;border:0;border-radius:10px;color:white;padding:13px 20px;font:inherit;cursor:pointer;margin-top:18px}.strip{height:45px;border-radius:12px;background:linear-gradient(90deg,var(--c0),var(--c1));margin:20px 0;box-shadow:0 0 20px #4678ad66}.device{background:#2a3b55;padding:12px;border-radius:10px;white-space:pre-wrap}.status{font-weight:bold}</style>
<main><h1>LincStation N1</h1><p>LED Control Center · RGB und SMART</p><section><h2>RGB-Leiste</h2><div id="strip" class="strip"></div><div class="grid"><div><label>Effekt</label><select id="mode"><option value="off">Aus</option><option value="normal">Dauerlicht</option><option value="breath">Atmen</option><option value="loop">Zweifarben-Lauflicht</option></select></div><div><label>Helligkeit: <span id="percent"></span></label><input id="brightness" type="range" min="0" max="255"></div><div><label>Farbe 1</label><input id="color0" type="color"></div><div><label>Farbe 2</label><input id="color1" type="color"></div></div><button id="save">Einstellungen speichern</button><p id="message">SMART-Warnfarben haben Vorrang.</p></section><section><h2>Überwachung: <span id="health" class="status">Warte …</span></h2><div class="grid" id="devices"></div></section><p>Gelbes Atmen: Warnung · Rotes Atmen: kritischer SMART-Fehler. Kleine LEDs bleiben unabhängig.</p><section><h2>🔒 Sicherheit</h2><label><input id="authEnabled" type="checkbox"> Passwortschutz verwenden</label><p>Bei aktiviertem Schutz benötigst du das bisherige Passwort, um ihn zu ändern oder auszuschalten.</p><div class="grid"><div><label>Aktuelles Passwort</label><input id="currentPassword" type="password" autocomplete="current-password" placeholder="Bei Änderungen mit Schutz"></div><div><label>Neues Passwort (mind. 10 Zeichen)</label><input id="newPassword" type="password" autocomplete="new-password" placeholder="Leer lassen, um es beizubehalten"></div></div><button id="saveSecurity">Sicherheit speichern</button><p id="securityMessage">Lade Sicherheitseinstellungen …</p><small>Ohne Passwortschutz kann jeder mit Zugriff auf die Weboberfläche die LED-Einstellungen verändern. Nach einem Passwortwechsel kann der Browser erneut nach Zugangsdaten fragen.</small></section></main>
<script>const el=x=>document.getElementById(x);let dirty=false;function preview(){el('strip').style.setProperty('--c0',el('color0').value);el('strip').style.setProperty('--c1',el('color1').value);el('strip').style.opacity=el('mode').value==='off'?.1:Math.max(.15,+el('brightness').value/255);el('percent').textContent=Math.round(+el('brightness').value/255*100)+' %'}for(const k of ['mode','brightness','color0','color1'])el(k).addEventListener('input',()=>{dirty=true;preview()});async function refresh(){try{let r=await fetch('/api/state');let d=await r.json();if(!dirty){for(let k of ['mode','brightness','color0','color1'])el(k).value=d.settings[k];preview()}el('health').textContent=({ok:'Normal',warning:'Warnung',critical:'Kritisch'})[d.status.severity]||'Unbekannt';el('devices').replaceChildren();for(const [k,v] of Object.entries(d.status.devices||{})){let n=document.createElement('div');n.className='device';n.textContent=k+' · '+v.state+'\n'+v.reason;el('devices').append(n)}}catch(e){el('message').textContent='Statusfehler: '+e.message}}el('save').onclick=async()=>{try{let d={};for(let k of ['mode','brightness','color0','color1'])d[k]=el(k).value;d.brightness=+d.brightness;let r=await fetch('/api/rgb',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify(d)});let x=await r.json();if(!r.ok)throw Error(x.error);dirty=false;el('message').textContent=x.message}catch(e){el('message').textContent=e.message}};refresh();setInterval(refresh,10000)
let initialEnabled=true;
async function loadSecurity(){try{let r=await fetch('/api/security');if(!r.ok)throw Error('HTTP '+r.status);let d=await r.json();initialEnabled=d.enabled;el('authEnabled').checked=d.enabled;el('securityMessage').textContent=d.enabled?'Passwortschutz ist aktiviert.':'Passwortschutz ist deaktiviert.'}catch(e){el('securityMessage').textContent='Fehler: '+e.message}}
el('saveSecurity').onclick=async()=>{let enabled=el('authEnabled').checked;let current_password=el('currentPassword').value;let new_password=el('newPassword').value;if(enabled&&!initialEnabled&&!new_password){el('securityMessage').textContent='Bitte ein neues Passwort eingeben.';return}try{let r=await fetch('/api/security',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({enabled,current_password,new_password})});let x=await r.json();if(!r.ok)throw Error(x.error||'Fehler');el('currentPassword').value='';el('newPassword').value='';initialEnabled=enabled;el('securityMessage').textContent='Gespeichert. Bei Passwortänderung Seite neu laden.'}catch(e){el('securityMessage').textContent=e.message}};
loadSecurity();</script></html>
```

## Bash-Controller
Originaldatei: `controller/lincstation-led-control.sh`

```bash
#!/usr/bin/env bash
set -uo pipefail

# LincStation N1 - automatische LED-Steuerung
# Standard: Dry-Run (keine I2C-Schreibzugriffe)
# Echtbetrieb: bash /root/lincstation-led-control.sh --apply

BUS=0
ADDR=0x26
MODE="${1:---dry-run}"

if [[ "$MODE" != "--dry-run" && "$MODE" != "--apply" ]]; then
    echo "Verwendung: $0 [--dry-run|--apply]"
    exit 2
fi

for tool in smartctl jq lsblk readlink; do
    if ! command -v "$tool" >/dev/null 2>&1; then
        echo "FEHLER: $tool fehlt"
        exit 1
    fi
done

if [[ "$MODE" == "--apply" ]]; then
    if [[ "$EUID" -ne 0 ]]; then
        echo "FEHLER: Echtbetrieb benötigt root"
        exit 1
    fi
    if ! command -v i2cset >/dev/null 2>&1; then
        echo "FEHLER: i2cset fehlt"
        exit 1
    fi
fi

declare -A STATE REASON
SLOTS=(SATA0 SATA1 NVMe0 NVMe1 NVMe2 NVMe3 NETZWERK)

# Format:
# Weiss-EIN Register/Bit, Weiss-AUS Register/Bit,
# Rot-EIN Register/Bit, Rot-AUS Register/Bit,
# Weiss-Blinkregister, Rot-Blinkregister
declare -A MAP=(
    [SATA0]="A0:04:B0:04:A0:08:B0:08:52:53"
    [SATA1]="A0:10:B0:10:A0:20:B0:20:54:55"
    [NVMe0]="A1:01:B1:01:A1:02:B1:02:58:59"
    [NVMe1]="A1:04:B1:04:A1:08:B1:08:5A:5B"
    [NVMe2]="A1:10:B1:10:A1:20:B1:20:5C:5D"
    [NVMe3]="A1:40:B1:40:A1:80:B1:80:5E:5F"
    [NETZWERK]="A0:40:B0:40:A0:80:B0:80:56:57"
)

set_state() {
    STATE["$1"]="$2"
    REASON["$1"]="$3"
}

# I2C nur bei ausdruecklichem --apply ausfuehren.
write_i2c() {
    local reg="$1"
    local value="$2"

    if [[ "$MODE" == "--dry-run" ]]; then
        printf '  [TEST] i2cset -y %s %s 0x%s 0x%s\n' \
            "$BUS" "$ADDR" "$reg" "$value"
    else
        i2cset -y "$BUS" "$ADDR" "0x$reg" "0x$value" || return 1
    fi
}

# NVMe-SMART pruefen.
check_nvme() {
    local slot="$1"
    local path="$2"
    local dev json warning spare threshold used errors temp
    local smart_exit

    if [[ ! -b "$path" ]]; then
        set_state "$slot" AUS "Kein Laufwerk am PCIe-Pfad"
        return
    fi

    dev=$(readlink -f "$path")

    json=$(smartctl -j -A "$dev" 2>/dev/null)
    smart_exit=$?

    if ! jq -e '.nvme_smart_health_information_log' \
        >/dev/null 2>&1 <<< "$json"; then
        set_state "$slot" UNBEKANNT "SMART nicht lesbar: $dev"
        return
    fi

    warning=$(jq -r '.nvme_smart_health_information_log.critical_warning // empty' <<< "$json")
    spare=$(jq -r '.nvme_smart_health_information_log.available_spare // empty' <<< "$json")
    threshold=$(jq -r '.nvme_smart_health_information_log.available_spare_threshold // empty' <<< "$json")
    used=$(jq -r '.nvme_smart_health_information_log.percentage_used // empty' <<< "$json")
    errors=$(jq -r '.nvme_smart_health_information_log.media_errors // empty' <<< "$json")
    temp=$(jq -r '.temperature.current // empty' <<< "$json")

    local value
    for value in "$warning" "$spare" "$threshold" "$used" "$errors" "$temp"; do
        if [[ ! "$value" =~ ^[0-9]+$ ]]; then
            set_state "$slot" UNBEKANNT "SMART-Daten unvollstaendig: $dev"
            return
        fi
    done

    local info="$dev: ${temp}C, Reserve ${spare}%, Verschleiss ${used}%, Fehler ${errors}, Warnung ${warning}"

    if (( warning != 0 || errors > 0 )); then
        set_state "$slot" ROT "$info"
    elif (( spare <= threshold || used >= 90 || temp >= 70 )); then
        set_state "$slot" ROT_BLINKEND "$info"
    elif (( smart_exit & 0x03 )); then
        set_state "$slot" UNBEKANNT "SMART-Befehlsfehler: $dev"
    else
        set_state "$slot" WEISS "$info"
    fi
}

# SATA- und NVMe-Bestand pruefen.
# Unbestaetigte Slot-Zuordnungen werden nicht geraten.
check_other_slots() {
    local nvme_count sata_count
    nvme_count=$(lsblk -dn -o NAME,TYPE |
        awk '$2=="disk" && $1 ~ /^nvme[0-9]+n[0-9]+$/ {n++} END {print n+0}')

    sata_count=$(lsblk -dn -o NAME,TRAN,TYPE |
        awk '$3=="disk" && $2=="sata" {n++} END {print n+0}')

    if (( nvme_count == 2 )) &&
       [[ -b /dev/disk/by-path/pci-0000:05:00.0-nvme-1 ]] &&
       [[ -b /dev/disk/by-path/pci-0000:04:00.0-nvme-1 ]]; then
        set_state NVMe2 AUS "Keine weiteren NVMe-Laufwerke erkannt"
        set_state NVMe3 AUS "Keine weiteren NVMe-Laufwerke erkannt"
    else
        set_state NVMe2 UNBEKANNT "Weitere NVMe oder unklare Zuordnung"
        set_state NVMe3 UNBEKANNT "Weitere NVMe oder unklare Zuordnung"
    fi

    if (( sata_count == 0 )); then
        set_state SATA0 AUS "Kein SATA-Laufwerk erkannt"
        set_state SATA1 AUS "Kein SATA-Laufwerk erkannt"
    else
        set_state SATA0 UNBEKANNT "SATA-Slot-Zuordnung noch offen"
        set_state SATA1 UNBEKANNT "SATA-Slot-Zuordnung noch offen"
    fi
}

# Physische Netzwerkkarte anhand der PCI-Adresse suchen.
check_network() {
    local iface device carrier net_if=""
    for iface in /sys/class/net/*; do
        device=$(readlink -f "$iface/device" 2>/dev/null || true)
        if [[ "$device" == */0000:01:00.0 ]]; then
            net_if=$(basename "$iface")
            break
        fi
    done

    if [[ -z "$net_if" || ! -r "/sys/class/net/$net_if/carrier" ]]; then
        set_state NETZWERK UNBEKANNT "Netzwerkstatus nicht lesbar"
        return
    fi

    carrier=$(cat "/sys/class/net/$net_if/carrier")

    case "$carrier" in
        1) set_state NETZWERK WEISS "$net_if verbunden" ;;
        0) set_state NETZWERK ROT "$net_if getrennt" ;;
        *) set_state NETZWERK UNBEKANNT "Unbekannter Carrier-Status" ;;
    esac
}

# LED-Zustand in I2C-Befehle umsetzen.
control_led_raw() {
    local slot="$1"
    local state="${STATE[$slot]:-UNBEKANNT}"
    local won_reg won_bit woff_reg woff_bit
    local ron_reg ron_bit roff_reg roff_bit
    local wb rb

    IFS=: read -r \
        won_reg won_bit woff_reg woff_bit \
        ron_reg ron_bit roff_reg roff_bit \
        wb rb <<< "${MAP[$slot]}"

    echo
    echo "[$slot] $state"
    echo "  ${REASON[$slot]:-Keine Information}"

    case "$state" in
        WEISS)
            write_i2c "$rb" 00 || return 1
            write_i2c "$wb" 00 || return 1
            write_i2c "$roff_reg" "$roff_bit" || return 1
            write_i2c "$won_reg" "$won_bit" || return 1
            ;;
        ROT)
            write_i2c "$wb" 00 || return 1
            write_i2c "$rb" 00 || return 1
            write_i2c "$woff_reg" "$woff_bit" || return 1
            write_i2c "$ron_reg" "$ron_bit" || return 1
            ;;
        ROT_BLINKEND)
            write_i2c "$wb" 00 || return 1
            write_i2c "$woff_reg" "$woff_bit" || return 1
            write_i2c "$ron_reg" "$ron_bit" || return 1
            write_i2c "$rb" 01 || return 1
            ;;
        AUS)
            write_i2c "$wb" 00 || return 1
            write_i2c "$rb" 00 || return 1
            write_i2c "$woff_reg" "$woff_bit" || return 1
            write_i2c "$roff_reg" "$roff_bit" || return 1
            ;;
        UNBEKANNT)
            echo "  Keine Schaltung bei unklarer Zuordnung"
            ;;
    esac
}


# LINCSTATION_RGB_EXTENSION_V1
RUNDIR=/run/lincstation-led
if [[ "$MODE" == "--dry-run" ]]; then
    RUNDIR=$(mktemp -d)
    trap 'rm -rf "$RUNDIR"' EXIT
else
    mkdir -p "$RUNDIR"
    chmod 755 "$RUNDIR"
    exec 9>"$RUNDIR/lock"
    flock -n 9 || exit 0
fi

# Freigabe bindet den Bus an den nachgewiesenen PCI-Controller.
# Nur sysfs-Metadaten lesen, keine automatischen I2C-Scans.
verify_led_bus() {
    local config=/etc/lincstation-led.conf bus pci expected_pci expected_id
    local adapter expected_adapter device_path actual_id
    [[ -r "$config" ]] || { echo "FEHLER: Busfreigabe fehlt: $config" >&2; return 1; }
    bus=$(sed -n 's/^LED_BUS=//p' "$config" | tail -1)
    expected_pci=$(sed -n 's/^LED_PCI=//p' "$config" | tail -1)
    expected_id=$(sed -n 's/^LED_PCI_ID=//p' "$config" | tail -1)
    expected_adapter=$(sed -n 's/^LED_ADAPTER_NAME=//p' "$config" | tail -1)
    [[ "$bus" =~ ^[0-9]+$ && "$expected_pci" == '0000:00:15.0' && "$expected_id" == '8086:4de8' && -n "$expected_adapter" ]] || {
        echo 'FEHLER: Unbekannte oder unvollständige Hardwarefreigabe' >&2; return 1;
    }
    [[ -c "/dev/i2c-$bus" && -r "/sys/class/i2c-dev/i2c-$bus/name" ]] || {
        echo 'FEHLER: Freigegebener I2C-Bus fehlt' >&2; return 1;
    }
    adapter=$(cat "/sys/class/i2c-dev/i2c-$bus/name")
    [[ "$adapter" == "$expected_adapter" ]] || { echo 'FEHLER: Adaptername weicht ab' >&2; return 1; }
    device_path=$(readlink -f "/sys/class/i2c-dev/i2c-$bus") || return 1
    [[ "$device_path" == *"/$expected_pci/i2c_designware."*"/i2c-$bus/i2c-dev/i2c-$bus" ]] || {
        echo 'FEHLER: I2C-Bus gehört nicht zum freigegebenen PCI-/DesignWare-Pfad' >&2; return 1;
    }
    [[ -r "/sys/bus/pci/devices/$expected_pci/vendor" && -r "/sys/bus/pci/devices/$expected_pci/device" ]] || return 1
    actual_id="$(cat "/sys/bus/pci/devices/$expected_pci/vendor"):$(cat "/sys/bus/pci/devices/$expected_pci/device")"
    [[ "$actual_id" == '0x8086:0x4de8' ]] || { echo "FEHLER: PCI-ID $actual_id unerwartet" >&2; return 1; }
    BUS="$bus"
}
if [[ "$MODE" == "--apply" ]]; then
    verify_led_bus || exit 1
fi

control_led() {
    local slot="$1" state="${STATE[$1]:-UNBEKANNT}" key
    # Kleine LEDs bei jeder SMART-Störung dauerhaft rot, niemals blinkend.
    [[ "$state" == ROT_BLINKEND ]] && state=ROT
    [[ "$state" == UNBEKANNT ]] && { control_led_raw "$slot"; return; }
    key="$RUNDIR/led-$slot"
    if [[ "$MODE" == "--apply" && -r "$key" && "$(cat "$key")" == "$state" ]]; then
        echo "[$slot] $state – unverändert, kein I2C-Schreiben"
        return 0
    fi
    local old="${STATE[$slot]}"
    STATE[$slot]="$state"
    if ! control_led_raw "$slot"; then
        rm -f "$key"
        echo "FEHLER: I2C-Schreiben bei $slot" >&2
        STATE[$slot]="$old"
        return 1
    fi
    STATE[$slot]="$old"
    [[ "$MODE" == "--apply" ]] && printf '%s\n' "$state" > "$key"
}

rgb_control() {
    local cfg=/opt/lincstation-led-web/data/rgb.json
    local mode brightness color0 color1 severity=ok desired hash old
    local reg hex rgb i
    # Warnstufe nur aus den beiden bekannten NVMe-SMART-Ergebnissen ableiten.
    for i in NVMe0 NVMe1; do
        case "${STATE[$i]:-UNBEKANNT}" in
            ROT) severity=critical ;;
            ROT_BLINKEND|UNBEKANNT) [[ "$severity" != critical ]] && severity=warning ;;
        esac
    done
    RGB_SEVERITY="$severity"
    [[ -r "$cfg" ]] || { echo 'RGB-Konfiguration fehlt' >&2; return 1; }
    mode=$(jq -r '.mode' "$cfg")
    brightness=$(jq -r '.brightness' "$cfg")
    color0=$(jq -r '.color0' "$cfg")
    color1=$(jq -r '.color1' "$cfg")
    [[ "$mode" =~ ^(off|normal|breath|loop)$ && "$brightness" =~ ^[0-9]+$ ]] || return 1
    (( brightness <= 255 )) || return 1
    [[ "$color0" =~ ^#[0-9a-fA-F]{6}$ && "$color1" =~ ^#[0-9a-fA-F]{6}$ ]] || return 1
    if [[ "$severity" == critical ]]; then
        mode=breath; brightness=255; color0='#ff0000'; color1='#ff0000'
    elif [[ "$severity" == warning ]]; then
        mode=breath; brightness=255; color0='#ffff00'; color1='#ffff00'
    fi
    desired="$mode:$brightness:$color0:$color1"
    hash=$(printf '%s' "$desired" | sha256sum | cut -d' ' -f1)
    if [[ "$MODE" == "--apply" && -r "$RUNDIR/rgb-state" && "$(cat "$RUNDIR/rgb-state")" == "$hash" ]]; then
        echo "[RGB] $severity – unverändert, kein I2C-Schreiben"
        return 0
    fi
    echo "[RGB] $severity – Modus $mode"
    [[ "$MODE" == "--dry-run" ]] && return 0
    # Bei Aus: Helligkeit 0 und schwarze Farbe (kein unbekannter Moduswert).
    [[ "$mode" == off ]] && { mode=normal; brightness=0; color0='#000000'; color1='#000000'; }
    local modebyte=00
    [[ "$mode" == breath ]] && modebyte=01
    [[ "$mode" == loop ]] && modebyte=02
    write_i2c 91 "$(printf '%02X' "$brightness")" || { rm -f "$RUNDIR/rgb-state"; return 1; }
    for i in 0 1; do
        if (( i == 0 )); then rgb=${color0#\#}; reg=0x95; else rgb=${color1#\#}; reg=0x98; fi
        for hex in "${rgb:0:2}" "${rgb:2:2}" "${rgb:4:2}"; do
            write_i2c "$(printf '%02X' "$reg")" "${hex^^}" || { rm -f "$RUNDIR/rgb-state"; return 1; }
            ((reg++))
        done
    done
    # Hersteller: normal/breath lesen die Register 92-94, loop die 95-9A.
    rgb=${color0#\#}; reg=0x92
    for hex in "${rgb:0:2}" "${rgb:2:2}" "${rgb:4:2}"; do
        write_i2c "$(printf '%02X' "$reg")" "${hex^^}" || { rm -f "$RUNDIR/rgb-state"; return 1; }
        ((reg++))
    done
    write_i2c 90 "$modebyte" || { rm -f "$RUNDIR/rgb-state"; return 1; }
    printf '%s\n' "$hash" > "$RUNDIR/rgb-state"
}

publish_status() {
    local tmp="$RUNDIR/status.tmp.$$" slot
    local args=(--arg severity "${RGB_SEVERITY:-unknown}")
    local data='{}'
    for slot in "${SLOTS[@]}"; do
        data=$(jq -cn --argjson old "$data" --arg name "$slot" --arg state "${STATE[$slot]:-UNBEKANNT}" --arg reason "${REASON[$slot]:-}" '$old + {($name):{state:$state,reason:$reason}}')
    done
    jq -n --arg severity "${RGB_SEVERITY:-unknown}" --argjson devices "$data" '{severity:$severity,devices:$devices}' > "$tmp"
    chmod 644 "$tmp"
    mv "$tmp" "$RUNDIR/status.json"
}

echo "=============================================="
echo " LincStation N1 - automatische LED-Steuerung"
echo " Modus: $MODE"
echo "=============================================="

check_nvme NVMe0 "/dev/disk/by-path/pci-0000:05:00.0-nvme-1"
check_nvme NVMe1 "/dev/disk/by-path/pci-0000:04:00.0-nvme-1"
check_other_slots
check_network

for slot in "${SLOTS[@]}"; do
    control_led "$slot" || exit 1
done
rgb_control || exit 1
[[ "$MODE" == "--apply" ]] && publish_status

echo
echo "=============================================="
echo " Fertig - Modus: $MODE"
echo "=============================================="
```

## Installationsskript
Originaldatei: `install.sh`

```bash
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
```

## Hardwarefreigabe
Originaldatei: `enable-leds.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Bitte mit sudo/root ausführen'; exit 1; }
[[ -x /usr/local/sbin/lincstation-led-control.sh ]] || { echo 'Zuerst install.sh ausführen'; exit 1; }
[[ ! -e /etc/lincstation-led.conf ]] || { echo 'Bereits freigegeben. Keine automatische Überschreibung.'; exit 1; }
echo 'Verfügbare I2C-Adapter (ohne Adressscan):'
i2cdetect -l
read -r -p 'Bestätigte Busnummer (auf untersuchter N1: 0): ' bus
[[ "$bus" =~ ^[0-9]+$ ]] || { echo 'Ungültige Busnummer'; exit 1; }
[[ -c "/dev/i2c-$bus" && -r "/sys/class/i2c-dev/i2c-$bus/name" ]] || { echo 'Bus nicht vorhanden'; exit 1; }
name=$(cat "/sys/class/i2c-dev/i2c-$bus/name")
path=$(readlink -f "/sys/class/i2c-dev/i2c-$bus")
pci='0000:00:15.0'
[[ "$path" == *"/$pci/i2c_designware."*"/i2c-$bus/i2c-dev/i2c-$bus" ]] || {
    echo "ABBRUCH: Bus gehört nicht zum erwarteten PCI-/DesignWare-Controller: $path"; exit 1;
}
[[ -r "/sys/bus/pci/devices/$pci/vendor" && -r "/sys/bus/pci/devices/$pci/device" ]] || exit 1
vendor=$(cat "/sys/bus/pci/devices/$pci/vendor")
device=$(cat "/sys/bus/pci/devices/$pci/device")
[[ "$vendor:$device" == '0x8086:0x4de8' ]] || { echo "ABBRUCH: PCI-ID $vendor:$device unerwartet"; exit 1; }
printf '\nHardwareprüfung (nur lesend):\n  Bus: i2c-%s\n  Adapter: %s\n  sysfs: %s\n  PCI: %s (%s:%s)\n' "$bus" "$name" "$path" "$pci" "$vendor" "$device"
echo 'WARNUNG: Der Hardwarepfad identifiziert den HOST-Adapter, nicht das Gerät 0x26.'
echo 'Nur freigeben, wenn du eine LincStation N1 mit bekannter LED-Controller-Zuordnung hast.'
echo 'Falsche I2C-Schreibzugriffe können andere Geräte stören oder beschädigen.'
read -r -p 'N1, Controlleradresse 0x26 und Buszuordnung unabhängig bestätigt? Tippe JA: ' answer
[[ "$answer" == JA ]] || { echo 'Ohne Freigabe beendet'; exit 1; }
printf 'LED_BUS=%s\nLED_ADAPTER_NAME=%s\nLED_PCI=%s\nLED_PCI_ID=8086:4de8\n' "$bus" "$name" "$pci" > /etc/lincstation-led.conf
chmod 600 /etc/lincstation-led.conf
systemctl enable --now lincstation-led-control.timer
echo 'LED-Timer aktiviert; erste Ausführung nach ca. 30 Sekunden.'
```

## Deinstallation
Originaldatei: `uninstall.sh`

```bash
#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exit 1
systemctl disable --now lincstation-led-control.timer lincstation-led-web.service 2>/dev/null || true
rm -f /etc/systemd/system/lincstation-led-control.{timer,service} /etc/systemd/system/lincstation-led-web.service
systemctl daemon-reload
printf 'Dienste entfernt. Konfiguration, Programmdateien und Passwörter bleiben zur Sicherung erhalten.\n'
```

