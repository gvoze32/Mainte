# `mainte run`, `mainte reload`, and `mainte stop`.
# shellcheck shell=sh

run_usage() {
    printf '%s\n' \
        'Usage: mainte run [--extensions] [WALLPAPER]' \
        '' \
        'WALLPAPER overrides MAINTE_WALLPAPER for this session; relative paths' \
        'are resolved from the current directory. Running again restarts Mainte.'
}

cmd_run() {
    _cli_wallpaper=''
    _cli_extras=''
    while [ "$#" -gt 0 ]; do
        case $1 in
            --extensions) _cli_extras=1 ;;
            -h|--help)
                run_usage
                return 0
                ;;
            -*)
                run_usage >&2
                die "unknown option: $1"
                ;;
            *)
                [ -z "$_cli_wallpaper" ] || die 'only one wallpaper path may be given'
                _cli_wallpaper=$(resolve_path "$PWD" "$1")
                ;;
        esac
        shift
    done

    start_mainte "$_cli_wallpaper" "$_cli_extras"

    # Remember this session's overrides for `mainte reload` once it started.
    {
        printf 'MAINTE_SESSION_WALLPAPER=%s\n' "$(shell_quote "$_cli_wallpaper")"
        printf 'MAINTE_SESSION_EXTRAS=%s\n' "$(shell_quote "$_cli_extras")"
    } > "$MAINTE_SESSION_FILE"
}

# Restart with the options of the last `mainte run`, re-reading config and layout.
cmd_reload() {
    [ "$#" -eq 0 ] || die 'reload takes no arguments'
    [ -r "$MAINTE_SESSION_FILE" ] || die 'Mainte has not been started yet; use: mainte run'
    MAINTE_SESSION_WALLPAPER=''
    MAINTE_SESSION_EXTRAS=''
    # shellcheck disable=SC1090
    . "$MAINTE_SESSION_FILE"
    start_mainte "$MAINTE_SESSION_WALLPAPER" "$MAINTE_SESSION_EXTRAS"
}

cmd_stop() {
    [ "$#" -eq 0 ] || die 'stop takes no arguments'
    if mainte_is_running; then
        stop_mainte
        printf 'Mainte stopped.\n'
    else
        rm -f "$MAINTE_PID_FILE"
        printf 'Mainte is not running.\n'
    fi
}

stop_mainte() {
    _pids=$(mainte_pids)
    rm -f "$MAINTE_PID_FILE"
    [ -n "$_pids" ] || return 0

    # Word splitting is intended: one PID per word.
    # shellcheck disable=SC2086
    kill $_pids 2>/dev/null || :
    _tries=0
    while [ "$_tries" -lt 20 ]; do
        _alive=''
        for _pid in $_pids; do
            if kill -0 "$_pid" 2>/dev/null; then
                _alive=1
            fi
        done
        [ -n "$_alive" ] || return 0
        sleep 0.1
        _tries=$((_tries + 1))
    done
}

int_setting() { # int_setting NAME VALUE
    is_int "$2" || die "$1 must be an integer, got: $2"
    to_int "$2"
}

# Network interface and battery names are embedded in Conky variables.
device_setting() { # device_setting NAME VALUE
    case $2 in
        ''|*[!A-Za-z0-9._:@-]*) die "$1 contains unsupported characters: $2" ;;
    esac
    printf '%s\n' "$2"
}

start_mainte() { # start_mainte CLI_WALLPAPER CLI_EXTRAS
    has_command conky || die 'Conky is not installed (conky was not found in PATH).'

    if [ -n "$1" ]; then
        _wallpaper=$1
    elif [ -n "${MAINTE_WALLPAPER:-}" ]; then
        _wallpaper=$(resolve_path "$MAINTE_ROOT" "$MAINTE_WALLPAPER")
    else
        _wallpaper=$MAINTE_DEFAULT_WALLPAPER
    fi
    [ -f "$_wallpaper" ] && [ -r "$_wallpaper" ] \
        || die "wallpaper is not a readable file: $_wallpaper"

    _extras=${2:-${MAINTE_EXTRAS:-0}}
    case $_extras in
        1|true|yes|on) _extras=1 ;;
        *) _extras=0 ;;
    esac

    # Read by providers/features.sh inside Conky, so it must be exported.
    MAINTE_WEATHER=${MAINTE_WEATHER:-}
    case $MAINTE_WEATHER in
        *[!A-Za-z0-9\ ,.-]*) die "MAINTE_WEATHER may only contain letters, digits, spaces, commas, dots, and dashes: $MAINTE_WEATHER" ;;
    esac
    export MAINTE_WEATHER

    _size=${MAINTE_WALLPAPER_SIZE:-$MAINTE_DEFAULT_WALLPAPER_SIZE}
    _art_width=${_size%%x*}
    _art_height=${_size#*x}
    case "$_size/$_art_width:$_art_height" in
        *x*/[1-9]*:[1-9]*) ;;
        *) die "MAINTE_WALLPAPER_SIZE must look like 280x679, got: $_size" ;;
    esac
    case "$_art_width$_art_height" in
        *[!0-9]*) die "MAINTE_WALLPAPER_SIZE must look like 280x679, got: $_size" ;;
    esac

    _color=${MAINTE_COLOR:-BEC8CB}
    _color=${_color#\#}
    case $_color in
        [0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f][0-9A-Fa-f]) ;;
        *) die "MAINTE_COLOR must be a 6-digit hex colour, got: ${MAINTE_COLOR:-}" ;;
    esac

    _gap_x=$(int_setting MAINTE_GAP_X "${MAINTE_GAP_X:-60}")
    _gap_y=$(int_setting MAINTE_GAP_Y "${MAINTE_GAP_Y:-40}")
    _text_x=$(layout_get text-x)
    _text_y=$(layout_get text-y)

    _iface=${MAINTE_NET_IFACE:-$(sh "$MAINTE_ROOT/providers/sysinfo.sh" net-iface)}
    _iface=$(device_setting MAINTE_NET_IFACE "${_iface:-lo}")
    _battery=${MAINTE_BATTERY:-$(sh "$MAINTE_ROOT/providers/sysinfo.sh" battery-name)}
    _battery=$(device_setting MAINTE_BATTERY "${_battery:-none}")

    ensure_state_dir
    stop_mainte

    # Conky cannot parse image paths containing spaces, so point at a link.
    _extension=${_wallpaper##*/}
    case $_extension in
        *.*) _extension=${_extension##*.} ;;
        *) _extension=png ;;
    esac
    rm -f "$MAINTE_STATE"/wallpaper.*
    _artwork=$MAINTE_STATE/wallpaper.$_extension
    ln -s "$_wallpaper" "$_artwork" 2>/dev/null || cp "$_wallpaper" "$_artwork"

    MAINTE_T_WALLPAPER=$_artwork
    MAINTE_T_ART_WIDTH=$_art_width
    MAINTE_T_ART_HEIGHT=$_art_height
    MAINTE_T_ART_GAP_X=$_gap_x
    MAINTE_T_ART_GAP_Y=$_gap_y
    MAINTE_T_TEXT_GAP_X=$((_gap_x + _art_width - MAINTE_TEXT_OVERLAP - _text_x))
    MAINTE_T_TEXT_GAP_Y=$((_gap_y + MAINTE_TEXT_DROP + _text_y))
    MAINTE_T_COLOR=$_color
    MAINTE_T_IFACE=$_iface
    MAINTE_T_BATTERY=$_battery
    MAINTE_T_BATTERY_LABEL=$(printf '%s\n' "$_battery" | sed 's/^\([A-Za-z]*\)\([0-9]\)/\1 \2/')
    export MAINTE_T_WALLPAPER MAINTE_T_ART_WIDTH MAINTE_T_ART_HEIGHT \
        MAINTE_T_ART_GAP_X MAINTE_T_ART_GAP_Y MAINTE_T_TEXT_GAP_X MAINTE_T_TEXT_GAP_Y \
        MAINTE_T_COLOR MAINTE_T_IFACE MAINTE_T_BATTERY MAINTE_T_BATTERY_LABEL
    for _section in $MAINTE_SECTIONS; do
        _name=$(printf '%s' "$_section" | tr '[:lower:]' '[:upper:]')
        eval "MAINTE_Y_$_name=\$(layout_get \"\$_section\")"
        export "MAINTE_Y_$_name"
    done

    render_template artwork
    render_template main
    if [ "$_extras" -eq 1 ]; then
        render_template extras
    fi

    # Provider scripts are referenced relative to the project root.
    cd "$MAINTE_ROOT" || die "cannot enter $MAINTE_ROOT"
    : > "$MAINTE_LOG_FILE"
    # Start the artwork first so the text window stacks above it.
    conky -c "$MAINTE_STATE/artwork.conf" >> "$MAINTE_LOG_FILE" 2>&1 < /dev/null &
    printf '%s\n' "$!" > "$MAINTE_PID_FILE"
    sleep 0.5
    conky -c "$MAINTE_STATE/main.conf" >> "$MAINTE_LOG_FILE" 2>&1 < /dev/null &
    printf '%s\n' "$!" >> "$MAINTE_PID_FILE"
    if [ "$_extras" -eq 1 ]; then
        conky -c "$MAINTE_STATE/extras.conf" >> "$MAINTE_LOG_FILE" 2>&1 < /dev/null &
        printf '%s\n' "$!" >> "$MAINTE_PID_FILE"
    fi

    printf 'Mainte started (artwork: %s, network: %s, battery: %s).\n' \
        "$_wallpaper" "$_iface" "$_battery"
    printf 'Conky log: %s\n' "$MAINTE_LOG_FILE"
}

# Fill {{name}} tokens from MAINTE_T_* and {{offset SECTION BASE}} tokens from
# MAINTE_Y_*. A section offset is relative to the previous section because
# Conky's voffset is cumulative, so moving one section leaves the rest in place.
render_template() { # render_template NAME
    awk '
        function fail(message) {
            printf "mainte: %s: %s\n", FILENAME, message > "/dev/stderr"
            failed = 1
            exit 1
        }
        function resolve(token,    parts, count, key, value) {
            count = split(token, parts, " ")
            if (parts[1] == "offset" && count == 3) {
                key = "MAINTE_Y_" toupper(parts[2])
                if (!(key in ENVIRON)) fail("unknown section: " parts[2])
                value = parts[3] + ENVIRON[key] - previous
                previous = ENVIRON[key]
                return value
            }
            key = "MAINTE_T_" toupper(token)
            if (count != 1 || !(key in ENVIRON)) fail("unknown token: {{" token "}}")
            return ENVIRON[key]
        }
        {
            line = $0
            output = ""
            while (match(line, /[{][{][^}]*[}][}]/)) {
                output = output substr(line, 1, RSTART - 1) resolve(substr(line, RSTART + 2, RLENGTH - 4))
                line = substr(line, RSTART + RLENGTH)
            }
            print output line
        }
        END { if (failed) exit 1 }
    ' "$MAINTE_ROOT/conky/$1.conf" > "$MAINTE_STATE/$1.conf"
}
