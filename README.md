# Mainte

<p align="center">
  <img src="https://i.ibb.co/RHcqFLx/Screenshot-20191202-223118.png" alt="Mainte Conky theme">
</p>

Mainte is a lightweight Conky theme in an exploded-view technical-drawing
style, inspired by
["conky-bandithijodotcom"](https://mega.nz/#!y8JTFAYD!siXwByZVpZAQUfpocT46M1aMRUP9Qfs5mjCnumCA-ew).

It works on any Linux laptop or desktop: the network interface, battery,
sensors, and CPU are detected at start-up, and anything the system does not
expose is shown as `N/A`. Bring your own exploded-view artwork and line the
text up with it without editing Conky files.

## Quick start

```sh
git clone https://github.com/gvoze32/Mainte.git
cd Mainte
./mainte install   # installs FiraCode Nerd Font Mono, creates mainte.local
./mainte run
```

`./mainte install --offline` skips the font download. For autostart, add
`/absolute/path/to/Mainte/mainte run` to your desktop's startup programs. The
`mainte` script may also be symlinked into `~/.local/bin`.

| Command                               | Effect                                              |
| ------------------------------------- | --------------------------------------------------- |
| `mainte run [--extensions] [IMAGE]`   | Start Mainte, or restart it if already running      |
| `mainte reload`                       | Apply edits to `mainte.local` and the layout        |
| `mainte stop`                         | Stop Mainte                                         |
| `mainte layout`                       | Align the text with the artwork interactively       |
| `mainte layout set ITEM PX` / `reset` | Same, non-interactively                             |

Conky output goes to `$XDG_RUNTIME_DIR/mainte-<uid>/conky.log`.

## Requirements

- Conky 1.10 or newer with Imlib2 (X11, or XWayland on Wayland).
- A POSIX shell and the standard `awk`, `sed`, `sort`, and `ps` utilities.
- For `mainte install`: `curl` or `wget`, `tar`, and `sha256sum` or `shasum`.

Optional commands that fill in more values:

| Command                         | Used for                        |
| ------------------------------- | ------------------------------- |
| `sensors` (`lm-sensors`)        | Fan RPM and temperatures        |
| `lspci` (`pciutils`)            | GPU model                       |
| `xdpyinfo` or `xrandr`          | Screen resolution               |
| `iwgetid`, `nmcli`, or `iw`     | Wi-Fi network name              |

Without `sensors`, fan and temperature values come from Linux `hwmon`; on
laptops whose firmware hides the fan RPM, `nbfc` (NoteBook FanControl) is
used to show the fan duty cycle instead.

## Your own artwork

Point Mainte at any PNG or JPEG for one session:

```sh
./mainte run ~/Pictures/thinkpad-t470-exploded.png
```

or permanently in `mainte.local` (git-ignored, created by `mainte install`):

```sh
MAINTE_WALLPAPER="~/Pictures/thinkpad-t470-exploded.png"
MAINTE_WALLPAPER_SIZE=280x679
```

All settings are optional:

| Setting                 | Default        | Meaning                                                      |
| ----------------------- | -------------- | ------------------------------------------------------------ |
| `MAINTE_WALLPAPER`      | `assets/bg.png`| Artwork; absolute, `~/…`, or relative to the Mainte folder   |
| `MAINTE_WALLPAPER_SIZE` | `280x679`      | Box the artwork is scaled to; match your image's aspect ratio|
| `MAINTE_GAP_X`          | `60`           | Artwork distance from the right screen edge                  |
| `MAINTE_GAP_Y`          | `40`           | Artwork distance from the top screen edge                    |
| `MAINTE_COLOR`          | `BEC8CB`       | Text and graph colour                                        |
| `MAINTE_NET_IFACE`      | detected       | Interface of the default route                               |
| `MAINTE_BATTERY`        | detected       | First system battery (`BAT0`, `CMB0`, …)                     |
| `MAINTE_EXTRAS`         | `0`            | `1` shows the extensions panel                               |
| `MAINTE_WEATHER`        | unset          | City for the extensions panel's weather row (via wttr.in)    |
| `MAINTE_LAYOUT_FILE`    | `mainte.layout`| Layout offsets; use one file per artwork if you switch often |

Run `./mainte reload` after editing. The network interface is detected at
start-up, so reload after switching between Wi-Fi and Ethernet.

## Aligning the text

The text column sits to the left of the artwork with its connector lines
reaching into it, exactly like the original layout. Different artwork needs
different positions:

```sh
./mainte layout
```

Pick an item, then type `+10` / `-10` to nudge it or `=25` to set it. While
Mainte is running every change is applied immediately.

- **Text column X / Y** move the whole text column (positive = right / down).
- **Identity, Graphics, Locale, Performance, Memory, Network, Battery,
  Storage** move one section up or down without moving the others.

Offsets are stored in `mainte.layout` (git-ignored). `./mainte layout reset`
returns to the original positions.

## Extensions panel

`./mainte run --extensions` (or `MAINTE_EXTRAS=1`) adds a bottom-right panel
with portable versions of the overlays from
[modified-mainte](https://github.com/AyoItsYas/modified-mainte). CPU
frequency and process counts, gateway, and DNS are always shown; the other
rows appear only when their provider exists:

| Row       | Provider                                    | Shows                                 |
| --------- | ------------------------------------------- | ------------------------------------- |
| Traffic   | `vnstat`                                    | Today's download and upload           |
| Weather   | `curl` or `wget`, and `MAINTE_WEATHER`      | Conditions and temperature, no API key |
| Media     | `playerctl`                                 | Track, position / length, progress    |
| Bluetooth | `bluetoothctl`                              | Connected devices and their battery   |
| USB       | `lsusb`                                     | Device count and names                |
| Android   | `adb`                                       | Connected phones                      |
| GPU       | `nvidia-smi`, or the `amdgpu` kernel driver | Load, VRAM, temperature               |

The fork's machine-specific parts (fixed 1920x1080 positions, hard-coded
drive and GPU models, Python helpers, `radeontop` and `usbguard` daemons, and
the OpenWeatherMap key) are intentionally left out.

## Troubleshooting

Inspect what Mainte detects:

```sh
sh providers/sysinfo.sh net-iface
sh providers/sysinfo.sh battery-name
sh providers/sysinfo.sh fan
sh providers/sysinfo.sh temperature 1
sh providers/features.sh available gpu
sh providers/features.sh dns
```

- **Fan speed is `N/A`:** the firmware exposes no fan RPM in `sensors` or
  `hwmon`; Conky cannot invent one.
- **Battery is `N/A`:** no system battery was found (expected on desktops).
- **Network graph is empty:** check `net-iface` above, or set
  `MAINTE_NET_IFACE` in `mainte.local`.
- **Boxes or wrong glyphs:** the font is missing; run `./mainte install`.
- **Nothing appears:** read the Conky log printed by `./mainte run`.

## Layout of this repository

| Path                    | Contents                                               |
| ----------------------- | ------------------------------------------------------ |
| `mainte`                | Command-line entry point                               |
| `lib/`                  | `install`, `run`/`reload`/`stop`, and `layout` commands |
| `conky/`                | Conky templates, rendered into the runtime directory   |
| `providers/`            | Hardware and extension adapters called by Conky        |
| `assets/`               | Default artwork (`bg.png`) and its GIMP source         |
| `mainte.local.example`  | Documented per-machine settings                        |

## Credits

- [bandithijo](https://mega.nz/#!y8JTFAYD!siXwByZVpZAQUfpocT46M1aMRUP9Qfs5mjCnumCA-ew)
- [ThinkPad exploded-view vector source](https://www.reddit.com/r/thinkpad/search/?q=exploded%20wallpaper&restrict_sr=1)
- [AyoItsYas/modified-mainte](https://github.com/AyoItsYas/modified-mainte)
