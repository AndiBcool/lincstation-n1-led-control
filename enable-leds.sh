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
