# Lantern Out

Keep the village lanterns lit until dawn. One of your friends is blowing them out.

A social deduction party game for 4 to 10 players, built with Godot 4 for
Ubuntu. Design: [idea 14](https://github.com/kenvandine/game-ideas/blob/main/ideas/14-lantern-out.md)
in game-ideas.

## How a night plays

- **Lamplighters** do chores around Moonpatch Village and relight lanterns.
  Chores need a lit lantern nearby, so darkness slows the village down.
- One or two secret **Hollow** snuff lanterns and take villagers who wander
  into the dark. Hollow see each other.
- The **Seer** may look closely at one villager per night; the **Watchman**
  sees fresh footprints in the dark.
- Taken villagers become **ghosts**: they keep doing chores and may flicker
  one lantern each round as a silent hint.
- Find a friend's empty lantern, or ring the bell at the square, to call a
  meeting. Talk (out loud in the room, or with quick chat), then vote in secret.
- The village wins at dawn with enough chores done, or when every Hollow is
  banished. The Hollow win if they equal the villagers left, or if the village
  falls dark.

Every player sees only what their own light shows. The host sends each device
only what its character can see, so reading network traffic doesn't help.

## Playing

- **Play with bots**: a solo night on this device.
- **Host / Join on this network**: hosts are found automatically, or join
  with the host's code.
- **Play online**: through a [LinuxGroove game server](https://github.com/LinuxGroove/game-server).

Controls (controller first, keyboard always works):

| Action | Controller | Keyboard |
|---|---|---|
| Move | Left stick | WASD or arrows |
| Relight, chore, report | A | E, Space, Enter |
| Snuff or take (Hollow), look closely (Seer), flicker (ghost) | X | Q or F |
| Ring the bell | Y | R |
| Emotes | D-pad | 1 to 4 |
| Map | View / Back | Tab or M |
| Pause | Menu / Start | Esc |

Text fields open an on-screen keyboard when you press A on them.

## AI players

Bots move, do chores, snuff and take by themselves. In meetings they talk
and vote from what they actually saw. With a local language model they
speak in their own words; otherwise they use scripted lines. The snap
bundles [Lemonade Server](https://github.com/lemonade-sdk/lemonade) and
downloads a small model the first time bots need it (Qwen3 4B, about 2.5 GB,
or the lighter LFM2.5 1.2B in Settings). It runs privately on localhost and
only while you play. See [docs/ai-players.md](docs/ai-players.md).

## Building and testing

You need Godot 4.6.

```sh
godot --headless --path . --import
godot --headless --path . tools/check_scripts.tscn     # every script compiles
godot --headless --path . tests/run_tests.tscn -- --games=10   # unit tests and whole bot nights
godot --path . -- --solo --windowed                    # straight into a night with bots
```

The village is generated from the Kenney kits by `tools/build_village.gd`
(`godot --headless --path . -s tools/build_village.gd`).

## Snap

`snapcraft` builds a strictly confined snap, `lantern-out`, with the
exported game and the embedded Lemonade Server. It is packaged as a
regular desktop snap with the gnome extension, so it runs the same on an
Ubuntu desktop and on a handheld's gamepad shell. See [docs/packaging.md](docs/packaging.md).

## Layout

| Path | What |
|---|---|
| `game/` | Lantern Out itself: match rules and host, bots, actors, UI |
| `addons/linuxgroove/` | The shared LinuxGroove add-on (settings, input and glyphs, theme, LAN, online, local AI). Kept self-contained so it can move to its own repository |
| `addons/com.heroiclabs.nakama/` | Vendored Nakama client |
| `assets/kenney/` | Kenney packs (CC0) |
| `snap/` | Snap packaging |

Code is MIT (see `LICENSE`); assets and other credits in [CREDITS.md](CREDITS.md).
