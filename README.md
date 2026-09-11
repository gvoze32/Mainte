# Mainte

<p align="center">
  <img src="https://i.ibb.co/RHcqFLx/Screenshot-20191202-223118.png" alt="Mainte Conky theme">
</p>

Mainte is a simple, functional Conky theme inspired by
["conky-bandithijodotcom"](https://mega.nz/#!y8JTFAYD!siXwByZVpZAQUfpocT46M1aMRUP9Qfs5mjCnumCA-ew).

The base configuration is hardware-neutral. It does not assume a specific
laptop brand, Linux distribution, desktop environment, network interface,
battery slot, or CPU core count. Values that are not exposed by the system are
shown as `N/A` instead of making Conky fail.

## Features

- Host, user, distribution, kernel, uptime, GPU, display, and locale details.
- CPU model, top processes, memory, swap, storage, and network graphs.
- Automatic battery discovery (`BAT0`, `BAT1`, and other standard power-supply
  names).
- Fan and temperature discovery through `lm-sensors`, with a Linux `hwmon`
  fallback.
- A 1024-pixel overlay anchored to the top-right corner so the text and
  exploded-view artwork share the same coordinate system.
- Optional community-inspired extensions for media playback, Bluetooth, USB,
  Android, and NVIDIA GPU telemetry. Each extension is provider-based and
  disappears when its command is unavailable.

## Requirements

- Conky 1.10 or newer, running in an X11 session or a Wayland compositor with
  Conky layer-shell support.
- A POSIX shell plus the standard `awk`, `sed`, `cut`, `df`, and `uname`
  utilities.

The online font installer additionally requires `curl` or `wget`, `tar`, and
`sha256sum` or `shasum`.

Optional commands improve the values shown by the base theme:

| Command                  | Used for                                   |
| ------------------------ | ------------------------------------------ |
| `sensors` (`lm-sensors`) | Fan RPM and temperatures                   |
| `lspci` (`pciutils`)     | GPU model                                  |
| `xdpyinfo` or `xrandr`   | Display resolution                         |
| `acpi`                   | Battery fallback when sysfs is unavailable |

The optional extension overlay detects these providers independently:

| Command        | Extension                              |
| -------------- | -------------------------------------- |
| `playerctl`    | MPRIS media player and playback bar    |
| `bluetoothctl` | Connected Bluetooth devices            |
| `lsusb`        | USB device inventory                   |
| `adb`          | Connected Android devices              |
| `nvidia-smi`   | NVIDIA utilization, memory, temperature |

## Installation

Clone the repository and run one setup command:

```sh
git clone https://github.com/gvoze32/Mainte.git
cd Mainte
sh install.sh --start
```

`sh install.sh` prepares executable permissions and downloads the pinned
[FiraCode Nerd Font release](https://github.com/ryanoasis/nerd-fonts/releases/tag/v3.5.1)
over HTTPS, verifying its SHA-256 checksum before installing
`FiraCode Nerd Font Mono`. Add `--start` to launch Mainte immediately. The
runtime never downloads anything.

If the machine is offline, use `sh install.sh --offline --start`. Mainte then
uses the configured font fallback; you can change both Conky files' `font`
values to any locally installed monospace font, for example
`monospace:size=10`.

The launcher resolves its own directory, so the project does not need to be
copied to `~/.conky/Mainte`. To start Mainte with your desktop session, add
the absolute path to `conky-launch.sh` to your desktop environment's
autostart applications.

The launcher starts `conkyrc-dark-bg` and `conkyrc-dark-bspwm`. The latter
keeps its historical filename; it contains no bspwm-specific commands.

## Per-machine exploded wallpaper

The artwork is intentionally separate from the hardware data. Each laptop can
use its own exploded-view image without changing the global overlay:

```sh
./conky-launch.sh "$HOME/Pictures/thinkpad-t470-exploded.png"
```

The path may also be configured persistently:

```sh
cp mainte.local.example mainte.local
```

Then edit `MAINTE_WALLPAPER` in `mainte.local` to an absolute path or a path
relative to the repository, such as `wallpapers/t470.png`. `mainte.local` is
ignored by git. The launcher creates a runtime background config and symlink;
the tracked `bg.png` is never overwritten. The image is scaled to the
original `280x679` artwork area. Edit the `-s` value in `conkyrc-dark-bg` if
your asset uses a different aspect ratio.

## Aligning text to custom artwork

Use the interactive selector instead of editing the Conky text:

```sh
./mainte-layout.sh
```

Choose a named section (`Identity`, `Graphics`, `Locale`, `Performance`,
`Memory`, `Network`, `Battery`, or `Storage`), then move it up with `u`, down
with `d`, or enter an exact pixel offset with `n`. Positive values move a
section down; negative values move it up. Press `q` to save. The selector
writes the git-ignored `mainte.layout`; the launcher renders a temporary
configuration automatically.

Reset every section to the original positions with:

```sh
./mainte-layout.sh --reset
```

## Optional community extensions

Enable the portable subset inspired by
[modified-mainte](https://github.com/AyoItsYas/modified-mainte):

```sh
./conky-launch.sh --extensions
```

Or set `MAINTE_EXTRAS=1` in `mainte.local`. The extra overlay uses a bottom
anchor instead of fixed 1920x1080 coordinates. It only renders sections whose
provider exists, so installing every optional dependency is not required.
Provider-specific pieces from the fork that require fixed hardware, Python
packages, API keys, or laptop-specific daemons are deliberately not part of
the global default.

## Sensor setup

Install `lm-sensors` using your distribution's package manager and run
`sensors` once. If your distribution requires sensor detection, follow its
`sensors-detect` instructions. Mainte reads only values exposed by the
standard `sensors` output or Linux `hwmon` files.

Some firmware does not expose fan telemetry at all. In that case the correct
display is `N/A`; a Conky configuration cannot manufacture an RPM value. The
same fallback behavior applies to systems without a battery or temperature
sensor.

## Customization

Both base Conky files use the same `alignment`, `gap_x`, `gap_y`, and
1024-pixel window width. Change those settings in both files together when
repositioning the overlay. The main text is in `conkyrc-dark-bspwm`; the
artwork is in `conkyrc-dark-bg`.

To inspect the hardware adapter directly:

```sh
./mainte-sysinfo.sh fan
./mainte-sysinfo.sh temperature 1
./mainte-sysinfo.sh battery
./mainte-features.sh help
```

## Troubleshooting

- **Fan speed is `N/A`:** run `sensors` and check that a fan RPM value is
  exposed. If no fan value exists there, the kernel or firmware does not make
  it available.
- **Battery is `N/A`:** this is expected on desktops and systems that expose
  no battery through sysfs or `acpi`.
- **The network graph is empty:** Conky uses the default network interface.
  Check that the session has a default route and that Conky can access the
  display session.
- **The artwork and text overlap:** start Mainte through `conky-launch.sh` so
  both windows receive identical positioning. Use the wallpaper argument
  instead of editing the tracked artwork.
- **The extension overlay is not visible:** run
  `./mainte-features.sh available any`; `0` means no optional provider is
  installed. On short displays, the bottom-anchored panel may also be outside
  the visible area.
- **Permission denied:** run `chmod +x conky-launch.sh mainte-sysinfo.sh
  mainte-features.sh`.

## Credits

- [bandithijo](https://mega.nz/#!y8JTFAYD!siXwByZVpZAQUfpocT46M1aMRUP9Qfs5mjCnumCA-ew)
- [ThinkPad exploded-view vector source](https://www.reddit.com/r/thinkpad/search/?q=exploded%20wallpaper&restrict_sr=1)
- [AyoItsYas/modified-mainte](https://github.com/AyoItsYas/modified-mainte)
