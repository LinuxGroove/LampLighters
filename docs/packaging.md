# Packaging

Graveyard Hollow ships as the strictly confined snap `graveyard-hollow`
(`snap/snapcraft.yaml`, core24, amd64).

## What the build does

1. **graveyard-hollow part**: downloads the Godot editor and export templates for
   the pinned version (`GODOT_VERSION` in the yaml, keep it in step with
   `project.godot`), imports the project and runs
   `--export-release Linux` with the preset in `export_presets.cfg`. The
   binary and `.pck` go to `$SNAP/game`, the launcher to `$SNAP/bin`.
2. **lemonade part**: unpacks the self-contained `lemonade-embeddable` release
   into `$SNAP/lemonade`. `lemond` downloads its llama.cpp backend as a
   `.tar.xz` at runtime and unpacks it with `tar` from `PATH`. GNU tar in the
   base can't run `xz` under confinement, so the part stages
   `libarchive-tools` and links `$SNAP/bin/tar` to `bsdtar`, and `$SNAP/bin`
   is first on `PATH`.
3. The app uses the **gnome extension**, which brings the GNOME runtime,
   Mesa through `gpu-2404`, and the desktop plugs (`wayland`, `x11`,
   `opengl`, `desktop`). The same snap runs on an Ubuntu desktop and on a
   handheld's gamepad shell.

Build locally with `snapcraft pack`. CI builds the snap on every push and
uploads it as an artifact (`.github/workflows/ci.yml`).

## Interfaces

The gnome extension's desktop plugs, plus `audio-playback`, `joystick`
(controllers), and `network` and `network-bind` (LAN games, discovery and
the local model server). `joystick` is not auto-connected on desktops:

```sh
sudo snap connect graveyard-hollow:joystick
```

## Where data lives

| What | Where |
| --- | --- |
| Settings, player name, logs and play test recordings | `$SNAP_USER_COMMON/.local/share/graveyard-hollow` |
| Downloaded AI models | `$SNAP_USER_COMMON/lemonade` |

Neither is copied for every revision. The launcher (`snap/local/graveyard-hollow`)
sets `XDG_DATA_HOME` (Godot's `user://`) to `$SNAP_USER_COMMON/.local/share`,
after the gnome extension points it at `$SNAP_USER_DATA`, and its first run
brings over what an older revision kept in `$SNAP_USER_DATA/.local/share`.

## Updating Godot or Lemonade

Change `GODOT_VERSION` (and the CI workflow's version) together, or the
Lemonade release URL. The embedded server is started with
`--host --port --no-broadcast <cache> <config>`; check the Lemonade release
notes if those flags change.
