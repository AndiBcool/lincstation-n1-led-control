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
