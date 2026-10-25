#!/usr/bin/env sh
# Values Conky cannot discover portably on its own. Called by the Conky
# templates (relative to the project root) and by `mainte run` for detection.
# Missing hardware is reported as N/A instead of failing.

DISPLAY_LOCALE=${LC_ALL:-${LANG:-${LC_CTYPE:-}}}
LC_ALL=C
export LC_ALL

SYSFS_ROOT=${MAINTE_SYSFS_ROOT:-/sys}
PROC_ROOT=${MAINTE_PROC_ROOT:-/proc}
POWER_SUPPLY_ROOT=$SYSFS_ROOT/class/power_supply
HWMON_ROOT=$SYSFS_ROOT/class/hwmon
NET_ROOT=$SYSFS_ROOT/class/net

print_na() {
    printf '%s\n' 'N/A'
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

# clean_value [WIDTH]: squeeze whitespace, drop (R)/(TM), cut to WIDTH characters.
clean_value() {
    sed -e 's/[[:space:]][[:space:]]*/ /g' \
        -e 's/^ *//; s/ *$//' \
        -e 's/ *(R)//g; s/ *(TM)//g' | cut -c "1-${1:-48}"
}

print_value() { # print_value VALUE [WIDTH]
    if [ -n "$1" ]; then
        printf '%s\n' "$1" | clean_value "${2:-48}"
    else
        print_na
    fi
}

first_line() {
    sed -n '1p' "$1" 2>/dev/null | tr -d '[:space:]'
}

distro() {
    value=''
    if has_command lsb_release; then
        value=$(lsb_release -ds 2>/dev/null | sed 's/^"//; s/"$//')
    fi
    if [ -z "$value" ] && [ -r /etc/os-release ]; then
        value=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/^"|"$/, "", $2); print $2; exit }' /etc/os-release)
    fi
    if [ -z "$value" ]; then
        value=$(uname -s 2>/dev/null)
    fi
    print_value "$value"
}

gpu() {
    value=''
    if has_command lspci; then
        value=$(lspci 2>/dev/null | awk -F': ' \
            '/(VGA compatible controller|3D controller|Display controller)/ { print $2; exit }')
    fi
    if [ -z "$value" ] && has_command glxinfo; then
        value=$(glxinfo -B 2>/dev/null | awk -F': ' '/Device:/ { print $2; exit }')
    fi
    print_value "$value"
}

resolution() {
    value=''
    if has_command xdpyinfo; then
        value=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ { print $2; exit }')
    fi
    if [ -z "$value" ] && has_command xrandr; then
        value=$(xrandr 2>/dev/null | awk '$2 == "connected" {
            for (i = 3; i <= NF; i++) if ($i ~ /^[0-9]+x[0-9]+[+-]/) { sub(/[+-].*$/, "", $i); print $i; exit }
        }')
    fi
    if [ -z "$value" ] && has_command wlr-randr; then
        value=$(wlr-randr 2>/dev/null | awk '/current/ { print $1; exit }')
    fi
    print_value "$value"
}

locale_name() {
    value=$DISPLAY_LOCALE
    if [ -z "$value" ] && [ -r /etc/locale.conf ]; then
        value=$(awk -F= '$1 == "LANG" { gsub(/^"|"$/, "", $2); print $2; exit }' /etc/locale.conf)
    fi
    print_value "$value"
}

cpu_model() {
    value=''
    if [ -r "$PROC_ROOT/cpuinfo" ]; then
        value=$(awk -F: '/^(model name|Processor|Hardware)[[:space:]]*:/ {
            gsub(/^[[:space:]]+/, "", $2); print $2; exit
        }' "$PROC_ROOT/cpuinfo")
    fi
    if [ -z "$value" ] || [ "$value" = unknown ]; then
        value=$(uname -m 2>/dev/null)
    fi
    # The original layout reserves 36 characters for the CPU model.
    print_value "$(printf '%s\n' "$value" | sed 's/ CPU / /; s/ CPU$//')" 36
}

fan_speed() {
    if has_command sensors; then
        value=$(sensors 2>/dev/null | awk '
            /[Rr][Pp][Mm]/ {
                for (i = 1; i < NF; i++) {
                    if ($i ~ /^[0-9]+([.][0-9]+)?$/ && tolower($(i + 1)) == "rpm") {
                        printf "%.0f\n", $i
                        exit
                    }
                }
            }')
        if [ -n "$value" ]; then
            printf '%s RPM\n' "$value"
            return
        fi
    fi

    for file in "$HWMON_ROOT"/*/fan*_input; do
        value=$(first_line "$file")
        case $value in
            ''|*[!0-9]*) continue ;;
        esac
        printf '%s RPM\n' "$value"
        return
    done

    # NoteBook FanControl reports duty cycle on laptops whose EC hides the RPM.
    if has_command nbfc; then
        value=$(nbfc status -a 2>/dev/null | awk -F: '
            tolower($1) ~ /current fan speed/ { gsub(/[[:space:]]/, "", $2); printf "%.0f\n", $2; exit }
        ')
        if [ -n "$value" ]; then
            printf '%s %%\n' "$value"
            return
        fi
    fi
    print_na
}

# Raw hwmon readings (millidegrees), CPU drivers first.
hwmon_temperatures() {
    for dir in "$HWMON_ROOT"/*; do
        case $(first_line "$dir/name") in
            coretemp|k10temp|zenpower|cpu_thermal) printf '0 %s\n' "$dir" ;;
            *) printf '1 %s\n' "$dir" ;;
        esac
    done | sort -k1,1n -k2 | while read -r _ dir; do
        for file in "$dir"/temp*_input; do
            first_line "$file"
            printf '\n'
        done
    done
}

# CPU sensors (Intel coretemp, AMD k10temp/zenpower, ARM cpu_thermal) come
# first so "Temp 1" and "Temp 2" show the CPU whenever the system exposes it.
temperature() { # temperature INDEX
    wanted=$1
    case $wanted in
        ''|*[!0-9]*|0) print_na; return ;;
    esac

    value=''
    if has_command sensors; then
        value=$(sensors 2>/dev/null | awk -v wanted="$wanted" '
            /:/ {
                label = $0
                sub(/:.*/, "", label)
                for (i = 2; i <= NF; i++) {
                    reading = $i
                    if (reading ~ /^[+-]?[0-9]+([.][0-9]+)?°C$/) sub(/°C$/, "", reading)
                    else if (!(reading ~ /^[+-]?[0-9]+([.][0-9]+)?$/ && $(i + 1) == "C")) continue
                    sub(/^[+]/, "", reading)
                    if (label ~ /^(Core|Package|Tctl|Tdie|Tccd|CPU)/) cpu[++cpu_count] = reading
                    else other[++other_count] = reading
                    break
                }
            }
            END {
                for (i = 1; i <= other_count; i++) cpu[++cpu_count] = other[i]
                if (wanted <= cpu_count) printf "%.0f\n", cpu[wanted]
            }')
    fi

    if [ -z "$value" ]; then
        value=$(hwmon_temperatures | awk -v wanted="$wanted" '
            /^-?[0-9]+$/ && ++count == wanted { printf "%.0f\n", $1 / 1000; exit }
        ')
    fi

    if [ -n "$value" ]; then
        printf '%s °C\n' "$value"
    else
        print_na
    fi
}

# Interface of the default route with the lowest metric, else the first
# interface that is up, else the first non-loopback interface.
net_iface() {
    if [ -r "$PROC_ROOT/net/route" ]; then
        value=$(awk 'NR > 1 && $2 == "00000000" && $8 == "00000000" {
            if (best == "" || $7 + 0 < metric) { best = $1; metric = $7 + 0 }
        } END { if (best != "") print best }' "$PROC_ROOT/net/route")
        if [ -n "$value" ]; then
            printf '%s\n' "$value"
            return
        fi
    fi

    fallback=''
    for dir in "$NET_ROOT"/*; do
        name=${dir##*/}
        [ -e "$dir" ] && [ "$name" != lo ] || continue
        if [ "$(first_line "$dir/operstate")" = up ]; then
            printf '%s\n' "$name"
            return
        fi
        [ -n "$fallback" ] || fallback=$name
    done
    [ -z "$fallback" ] || printf '%s\n' "$fallback"
}

# "<ssid> : SSID" for Wi-Fi, "<iface> : LAN" otherwise.
network() { # network IFACE
    iface=$1
    if [ -z "$iface" ] || [ ! -e "$NET_ROOT/$iface" ]; then
        print_na
        return
    fi
    if [ ! -d "$NET_ROOT/$iface/wireless" ] && [ ! -e "$NET_ROOT/$iface/phy80211" ]; then
        printf '%s : LAN\n' "$iface"
        return
    fi

    ssid=''
    if has_command iwgetid; then
        ssid=$(iwgetid "$iface" --raw 2>/dev/null)
    fi
    if [ -z "$ssid" ] && has_command nmcli; then
        ssid=$(nmcli -t -f GENERAL.CONNECTION device show "$iface" 2>/dev/null | sed -n 's/^GENERAL.CONNECTION://p')
    fi
    if [ -z "$ssid" ] && has_command iw; then
        ssid=$(iw dev "$iface" link 2>/dev/null | sed -n 's/^[[:space:]]*SSID: //p')
    fi
    printf '%s : SSID\n' "$(print_value "$ssid" 24)"
}

# First system battery (BAT* preferred); peripheral batteries are skipped.
battery_name() {
    for dir in "$POWER_SUPPLY_ROOT"/BAT* "$POWER_SUPPLY_ROOT"/*; do
        [ -r "$dir/capacity" ] || continue
        [ "$(first_line "$dir/type")" = Battery ] || continue
        [ "$(first_line "$dir/scope")" != Device ] || continue
        printf '%s\n' "${dir##*/}"
        return
    done
}

case ${1:-help} in
    distro) distro ;;
    gpu) gpu ;;
    resolution) resolution ;;
    locale) locale_name ;;
    cpu) cpu_model ;;
    fan) fan_speed ;;
    temperature) temperature "${2:-1}" ;;
    network) network "${2:-}" ;;
    net-iface) net_iface ;;
    battery-name) battery_name ;;
    help|-h|--help)
        printf '%s\n' 'Usage: providers/sysinfo.sh {distro|gpu|resolution|locale|cpu|fan|temperature [N]|network IFACE|net-iface|battery-name}'
        ;;
    *) print_na ;;
esac
