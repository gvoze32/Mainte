#!/usr/bin/env sh
# Adapters for the optional extensions panel, adapted from
# https://github.com/AyoItsYas/modified-mainte without its machine-specific
# parts. Every adapter prints N/A when its provider is missing.

SYSFS_ROOT=${MAINTE_SYSFS_ROOT:-/sys}
PROC_ROOT=${MAINTE_PROC_ROOT:-/proc}
RESOLV_CONF=${MAINTE_RESOLV_CONF:-/etc/resolv.conf}

print_na() {
    printf '%s\n' 'N/A'
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

# Conky does not re-parse execi output, but keep values short and single-line.
clean_value() {
    printf '%s\n' "$(printf '%s' "$1" \
        | tr '\n' ' ' \
        | sed 's/[$}{]//g; s/[[:space:]][[:space:]]*/ /g; s/^ *//; s/ *$//' \
        | cut -c 1-64)"
}

print_value() {
    if [ -n "$1" ]; then
        clean_value "$1"
    else
        print_na
    fi
}

# --- media (playerctl) -------------------------------------------------------

# The first playing player, else the first paused one.
media_player() {
    has_command playerctl || return 0
    playerctl -l 2>/dev/null | while IFS= read -r player; do
        printf '%s %s\n' "$(playerctl -p "$player" status 2>/dev/null)" "$player"
    done | awk '
        $1 == "Playing" { print $2; found = 1; exit }
        $1 == "Paused" && paused == "" { paused = $2 }
        END { if (!found && paused != "") print paused }
    '
}

media() {
    player=$(media_player)
    [ -n "$player" ] || {
        print_na
        return
    }
    status=$(playerctl -p "$player" status 2>/dev/null)
    title=$(playerctl -p "$player" metadata --format '{{ title }}' 2>/dev/null)
    artist=$(playerctl -p "$player" metadata --format '{{ artist }}' 2>/dev/null)
    if [ -n "$artist" ] && [ -n "$title" ]; then
        clean_value "$status: $artist - $title"
    else
        clean_value "$status: ${title:-$player}"
    fi
}

media_time() {
    player=$(media_player)
    [ -n "$player" ] || {
        print_na
        return
    }
    print_value "$(playerctl -p "$player" metadata \
        --format '{{ duration(position) }} / {{ duration(mpris:length) }}' 2>/dev/null)"
}

media_percent() {
    player=$(media_player)
    [ -n "$player" ] || {
        printf '0\n'
        return
    }
    position=$(playerctl -p "$player" position 2>/dev/null)
    length=$(playerctl -p "$player" metadata --format '{{ mpris:length }}' 2>/dev/null)
    awk -v position="${position:-0}" -v length_us="${length:-0}" 'BEGIN {
        percent = length_us > 0 ? position * 100000000 / length_us : 0
        if (percent < 0) percent = 0
        if (percent > 100) percent = 100
        printf "%.0f\n", percent
    }'
}

# --- network -----------------------------------------------------------------

# Gateway of the lowest-metric default route, decoded from /proc/net/route.
gateway() {
    [ -r "$PROC_ROOT/net/route" ] || {
        print_na
        return
    }
    print_value "$(awk '
        function hex(s,    i, n) {
            n = 0
            for (i = 1; i <= length(s); i++) n = n * 16 + index("0123456789ABCDEF", toupper(substr(s, i, 1))) - 1
            return n
        }
        NR > 1 && $2 == "00000000" && $8 == "00000000" {
            if (best == "" || $7 + 0 < metric) { best = $3; metric = $7 + 0 }
        }
        END {
            if (best == "") exit
            # /proc/net/route stores IPv4 addresses little-endian.
            printf "%d.%d.%d.%d\n", hex(substr(best, 7, 2)), hex(substr(best, 5, 2)), hex(substr(best, 3, 2)), hex(substr(best, 1, 2))
        }
    ' "$PROC_ROOT/net/route")"
}

# Upstream DNS servers; looks through the systemd-resolved stub when possible.
dns() { # dns [IFACE]
    servers=''
    if [ -r "$RESOLV_CONF" ]; then
        servers=$(awk '$1 == "nameserver" { print $2 }' "$RESOLV_CONF")
    fi
    case $servers in
        127.0.0.53*)
            if has_command resolvectl; then
                if [ -n "${1:-}" ]; then
                    upstream=$(resolvectl dns "$1" 2>/dev/null)
                else
                    upstream=$(resolvectl dns 2>/dev/null)
                fi
                upstream=$(printf '%s\n' "$upstream" | sed -n 's/^[^:]*:[[:space:]]*//p' | tr ' ' '\n' | awk 'NF')
                [ -z "$upstream" ] || servers=$upstream
            fi
            ;;
    esac
    print_value "$(printf '%s\n' "$servers" | awk 'NF && NR <= 2' | tr '\n' ' ')"
}

# Today's received/sent traffic recorded by vnstat.
traffic() { # traffic IFACE
    has_command vnstat || {
        print_na
        return
    }
    print_value "$(vnstat -i "${1:-}" --oneline 2>/dev/null | awk -F';' 'NF >= 6 { printf "down %s up %s\n", $4, $5 }')"
}

# --- devices -----------------------------------------------------------------

bluetooth() {
    has_command bluetoothctl || {
        print_na
        return
    }
    bluetoothctl devices 2>/dev/null | awk '$1 == "Device" { print $2 }' | while IFS= read -r mac; do
        bluetoothctl info "$mac" 2>/dev/null | awk '
            /^[[:space:]]*Alias:/ { sub(/^[[:space:]]*Alias:[[:space:]]*/, ""); name = $0 }
            /^[[:space:]]*Connected: yes/ { connected = 1 }
            /^[[:space:]]*Battery Percentage:/ { battery = $NF; gsub(/[()]/, "", battery) }
            END { if (connected) print name (battery != "" ? " " battery "%" : "") }
        '
    done | awk '
        { count++; names = names (names == "" ? "" : ", ") $0 }
        END { if (count) print count " connected: " names; else print "0 connected" }
    ' | while IFS= read -r line; do clean_value "$line"; done
}

usb() {
    has_command lsusb || {
        print_na
        return
    }
    print_value "$(lsusb 2>/dev/null | awk '
        {
            count++
            name = $0
            sub(/^.*ID [0-9a-fA-F:]+ ?/, "", name)
            if (name !~ /root hub/ && name != "" && shown < 2) {
                names = names (names == "" ? "" : ", ") name
                shown++
            }
        }
        END { if (count) print count " devices" (names != "" ? ": " names : "") }
    ')"
}

android() {
    has_command adb || {
        print_na
        return
    }
    print_value "$(adb devices -l 2>/dev/null | awk '
        NR > 1 && $2 == "device" {
            count++
            for (i = 3; i <= NF; i++) if ($i ~ /^model:/) {
                model = substr($i, 7)
                gsub(/_/, " ", model)
                names = names (names == "" ? "" : ", ") model
            }
        }
        END { print (count + 0) " devices" (names != "" ? ": " names : "") }
    ')"
}

# --- GPU ---------------------------------------------------------------------

amdgpu_device() {
    for file in "$SYSFS_ROOT"/class/drm/card*/device/gpu_busy_percent; do
        if [ -r "$file" ]; then
            printf '%s\n' "${file%/gpu_busy_percent}"
            return
        fi
    done
}

gpu() {
    if has_command nvidia-smi; then
        value=$(nvidia-smi \
            --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
            --format=csv,noheader,nounits 2>/dev/null | awk -F', *' 'NR == 1 && NF == 4 {
                printf "NVIDIA %s%% | %s/%s MiB | %s C\n", $1, $2, $3, $4
            }')
        if [ -n "$value" ]; then
            clean_value "$value"
            return
        fi
    fi

    # amdgpu exposes load and VRAM in sysfs, so no radeontop daemon is needed.
    device=$(amdgpu_device)
    if [ -n "$device" ]; then
        busy=$(cat "$device/gpu_busy_percent" 2>/dev/null)
        used=$(cat "$device/mem_info_vram_used" 2>/dev/null)
        total=$(cat "$device/mem_info_vram_total" 2>/dev/null)
        temp=''
        for file in "$device"/hwmon/hwmon*/temp1_input; do
            [ -r "$file" ] && temp=$(cat "$file") && break
        done
        clean_value "$(awk -v busy="$busy" -v used="$used" -v total="$total" -v temp="$temp" 'BEGIN {
            line = "AMD " busy "%"
            if (total > 0) line = line sprintf(" | %d/%d MiB", used / 1048576, total / 1048576)
            if (temp != "") line = line sprintf(" | %d C", temp / 1000)
            print line
        }')"
        return
    fi
    print_na
}

# --- weather (wttr.in, no API key) ---------------------------------------------

weather() {
    location=${MAINTE_WEATHER:-}
    case $location in
        ''|*[!A-Za-z0-9\ ,.-]*)
            print_na
            return
            ;;
    esac
    url="https://wttr.in/$(printf '%s' "$location" | tr ' ' '+')?m&format=%C+%t"
    if has_command curl; then
        value=$(curl --fail --silent --max-time 10 --proto '=https' "$url" 2>/dev/null)
    elif has_command wget; then
        value=$(wget --quiet --timeout=10 --https-only -O - "$url" 2>/dev/null)
    else
        value=''
    fi
    # wttr.in answers errors with long HTML or "Unknown location" text.
    case $value in
        *'<'*|*Unknown*|*Sorry*) value='' ;;
    esac
    print_value "$value"
}

available() {
    case ${1:-} in
        media) has_command playerctl ;;
        traffic) has_command vnstat ;;
        bluetooth) has_command bluetoothctl ;;
        usb) has_command lsusb ;;
        android) has_command adb ;;
        gpu) has_command nvidia-smi || [ -n "$(amdgpu_device)" ] ;;
        weather) [ -n "${MAINTE_WEATHER:-}" ] && { has_command curl || has_command wget; } ;;
        *) return 1 ;;
    esac
}

case ${1:-help} in
    available)
        if available "${2:-}"; then
            printf '1\n'
        else
            printf '0\n'
        fi
        ;;
    media) media ;;
    media-time) media_time ;;
    media-percent) media_percent ;;
    gateway) gateway ;;
    dns) dns "${2:-}" ;;
    traffic) traffic "${2:-}" ;;
    bluetooth) bluetooth ;;
    usb) usb ;;
    android) android ;;
    gpu) gpu ;;
    weather) weather ;;
    help|-h|--help)
        printf '%s\n' 'Usage: providers/features.sh {available NAME|media|media-time|media-percent|gateway|dns [IFACE]|traffic IFACE|bluetooth|usb|android|gpu|weather}'
        ;;
    *) print_na ;;
esac
