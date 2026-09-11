#!/usr/bin/env sh
# Prepare Mainte and optionally install its online font.

set -eu

FONT_VERSION='v3.5.1'
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/FiraCode.tar.xz"
FONT_SHA256='68e3bd6164864b8b514605bc34e3a87ac401c8c48682fcce6478c70263340207'
FONT_FILE_NAME='FiraCodeNerdFontMono-Regular.ttf'

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

usage() {
    printf '%s\n' \
        'Usage: sh install.sh [--offline|--online] [--start]' \
        '' \
        'Default mode downloads the pinned FiraCode Nerd Font over HTTPS.' \
        'Use --offline to skip the font download; --start launches Mainte after setup.'
}

MODE=online
START=0
while [ "$#" -gt 0 ]; do
    case "$1" in
        --online) MODE=online ;;
        --offline) MODE=offline ;;
        --start) START=1 ;;
        --help)
            usage
            exit 0
            ;;
        *)
            printf 'Unknown option: %s\n' "$1" >&2
            usage >&2
            exit 2
            ;;
    esac
    shift
done

chmod 755 \
    "$SCRIPT_DIR/conky-launch.sh" \
    "$SCRIPT_DIR/mainte-sysinfo.sh" \
    "$SCRIPT_DIR/mainte-features.sh" \
    "$SCRIPT_DIR/mainte-layout.sh" \
    "$SCRIPT_DIR/install.sh"

if [ "$MODE" = offline ]; then
    printf '%s\n' 'Skipped online font download (--offline).'
else
    FONT_DIR=${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}/fonts

    if command -v curl >/dev/null 2>&1; then
        download() {
            curl --fail --location --silent --show-error \
                --proto '=https' --tlsv1.2 "$FONT_URL" --output "$1"
        }
    elif command -v wget >/dev/null 2>&1; then
        download() {
            wget --https-only --quiet --output-document="$1" "$FONT_URL"
        }
    else
        printf '%s\n' 'Install curl or wget before using the online font mode.' >&2
        exit 1
    fi

    if command -v sha256sum >/dev/null 2>&1; then
        checksum() {
            sha256sum "$1" | awk '{ print $1 }'
        }
    elif command -v shasum >/dev/null 2>&1; then
        checksum() {
            shasum -a 256 "$1" | awk '{ print $1 }'
        }
    else
        printf '%s\n' 'Install sha256sum or shasum before using the online font mode.' >&2
        exit 1
    fi

    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/mainte-font.XXXXXX")
    trap 'rm -rf "$TEMP_DIR"' EXIT HUP INT TERM
    ARCHIVE="$TEMP_DIR/FiraCode.tar.xz"

    download "$ARCHIVE"
    if [ "$(checksum "$ARCHIVE")" != "$FONT_SHA256" ]; then
        printf '%s\n' 'The downloaded font checksum does not match the pinned release.' >&2
        exit 1
    fi

    tar -xJf "$ARCHIVE" -C "$TEMP_DIR"
    FONT_FILE=$(find "$TEMP_DIR" -type f -name "$FONT_FILE_NAME" -print | sed -n '1p')
    if [ -z "$FONT_FILE" ]; then
        printf '%s\n' "The downloaded archive did not contain $FONT_FILE_NAME." >&2
        exit 1
    fi

    mkdir -p "$FONT_DIR"
    cp "$FONT_FILE" "$FONT_DIR/"

    if command -v fc-cache >/dev/null 2>&1; then
        fc-cache -f "$FONT_DIR"
    fi

    printf 'Installed FiraCode Nerd Font Mono (%s) in %s\n' "$FONT_VERSION" "$FONT_DIR"
fi

if command -v conky >/dev/null 2>&1; then
    printf '%s\n' 'Conky detected.'
else
    printf '%s\n' 'Conky is not installed yet; install it before starting Mainte.'
fi

if [ "$START" -eq 1 ]; then
    exec "$SCRIPT_DIR/conky-launch.sh"
fi

printf '%s\n' 'Setup complete. Start Mainte with: ./conky-launch.sh'
