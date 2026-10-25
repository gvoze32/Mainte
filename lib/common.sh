# Shared helpers for the Mainte CLI. Sourced by ./mainte after MAINTE_ROOT is set.
# shellcheck shell=sh disable=SC2034

# Vertical sections of the text column, in render order.
MAINTE_SECTIONS='identity graphics locale performance memory network battery storage'
# Everything `./mainte layout` can move: the whole text column, then each section.
MAINTE_LAYOUT_ITEMS="text-x text-y $MAINTE_SECTIONS"

MAINTE_DEFAULT_WALLPAPER=$MAINTE_ROOT/assets/bg.png
MAINTE_DEFAULT_WALLPAPER_SIZE=280x679

# Geometry of the original 2019 layout, measured from its screenshot: the text
# column's right edge reaches this far into the artwork, and starts this far
# below the artwork's top edge. Layout offsets are deltas on top of these.
MAINTE_TEXT_OVERLAP=101
MAINTE_TEXT_DROP=25

die() {
    printf 'mainte: %s\n' "$*" >&2
    exit 1
}

has_command() {
    command -v "$1" >/dev/null 2>&1
}

is_int() {
    _digits=${1#[+-]}
    case $_digits in
        ''|*[!0-9]*) return 1 ;;
    esac
    return 0
}

# Print a canonical integer (no plus sign, no leading zeros); non-integers become 0.
to_int() {
    if ! is_int "$1"; then
        printf '0\n'
        return
    fi
    _sign=''
    case $1 in
        -*) _sign=- ;;
    esac
    _digits=${1#[+-]}
    while :; do
        case $_digits in
            0?*) _digits=${_digits#0} ;;
            *) break ;;
        esac
    done
    [ "$_digits" != 0 ] || _sign=''
    printf '%s%s\n' "$_sign" "$_digits"
}

# resolve_path BASE PATH: expand a leading ~/ and anchor relative paths at BASE.
resolve_path() {
    # A literal ~ is intended: config values are quoted, so the shell never expanded it.
    # shellcheck disable=SC2088
    case $2 in
        '~') printf '%s\n' "$HOME" ;;
        '~/'*) printf '%s/%s\n' "$HOME" "${2#??}" ;;
        /*) printf '%s\n' "$2" ;;
        *) printf '%s/%s\n' "${1%/}" "$2" ;;
    esac
}

# Quote a value so that sourcing the output restores it verbatim.
shell_quote() {
    printf "'%s'\n" "$(printf '%s' "$1" | sed "s/'/'\\\\''/g")"
}

load_config() {
    MAINTE_CONFIG=${MAINTE_CONFIG:-$MAINTE_ROOT/mainte.local}
    if [ -r "$MAINTE_CONFIG" ]; then
        # shellcheck disable=SC1090
        . "$MAINTE_CONFIG"
    fi

    MAINTE_LAYOUT_FILE=$(resolve_path "$MAINTE_ROOT" "${MAINTE_LAYOUT_FILE:-mainte.layout}")
    if [ -r "$MAINTE_LAYOUT_FILE" ]; then
        # shellcheck disable=SC1090
        . "$MAINTE_LAYOUT_FILE"
    fi
}

# Runtime state: rendered configs, the artwork link, PIDs, and the last session.
_state_base=${XDG_RUNTIME_DIR:-}
if [ -z "$_state_base" ] || [ ! -d "$_state_base" ] || [ ! -w "$_state_base" ]; then
    _state_base=${TMPDIR:-/tmp}
fi
MAINTE_STATE=${_state_base%/}/mainte-$(id -u)
MAINTE_PID_FILE=$MAINTE_STATE/conky.pid
MAINTE_SESSION_FILE=$MAINTE_STATE/session
MAINTE_LOG_FILE=$MAINTE_STATE/conky.log

ensure_state_dir() {
    case $MAINTE_STATE in
        *[[:space:]]*) die "runtime directory must not contain whitespace: $MAINTE_STATE" ;;
    esac
    mkdir -p "$MAINTE_STATE"
    # The path was checked for whitespace above, so parsing ls output is safe.
    # shellcheck disable=SC2012
    [ "$(ls -ldn "$MAINTE_STATE" | awk '{ print $3 }')" = "$(id -u)" ] \
        || die "runtime directory is not owned by you: $MAINTE_STATE"
    chmod 700 "$MAINTE_STATE"
}

# Print the PIDs from the PID file that still belong to this Mainte session.
mainte_pids() {
    [ -r "$MAINTE_PID_FILE" ] || return 0
    while IFS= read -r _pid; do
        case $_pid in
            ''|*[!0-9]*) continue ;;
        esac
        _args=$(ps -p "$_pid" -o args= 2>/dev/null || :)
        case $_args in
            *conky*"$MAINTE_STATE/"*) printf '%s\n' "$_pid" ;;
        esac
    done < "$MAINTE_PID_FILE"
}

mainte_is_running() {
    [ -n "$(mainte_pids)" ]
}

layout_var() {
    case $1 in
        text-x) printf 'MAINTE_LAYOUT_TEXT_X\n' ;;
        text-y) printf 'MAINTE_LAYOUT_TEXT_Y\n' ;;
        *) printf 'MAINTE_LAYOUT_%s_Y\n' "$(printf '%s' "$1" | tr '[:lower:]' '[:upper:]')" ;;
    esac
}

layout_get() {
    _raw=0
    eval "_raw=\${$(layout_var "$1"):-0}"
    to_int "$_raw"
}

layout_set() {
    eval "$(layout_var "$1")=\$2"
}
