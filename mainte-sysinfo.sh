#!/usr/bin/env sh
# Small, dependency-light adapters for values that Conky cannot discover
# portably on its own. Missing hardware is reported as N/A.

DISPLAY_LOCALE=${LC_ALL:-${LANG:-${LC_CTYPE:-}}}
LC_ALL=C
export LC_ALL

SYSFS_ROOT=${MAINTE_SYSFS_ROOT:-/sys}
POWER_SUPPLY_ROOT="$SYSFS_ROOT/class/power_supply"
HWMON_ROOT="$SYSFS_ROOT/class/hwmon"

print_na() {
    printf '%s\n' 'N/A'
}

clean_value() {
    sed -e 's/[[:space:]][[:space:]]*/ /g' \
        -e 's/^ *//; s/ *$//' \
        -e 's/ (R)//g; s/ (TM)//g' | cut -c 1-48
}

distro() {
    value=''

    if command -v lsb_release >/dev/null 2>&1; then
        value=$(lsb_release -ds 2>/dev/null || :)
        value=$(printf '%s\n' "$value" | sed 's/^"//; s/"$//')
    fi

    if [ -z "$value" ] && [ -r /etc/os-release ]; then
        value=$(awk -F= '$1 == "PRETTY_NAME" { gsub(/^"|"$/, "", $2); print $2; exit }' /etc/os-release)
    fi

    if [ -z "$value" ] && command -v sw_vers >/dev/null 2>&1; then
        value=$(sw_vers -productName 2>/dev/null || :)
    fi

    if [ -z "$value" ]; then
        value=$(uname -s 2>/dev/null || :)
    fi

    if [ -n "$value" ]; then
        printf '%s\n' "$value" | clean_value
    else
        print_na
    fi
}

gpu() {
    value=''

    if command -v lspci >/dev/null 2>&1; then
        value=$(lspci 2>/dev/null | awk -F': ' \
            '/(VGA compatible controller|3D controller|Display controller)/ { print $2; exit }')
    fi

    if [ -z "$value" ] && command -v system_profiler >/dev/null 2>&1; then
        value=$(system_profiler SPDisplaysDataType 2>/dev/null | \
            awk -F': ' '/Chipset Model:/ { print $2; exit }')
    fi

    if [ -z "$value" ] && command -v glxinfo >/dev/null 2>&1; then
        value=$(glxinfo -B 2>/dev/null | awk -F': ' '/Device:/ { print $2; exit }')
    fi

    if [ -n "$value" ]; then
        printf '%s\n' "$value" | clean_value
    else
        print_na
    fi
}

resolution() {
    value=''

    if command -v xdpyinfo >/dev/null 2>&1; then
        value=$(xdpyinfo 2>/dev/null | awk '/dimensions:/ { print $2; exit }')
    fi

    if [ -z "$value" ] && command -v xrandr >/dev/null 2>&1; then
        value=$(xrandr 2>/dev/null | awk '$2 == "connected" { for (i = 3; i <= NF; i++) if ($i ~ /^[0-9]+x[0-9]+[+-]/) { sub(/[+-].*$/, "", $i); print $i; exit } }')
    fi

    if [ -z "$value" ] && command -v wlr-randr >/dev/null 2>&1; then
        value=$(wlr-randr 2>/dev/null | awk '/^[[:space:]]*[0-9]+x[0-9]+/ { sub(/^[[:space:]]*/, ""); print $1; exit }')
    fi

    if [ -n "$value" ]; then
        printf '%s\n' "$value" | clean_value
    else
        print_na
    fi
}

locale_name() {
    value=$DISPLAY_LOCALE

    if [ -z "$value" ] && [ -r /etc/locale.conf ]; then
        value=$(awk -F= '$1 == "LANG" { gsub(/^"|"$/, "", $2); print $2; exit }' /etc/locale.conf)
    fi

    if [ -z "$value" ] && command -v locale >/dev/null 2>&1; then
        value=$(locale 2>/dev/null | awk -F= '$1 == "LANG" { print $2; exit }')
    fi

    if [ -n "$value" ]; then
        printf '%s\n' "$value" | clean_value
    else
        print_na
    fi
}

cpu_model() {
    value=''

    if [ -r /proc/cpuinfo ]; then
        value=$(awk -F: '/^(model name|Processor|Hardware)[[:space:]]*:/ { gsub(/^[[:space:]]+/, "", $2); print $2; exit }' /proc/cpuinfo)
    fi

    if [ -z "$value" ] && command -v sysctl >/dev/null 2>&1; then
        value=$(sysctl -n machdep.cpu.brand_string 2>/dev/null || :)
        if [ -z "$value" ]; then
            value=$(sysctl -n hw.model 2>/dev/null || :)
        fi
    fi

    if [ -z "$value" ]; then
        value=$(uname -p 2>/dev/null || :)
    fi

    if [ -z "$value" ] || [ "$value" = 'unknown' ]; then
        value=$(uname -m 2>/dev/null || :)
    fi

    if [ -n "$value" ]; then
        printf '%s\n' "$value" | clean_value
    else
        print_na
    fi
}

sensor_fan_value() {
    command -v sensors >/dev/null 2>&1 || return 0

    sensors 2>/dev/null | awk '
        /[Rr][Pp][Mm]/ {
            for (i = 1; i < NF; i++) {
                if ($i ~ /^[0-9]+([.][0-9]+)?$/ && tolower($(i + 1)) == "rpm") {
                    printf "%.0f\n", $i
                    exit
                }
            }
        }
    '
}

fan_speed() {
    value=$(sensor_fan_value)
    if [ -n "$value" ]; then
        printf '%s RPM\n' "$value"
        return
    fi

    for file in "$HWMON_ROOT"/*/fan*_input; do
        [ -r "$file" ] || continue
        value=$(sed -n '1p' "$file" 2>/dev/null | tr -d '[:space:]')
        if awk -v value="$value" 'BEGIN { exit !(value ~ /^[0-9]+$/) }'; then
            printf '%s RPM\n' "$value"
            return
        fi
    done

    print_na
}

sensor_temperature_value() {
    wanted=$1
    command -v sensors >/dev/null 2>&1 || return 0

    sensors 2>/dev/null | awk -v wanted="$wanted" '
        /:/ {
            for (i = 1; i <= NF; i++) {
                value = $i
                if (value ~ /^[+-]?[0-9]+([.][0-9]+)?°C$/) {
                    sub(/°C$/, "", value)
                    sub(/^\+/, "", value)
                    count++
                    if (count == wanted) {
                        printf "%.0f\n", value
                        exit
                    }
                } else if (value ~ /^[+-]?[0-9]+([.][0-9]+)?$/ && tolower($(i + 1)) == "c") {
                    sub(/^\+/, "", value)
                    count++
                    if (count == wanted) {
                        printf "%.0f\n", value
                        exit
                    }
                }
            }
        }
    '
}

temperature() {
    index=$1
    value=$(sensor_temperature_value "$index")
    if [ -n "$value" ]; then
        printf '%s °C\n' "$value"
        return
    fi

    count=0
    for file in "$HWMON_ROOT"/*/temp*_input; do
        [ -r "$file" ] || continue
        raw=$(sed -n '1p' "$file" 2>/dev/null | tr -d '[:space:]')
        value=$(awk -v raw="$raw" 'BEGIN { if (raw ~ /^-?[0-9]+$/) printf "%.0f", raw / 1000 }')
        [ -n "$value" ] || continue
        count=$((count + 1))
        if [ "$count" -eq "$index" ]; then
            printf '%s °C\n' "$value"
            return
        fi
    done

    print_na
}

battery_dir() {
    for dir in "$POWER_SUPPLY_ROOT"/BAT* \
               "$POWER_SUPPLY_ROOT"/CMB* \
               "$POWER_SUPPLY_ROOT"/battery*; do
        [ -d "$dir" ] || continue
        [ -r "$dir/capacity" ] || continue
        printf '%s\n' "$dir"
        return
    done
    return 1
}

battery_acpi_percent() {
    command -v acpi >/dev/null 2>&1 || return 0

    acpi -b 2>/dev/null | awk '
        {
            for (i = 1; i <= NF; i++) {
                value = $i
                gsub(/,/, "", value)
                if (value ~ /^[0-9]+%$/) {
                    sub(/%$/, "", value)
                    print value
                    exit
                }
            }
        }
    '
}

battery_percent_value() {
    path=$(battery_dir 2>/dev/null)
    if [ -n "$path" ]; then
        value=$(sed -n '1p' "$path/capacity" 2>/dev/null | tr -d '[:space:]')
        if awk -v value="$value" 'BEGIN { exit !(value ~ /^[0-9]+$/) }'; then
            awk -v value="$value" 'BEGIN {
                if (value < 0) value = 0
                if (value > 100) value = 100
                printf "%.0f\n", value
            }'
            return
        fi
    fi

    battery_acpi_percent
}

battery_status_value() {
    path=$(battery_dir 2>/dev/null)
    if [ -n "$path" ] && [ -r "$path/status" ]; then
        value=$(sed -n '1p' "$path/status" 2>/dev/null | sed 's/[[:space:]]*$//')
        [ -n "$value" ] && { printf '%s\n' "$value"; return; }
    fi

    if command -v acpi >/dev/null 2>&1; then
        value=$(acpi -b 2>/dev/null | awk -F': ' 'NR == 1 { sub(/,.*/, "", $2); print $2; exit }')
        [ -n "$value" ] && { printf '%s\n' "$value"; return; }
    fi

    printf '%s\n' 'Unknown'
}

battery_present() {
    value=$(battery_percent_value)
    if awk -v value="$value" 'BEGIN { exit !(value ~ /^[0-9]+$/) }'; then
        printf '%s\n' 1
    else
        printf '%s\n' 0
    fi
}

battery_display() {
    value=$(battery_percent_value)
    if ! awk -v value="$value" 'BEGIN { exit !(value ~ /^[0-9]+$/) }'; then
        print_na
        return
    fi
    printf '%s %s%%\n' "$(battery_status_value)" "$value"
}

battery_percent_text() {
    value=$(battery_percent_value)
    if awk -v value="$value" 'BEGIN { exit !(value ~ /^[0-9]+$/) }'; then
        printf '%s%%\n' "$value"
    else
        print_na
    fi
}

storage_percent() {
    case ${1:-root} in
        root)
            path=/
            ;;
        home)
            path=${HOME:-/}
            ;;
        *)
            print_na
            return
            ;;
    esac

    value=$(df -P "$path" 2>/dev/null | awk 'NR == 2 {
        gsub(/%/, "", $5)
        if ($5 ~ /^[0-9]+$/) print $5
        exit
    }')

    if [ -n "$value" ]; then
        printf '%s\n' "$value"
    else
        printf '%s\n' 0
    fi
}

case ${1:-help} in
    distro)
        distro
        ;;
    gpu)
        gpu
        ;;
    resolution)
        resolution
        ;;
    locale)
        locale_name
        ;;
    cpu)
        cpu_model
        ;;
    fan)
        fan_speed
        ;;
    temperature)
        temperature "${2:-1}"
        ;;
    battery)
        battery_display
        ;;
    battery-present)
        battery_present
        ;;
    battery-percent)
        battery_percent_value
        ;;
    battery-percent-text)
        battery_percent_text
        ;;
    storage)
        storage_percent "${2:-root}"
        ;;
    help)
        printf '%s\n' 'Usage: mainte-sysinfo.sh {distro|gpu|resolution|locale|cpu|fan|temperature [n]|battery|battery-present|battery-percent|battery-percent-text|storage [root|home]}'
        ;;
    *)
        print_na
        ;;
esac
