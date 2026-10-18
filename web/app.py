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
