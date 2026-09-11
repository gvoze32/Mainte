#!/usr/bin/env sh
# Optional adapters inspired by community Mainte extensions.
# Every adapter degrades to N/A when its provider is not installed.

set -eu

clean_value() {
    printf '%s\n' "$1" \
        | tr '\n' ' ' \
        | sed 's/[$}{]//g; s/[[:space:]][[:space:]]*/ /g; s/^ *//; s/ *$//' \
        | cut -c 1-64
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

media_player() {
    has_command playerctl || return 1

    players=$(playerctl -l 2>/dev/null || :)
    [ -n "$players" ] || return 1

    paused=''
    old_ifs=$IFS
    IFS='
'
    for player in $players; do
        status=$(playerctl -p "$player" status 2>/dev/null || :)
        case "$status" in
            Playing)
                IFS=$old_ifs
                printf '%s\n' "$player"
                return 0
                ;;
            Paused)
                [ -n "$paused" ] || paused=$player
                ;;
        esac
    done
    IFS=$old_ifs

    [ -n "$paused" ] || return 1
    printf '%s\n' "$paused"
}

media() {
    player=$(media_player || :)
    [ -n "$player" ] || {
        print_na
        return
    }

    status=$(playerctl -p "$player" status 2>/dev/null || printf 'Unknown')
    artist=$(playerctl -p "$player" metadata --format '{{artist}}' 2>/dev/null || :)
    title=$(playerctl -p "$player" metadata --format '{{title}}' 2>/dev/null || :)

    if [ -n "$artist" ] && [ -n "$title" ]; then
        clean_value "$status: $artist - $title"
    elif [ -n "$title" ]; then
        clean_value "$status: $title"
    else
        clean_value "$status: $player"
    fi
}

media_percent() {
    player=$(media_player || :)
    [ -n "$player" ] || {
        printf '0\n'
        return
    }

    position=$(playerctl -p "$player" position 2>/dev/null || printf '0')
    length=$(playerctl -p "$player" metadata --format '{{mpris:length}}' 2>/dev/null || printf '0')
    awk -v position="$position" -v duration="$length" '
        BEGIN {
            if (duration > 1000000) duration = duration / 1000000
            if (duration > 0) {
                percent = (position / duration) * 100
                if (percent < 0) percent = 0
                if (percent > 100) percent = 100
                printf "%.0f\n", percent
            } else {
                print "0"
            }
        }
    '
}

bluetooth() {
    has_command bluetoothctl || {
        print_na
        return
    }

    connected=$(bluetoothctl devices Connected 2>/dev/null || :)
    count=$(printf '%s\n' "$connected" | awk 'NF { count++ } END { print count + 0 }')
    names=$(printf '%s\n' "$connected" \
        | awk '{$1 = ""; $2 = ""; sub(/^ +/, ""); print}' \
        | tr '\n' ',' \
        | sed 's/,$//; s/,/, /g')

    if [ "$count" -gt 0 ] && [ -n "$names" ]; then
        clean_value "$count connected: $names"
    else
        printf '%s\n' "$count connected"
    fi
}

usb() {
    has_command lsusb || {
        print_na
        return
    }

    devices=$(lsusb 2>/dev/null || :)
    count=$(printf '%s\n' "$devices" | awk 'NF { count++ } END { print count + 0 }')
    names=$(printf '%s\n' "$devices" \
        | sed -n '1,2{s/^[^:]*: //; s/^[^ ]* [^ ]* //; p;}' \
        | tr '\n' ',' \
        | sed 's/,$//; s/,/, /g')

    if [ "$count" -gt 0 ] && [ -n "$names" ]; then
        clean_value "$count devices: $names"
    else
        printf '%s\n' "$count devices"
    fi
}

android() {
    has_command adb || {
        print_na
        return
    }

    adb devices -l 2>/dev/null | awk '
        NR > 1 && $2 == "device" {
            count++
            model = ""
            for (i = 3; i <= NF; i++) {
                if ($i ~ /^model:/) {
                    model = $i
                    sub(/^model:/, "", model)
                    gsub(/_/, " ", model)
                }
            }
            if (model != "") {
                if (names != "") names = names ", "
                names = names model
            }
        }
        END {
            if (count == 0) print "0 devices"
            else if (names != "") print count " devices: " names
            else print count " devices"
        }
    ' | while IFS= read -r value; do clean_value "$value"; done
}

gpu() {
    has_command nvidia-smi || {
        print_na
        return
    }

    nvidia-smi \
        --query-gpu=utilization.gpu,memory.used,memory.total,temperature.gpu \
        --format=csv,noheader,nounits 2>/dev/null \
        | awk -F',' '
            NR == 1 {
                for (i = 1; i <= 4; i++) gsub(/^[ 	]+|[ 	]+$/, "", $i)
                printf "NVIDIA %s%% | %s/%s MiB | %s C\n", $1, $2, $3, $4
                found = 1
                exit
            }
            END { if (!found) print "N/A" }
        ' | while IFS= read -r value; do clean_value "$value"; done
}

print_na() {
    printf '%s\n' 'N/A'
}

available() {
    case "${1:-}" in
        media) has_command playerctl ;;
        bluetooth) has_command bluetoothctl ;;
        usb) has_command lsusb ;;
        android) has_command adb ;;
        gpu) has_command nvidia-smi ;;
        any)
            has_command playerctl \
                || has_command bluetoothctl \
                || has_command lsusb \
                || has_command adb \
                || has_command nvidia-smi
            ;;
        *) return 1 ;;
    esac
}

case "${1:-}" in
    available)
        if available "${2:-}"; then
            printf '1\n'
        else
            printf '0\n'
        fi
        ;;
    media) media ;;
    media-percent) media_percent ;;
    bluetooth) bluetooth ;;
    usb) usb ;;
    android) android ;;
    gpu) gpu ;;
    help)
        printf '%s\n' 'Usage: ./mainte-features.sh {available|media|media-percent|bluetooth|usb|android|gpu}'
        ;;
    *) print_na ;;
esac
