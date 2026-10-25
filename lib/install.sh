# `mainte install`: install the pinned font and create the per-machine config.
# shellcheck shell=sh

FONT_VERSION='v3.5.1'
FONT_URL="https://github.com/ryanoasis/nerd-fonts/releases/download/${FONT_VERSION}/FiraCode.tar.xz"
FONT_SHA256='68e3bd6164864b8b514605bc34e3a87ac401c8c48682fcce6478c70263340207'
FONT_FILE_NAME='FiraCodeNerdFontMono-Regular.ttf'

install_usage() {
    printf '%s\n' \
        'Usage: mainte install [--offline]' \
        '' \
        'Downloads the pinned FiraCode Nerd Font over HTTPS and verifies its checksum.' \
        'Use --offline to skip the download when the font is already installed.'
}

install_font() {
    _font_dir=${XDG_DATA_HOME:-${HOME:?HOME is not set}/.local/share}/fonts

    if has_command curl; then
        _download='curl'
    elif has_command wget; then
        _download='wget'
    else
        die 'install curl or wget, or use: mainte install --offline'
    fi
    if has_command sha256sum; then
        _checksum='sha256sum'
    elif has_command shasum; then
        _checksum='shasum -a 256'
    else
        die 'install sha256sum or shasum, or use: mainte install --offline'
    fi

    _temp=$(mktemp -d "${TMPDIR:-/tmp}/mainte-font.XXXXXX")
    trap 'rm -rf "$_temp"' EXIT
    trap 'exit 130' HUP INT TERM
    _archive=$_temp/FiraCode.tar.xz

    if [ "$_download" = curl ]; then
        curl --fail --location --silent --show-error --proto '=https' --tlsv1.2 \
            --output "$_archive" "$FONT_URL"
    else
        wget --https-only --quiet --output-document="$_archive" "$FONT_URL"
    fi

    # shellcheck disable=SC2086
    _actual=$($_checksum "$_archive" | awk '{ print $1 }')
    [ "$_actual" = "$FONT_SHA256" ] || die 'the downloaded font does not match the pinned checksum'

    tar -xJf "$_archive" -C "$_temp"
    _font=$(find "$_temp" -type f -name "$FONT_FILE_NAME" -print | sed -n '1p')
    [ -n "$_font" ] || die "the downloaded archive does not contain $FONT_FILE_NAME"

    mkdir -p "$_font_dir"
    cp "$_font" "$_font_dir/"
    if has_command fc-cache; then
        fc-cache -f "$_font_dir"
    fi
    printf 'Installed FiraCode Nerd Font Mono %s in %s\n' "$FONT_VERSION" "$_font_dir"
}

cmd_install() {
    _offline=0
    while [ "$#" -gt 0 ]; do
        case $1 in
            --offline) _offline=1 ;;
            -h|--help)
                install_usage
                return 0
                ;;
            *)
                install_usage >&2
                die "unknown option: $1"
                ;;
        esac
        shift
    done

    chmod 755 "$MAINTE_ROOT/mainte"

    if [ "$_offline" -eq 1 ]; then
        printf 'Skipped the font download (--offline).\n'
    else
        install_font
    fi

    if [ ! -e "$MAINTE_ROOT/mainte.local" ]; then
        cp "$MAINTE_ROOT/mainte.local.example" "$MAINTE_ROOT/mainte.local"
        printf 'Created mainte.local; edit it to use your own artwork and settings.\n'
    fi

    if has_command conky; then
        printf 'Ready. Start Mainte with: %s/mainte run\n' "$MAINTE_ROOT"
    else
        printf 'Install Conky with your package manager, then run: %s/mainte run\n' "$MAINTE_ROOT"
    fi
}
