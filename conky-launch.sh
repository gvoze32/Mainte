#!/usr/bin/env sh

set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

if [ -r "$SCRIPT_DIR/mainte.local" ]; then
    # shellcheck disable=SC1090
    . "$SCRIPT_DIR/mainte.local"
fi

LAYOUT_FILE=${MAINTE_LAYOUT_FILE:-$SCRIPT_DIR/mainte.layout}
case "$LAYOUT_FILE" in
    "~/"*) LAYOUT_FILE=$HOME/${LAYOUT_FILE#~/} ;;
    /*) ;;
    *) LAYOUT_FILE=$SCRIPT_DIR/$LAYOUT_FILE ;;
esac
if [ -r "$LAYOUT_FILE" ]; then
    # shellcheck disable=SC1090
    . "$LAYOUT_FILE"
fi

usage() {
    printf '%s\n' \
        'Usage: ./conky-launch.sh [--extensions] [WALLPAPER]' \
        '' \
        'WALLPAPER may be an absolute path or a path relative to this directory.' \
        'Set MAINTE_WALLPAPER or MAINTE_EXTRAS=1 in mainte.local.' \
        'Run ./mainte-layout.sh to move named sections without editing Conky files.'
}

POSITIONAL_WALLPAPER=''
EXTRAS_ENABLED=${MAINTE_EXTRAS:-0}
while [ "$#" -gt 0 ]; do
    case "$1" in
        --extensions)
            EXTRAS_ENABLED=1
            ;;
        --help)
            usage
            exit 0
            ;;
        --*)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
        *)
            if [ -n "$POSITIONAL_WALLPAPER" ]; then
                printf '%s\n' 'Only one wallpaper path may be supplied.' >&2
                usage >&2
                exit 2
            fi
            POSITIONAL_WALLPAPER=$1
            ;;
    esac
    shift
done

case "$EXTRAS_ENABLED" in
    1|true|yes) EXTRAS_ENABLED=1 ;;
    *) EXTRAS_ENABLED=0 ;;
esac

normalize_offset() {
    value=$1
    if awk -v value="$value" 'BEGIN { exit !(value ~ /^[-+]?[0-9]+$/) }'; then
        awk -v value="$value" 'BEGIN { printf "%.0f\n", value + 0 }'
    else
        printf '%s\n' 0
    fi
}

identity_y=$(normalize_offset "${MAINTE_LAYOUT_IDENTITY_Y:-0}")
graphics_y=$(normalize_offset "${MAINTE_LAYOUT_GRAPHICS_Y:-0}")
locale_y=$(normalize_offset "${MAINTE_LAYOUT_LOCALE_Y:-0}")
performance_y=$(normalize_offset "${MAINTE_LAYOUT_PERFORMANCE_Y:-0}")
memory_y=$(normalize_offset "${MAINTE_LAYOUT_MEMORY_Y:-0}")
network_y=$(normalize_offset "${MAINTE_LAYOUT_NETWORK_Y:-0}")
battery_y=$(normalize_offset "${MAINTE_LAYOUT_BATTERY_Y:-0}")
storage_y=$(normalize_offset "${MAINTE_LAYOUT_STORAGE_Y:-0}")

identity_marker=$identity_y
graphics_marker=$((graphics_y - identity_y))
locale_marker=$((10 + locale_y - graphics_y))
performance_marker=$((-10 + performance_y - locale_y))
memory_marker=$((15 + memory_y - performance_y))
network_marker=$((10 + network_y - memory_y))
battery_marker=$((20 + battery_y - network_y))
storage_marker=$((25 + storage_y - battery_y))

LAYOUT_ENABLED=0
if [ "$identity_y" -ne 0 ] \
    || [ "$graphics_y" -ne 0 ] \
    || [ "$locale_y" -ne 0 ] \
    || [ "$performance_y" -ne 0 ] \
    || [ "$memory_y" -ne 0 ] \
    || [ "$network_y" -ne 0 ] \
    || [ "$battery_y" -ne 0 ] \
    || [ "$storage_y" -ne 0 ]; then
    LAYOUT_ENABLED=1
fi

if ! command -v conky >/dev/null 2>&1; then
    printf '%s\n' 'Mainte requires Conky, but conky was not found in PATH.' >&2
    exit 1
fi

WALLPAPER=${POSITIONAL_WALLPAPER:-${MAINTE_WALLPAPER:-$SCRIPT_DIR/bg.png}}
case "$WALLPAPER" in
    "~/"*) WALLPAPER=$HOME/${WALLPAPER#~/} ;;
esac
case "$WALLPAPER" in
    /*) ;;
    *) WALLPAPER=$(CDPATH= cd -- "$(dirname -- "$WALLPAPER")" && pwd)/$(basename -- "$WALLPAPER") ;;
esac
if [ ! -r "$WALLPAPER" ]; then
    printf 'Wallpaper is not readable: %s\n' "$WALLPAPER" >&2
    exit 1
fi

RUNTIME_DIR=${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}
if [ ! -d "$RUNTIME_DIR" ] || [ ! -w "$RUNTIME_DIR" ]; then
    RUNTIME_DIR=/tmp
fi
PID_FILE="$RUNTIME_DIR/mainte-conky-$(id -u).pid"
RUNTIME_BACKGROUND_CONFIG="$RUNTIME_DIR/mainte-conky-bg-$(id -u).conf"
RUNTIME_MAIN_CONFIG="$RUNTIME_DIR/mainte-conky-main-$(id -u).conf"
RUNTIME_WALLPAPER="$RUNTIME_DIR/mainte-wallpaper-$(id -u).png"

stop_previous() {
    [ -r "$PID_FILE" ] || return 0

    while IFS= read -r pid; do
        case "$pid" in
            ''|*[!0-9]*)
                continue
                ;;
        esac

        command_line=$(ps -p "$pid" -o command= 2>/dev/null || :)
        case "$command_line" in
            *"$SCRIPT_DIR/conkyrc-dark-bg"*|*"$RUNTIME_BACKGROUND_CONFIG"*|*"$SCRIPT_DIR/conkyrc-dark-bspwm"*|*"$RUNTIME_MAIN_CONFIG"*|*"$SCRIPT_DIR/conkyrc-extras"*)
                kill "$pid" 2>/dev/null || :
                ;;
        esac
    done < "$PID_FILE"

    rm -f "$PID_FILE"
}

stop_previous
sleep 0.2

BACKGROUND_CONFIG="$SCRIPT_DIR/conkyrc-dark-bg"
if [ "$WALLPAPER" != "$SCRIPT_DIR/bg.png" ]; then
    rm -f "$RUNTIME_WALLPAPER" "$RUNTIME_BACKGROUND_CONFIG"
    if ! ln -s "$WALLPAPER" "$RUNTIME_WALLPAPER" 2>/dev/null; then
        cp "$WALLPAPER" "$RUNTIME_WALLPAPER"
    fi
    escaped_wallpaper=$(printf '%s\n' "$RUNTIME_WALLPAPER" | sed 's/[\\&|]/\\&/g')
    sed "s|bg.png|$escaped_wallpaper|g" \
        "$SCRIPT_DIR/conkyrc-dark-bg" > "$RUNTIME_BACKGROUND_CONFIG"
    BACKGROUND_CONFIG="$RUNTIME_BACKGROUND_CONFIG"
else
    rm -f "$RUNTIME_WALLPAPER" "$RUNTIME_BACKGROUND_CONFIG"
fi

MAIN_CONFIG="$SCRIPT_DIR/conkyrc-dark-bspwm"
if [ "$LAYOUT_ENABLED" -eq 1 ]; then
    awk \
        -v identity="$identity_marker" \
        -v graphics="$graphics_marker" \
        -v locale="$locale_marker" \
        -v performance="$performance_marker" \
        -v memory="$memory_marker" \
        -v network="$network_marker" \
        -v battery="$battery_marker" \
        -v storage="$storage_marker" '
        function replace_offset(value) {
            sub(/\$\{voffset [^}]*\}/, "${voffset " value "}")
            return $0
        }
        /mainte-layout: identity/ {
            print
            getline
            print replace_offset(identity)
            next
        }
        /mainte-layout: graphics/ {
            print
            getline
            print replace_offset(graphics)
            next
        }
        /mainte-layout: locale/ {
            print
            getline
            print replace_offset(locale)
            next
        }
        /mainte-layout: performance/ {
            print
            getline
            print replace_offset(performance)
            next
        }
        /mainte-layout: memory/ {
            print
            getline
            print replace_offset(memory)
            next
        }
        /mainte-layout: network/ {
            print
            getline
            print replace_offset(network)
            next
        }
        /mainte-layout: battery/ {
            print
            getline
            print replace_offset(battery)
            next
        }
        /mainte-layout: storage/ {
            print
            getline
            print replace_offset(storage)
            next
        }
        { print }
    ' "$SCRIPT_DIR/conkyrc-dark-bspwm" > "$RUNTIME_MAIN_CONFIG"
    MAIN_CONFIG="$RUNTIME_MAIN_CONFIG"
else
    rm -f "$RUNTIME_MAIN_CONFIG"
fi

cd "$SCRIPT_DIR"

# Start the artwork first so the information overlay remains in front.
conky -c "$BACKGROUND_CONFIG" &
BACKGROUND_PID=$!
sleep 0.8
conky -c "$MAIN_CONFIG" &
MAIN_PID=$!

printf '%s\n' "$BACKGROUND_PID" "$MAIN_PID" > "$PID_FILE"
if [ "$EXTRAS_ENABLED" -eq 1 ]; then
    conky -c "$SCRIPT_DIR/conkyrc-extras" &
    printf '%s\n' "$!" >> "$PID_FILE"
fi
