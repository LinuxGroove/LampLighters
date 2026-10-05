# Packaging

Lantern Out ships as the strictly confined snap `lantern-out`
(`snap/snapcraft.yaml`, core24, amd64).

## What the build does

1. **lantern-out part**: downloads the Godot editor and export templates for
   the pinned version (`GODOT_VERSION` in the yaml, keep it in step with
   `project.godot`), imports the project and runs
   `--export-release Linux` with the preset in `export_presets.cfg`. The
   binary and `.pck` go to `$SNAP/game`, the launchers to `$SNAP/bin`.
2. **lemonade part**: unpacks the self-contained `lemonade-embeddable` release
   into `$SNAP/lemonade`. `lemond` downloads its llama.cpp backend as a
   `.tar.xz` at runtime and unpacks it with `tar` from `PATH`. GNU tar in the
   base can't run `xz` under confinement, so the part stages
   `libarchive-tools` and links `$SNAP/bin/tar` to `bsdtar`, and `$SNAP/bin`
   is first on `PATH`.
3. **gpu-2404 part**: Canonical's `gpu-2404-wrapper`, which sets up Mesa
   from the `mesa-2404` content snap and is in every app's command chain.

Build locally with `snapcraft pack`. CI builds the snap on every push and
uploads it as an artifact (`.github/workflows/ci.yml`).

## Interfaces

`wayland`, `x11`, `opengl`, `audio-playback`, `joystick` (controllers),
`network` and `network-bind` (LAN games, discovery and the local model
server), `desktop`. `joystick` is not auto-connected on desktops:

```sh
sudo snap connect lantern-out:joystick
```

## Kiosk mode (Ubuntu Core)

On Ubuntu Core with Ubuntu Frame, the game can run fullscreen as a service:

```sh
sudo snap install ubuntu-frame
sudo snap install lantern-out
sudo snap connect lantern-out:wayland ubuntu-frame:wayland
sudo snap connect lantern-out:joystick
sudo snap set lantern-out kiosk=true
```

`kiosk=false` stops and disables the service again. The `configure` hook does
the switching; the `kiosk` daemon is `install-mode: disable` so desktops never
start it.

## Where data lives

| What | Where |
| --- | --- |
| Settings and player name | `$SNAP_USER_DATA/.local/share/lantern-out` |
| Downloaded AI models | `$SNAP_USER_COMMON/lemonade` |

## Updating Godot or Lemonade

Change `GODOT_VERSION` (and the CI workflow's version) together, or the
Lemonade release URL. The embedded server is started with
`--host --port --no-broadcast <cache> <config>`; check the Lemonade release
notes if those flags change.
