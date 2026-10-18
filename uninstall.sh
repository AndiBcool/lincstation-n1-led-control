#!/usr/bin/env bash
set -euo pipefail
[[ $EUID -eq 0 ]] || exit 1
systemctl disable --now lincstation-led-control.timer lincstation-led-web.service 2>/dev/null || true
rm -f /etc/systemd/system/lincstation-led-control.{timer,service} /etc/systemd/system/lincstation-led-web.service
systemctl daemon-reload
printf 'Dienste entfernt. Konfiguration, Programmdateien und Passwörter bleiben zur Sicherung erhalten.\n'
