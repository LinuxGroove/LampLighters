# Graveyard Hollow

A social deduction game for 4–10 players (Lamplighters against the hidden Hollow), in Godot 4.7 with GDScript. The concept is idea 14 in [game-ideas](https://github.com/LinuxGroove/game-ideas/blob/main/ideas/14-graveyard-hollow.md). Online play goes through the shared [game server](https://github.com/LinuxGroove/game-server); **read game-ideas' [online-addon.md](https://github.com/LinuxGroove/game-ideas/blob/main/online-addon.md) before touching networking, online or the shared add-on.**

## Commands

```sh
godot --headless --path . --import
godot --headless --path . tools/check_scripts.tscn                  # every script compiles
godot --headless --path . tests/run_tests.tscn -- --games=10        # unit tests and whole bot nights
godot --path . -- --solo --windowed                                 # straight into a night with bots
xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --resolution 1280x800 tools/screenshot.tscn -- --all=docs/screenshots [group=meetings]
```

Run the script check and the tests before every commit. Headless runs reimport assets and rewrite many `*.glb.import` files and `icon.png.import`; revert those (`git checkout -- '*.import'`, `rm icon.png.import`) unless you meant to change them.

## Layout

| Path | What |
|---|---|
| `game/game_config.gd` | `GAME_ID`, `PROTOCOL`, player limits, `QUICK_MATCH_SIZE`, looks, setting defaults, input map |
| `game/net/session.gd` | `Session` autoload: lobby and transport for solo, LAN, online rooms and quick match |
| `game/net/online_server.gd` | Default game server; `SERVER_KEY` stays `defaultkey` in git |
| `game/match/` | Rules, `MatchHost` (the authoritative night), bot brains and bot talk |
| `game/ui/` | Title, lobby, HUD, meetings, pause menu, tutorial pages |
| `addons/linuxgroove/` | Shared LinuxGroove add-on (settings, input, theme, LAN, online, local AI, names) |
| `addons/com.heroiclabs.nakama/` | Vendored Nakama client with a local patch (see its `VENDORED.md`) |
| `tests/run_tests.gd` | Headless test runner; add checks with `check(ok, "what")` |
| `tools/` | Script checker, village builder, screenshots (`screenshot_gallery.gd` stages every shot in `docs/screenshots/`) |
| `docs/screenshots/<group>/` | Screenshots of every screen, made by `tools/screenshot.tscn -- --all=docs/screenshots`, with a README listing them |

## How the game is built

- **Host-authoritative.** Peer 1 runs the night (`MatchHost`); bots exist only on the host, with negative ids. Clients send requests (`_c_*` RPCs) and the host sends state (`_h_*`). The host sends each player only what that player may see, always with `rpc_id`: roles and positions in the dark must never reach other devices.
- **One Session for every mode.** Solo, LAN, online rooms and quick match all run the same game code. Follow the rules in online-addon.md: never attach the bridge's peer yourself, never send a second hello, no `await` between joining and setting `mode`.
- **Bump `PROTOCOL`** whenever any RPC's arguments or meaning change.
- **Online results** come from `Session.report_round` (host only, online rooms only, signed-in players only) to the server's `graveyard-hollow.round_report`, which writes stats and leaderboards. Changing what's reported means changing `modules/src/games/graveyard-hollow.ts` in game-server too, and deploying the server first.
- **Everything works offline.** No server, no network and online turned off must all still play.
- **Launch ping.** `game/main.gd` calls `LGLaunchPing.send(GameConfig.GAME_ID)` at startup: one anonymous request to the game server's `/launch` (game, random install id, version, OS, CPU) so the server counts every player, online or not. It's skipped headless, from source and with `DO_NOT_TRACK` set, and never blocks or retries.

## The shared add-on

`addons/linuxgroove/` and `addons/com.heroiclabs.nakama/` are copies shared with [Foam Frenzy](https://github.com/LinuxGroove/foam-frenzy) (usually checked out next to this repository). Fix shared behaviour in the add-on, not with a workaround here, keep it game-agnostic, and port the change to Foam Frenzy in the same piece of work. When the change affects how games should use the add-on, update online-addon.md in game-ideas too. Keep the `_disconnect_peer` and `_close` patch in `NakamaMultiplayerPeer.gd` when updating nakama-godot.

## Style

- Match the surrounding code: `##` doc comments on classes and non-obvious functions, short comments only where the reason isn't obvious.
- Screens connect to autoload signals with methods, not lambdas (a lambda stays connected after the screen is freed).
- Build UI pieces so tests can drive them without a network or a scene change.
- Player-facing text is plain and short, in the game's words (Lamplighters, the Hollow, nights, chores).

## Testing online

Prefer a local game server to `play.linuxgroove.com`, since test runs create real accounts and rooms. online-addon.md describes running one in LXD or Docker and the two-instance tests for joining by code and quick match. Device logs live in `~/snap/graveyard-hollow/current/.local/share/graveyard-hollow/logs/godot.log`.

## Releases

Pushing to `main` builds the snap and publishes it to the `edge` channel; a GitHub release publishes to `candidate`. The **Windows and macOS** workflow (`desktop.yml`) exports both from Linux with the `Windows Desktop` and `macOS` presets (a single `.exe`, and a universal, ad-hoc signed `.app`): pushes to `main` keep the zips as artifacts for 5 days, and releases get them attached. They aren't signed by Microsoft or Apple, and the release notes tell players how to open them. CI injects the server key from the `GAME_SERVER_KEY` secret, so never commit the real key.

Versions are `vYYYY.WW.MINOR`: a release is a GitHub release tagged with the year and week and a number from 0 for that week's releases (`v2026.41.0`, then `v2026.41.1`). Weeks run Sunday to Saturday (UTC), numbered like ISO weeks: a Sunday starts the ISO week of the Monday after it. Make releases with the **Release** workflow (Actions, Release, Run workflow): it refuses commits whose CI hasn't passed, picks the next tag, publishes a release whose notes lead with the Snap Store link and list the changes since the last release (`tools/release.sh`), and starts the snap build that publishes it to `candidate` and the Windows and macOS build that attaches those zips to the release. Commit subjects become the release notes, so write them for players. Nobody edits the version by hand: `tools/version.sh` derives it from git (`2026.41.0` on a tag, `2026.41.0+3.g1a2b3c4d` for the third commit after it), CI stamps it into `project.godot` before building, and runs from source ask the same script (`LGVersion`). The game sends it at sign-in, so the server's dashboard shows which versions are played.
