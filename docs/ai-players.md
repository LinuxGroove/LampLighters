# AI players

Empty seats in a lobby can be filled with bots. Every bot runs on the host,
which is the only machine that knows the roles, so a bot sees exactly what a
human in its seat would see and nothing more (`MatchHost.can_see`).

## Two layers

**Moving and acting** is always scripted, in `game/match/bot_brain.gd`. It
runs every frame and needs no model:

- Villagers walk to their chore stations, relight dark lanterns near their
  work, report remains they find and ring the bell when their suspicion of
  someone gets high.
- The Hollow snuff lanterns, wait in the dark near one they just put out,
  take a villager when nobody can see, then walk away from the body.
- Every bot remembers where it saw each player and when, which is what it
  talks about in meetings.

**Talking and voting** in meetings is `game/match/bot_talk.gd`. Up to four
bots speak in each meeting. When AI brains are on and the local model is
ready, a bot's turn is one chat request: a short prompt with its role, what it
remembers seeing and what has been said so far, asking for JSON
`{"say": "...", "vote": "<name or skip>"}`. If the model is off, still
loading, slow (12 s timeout) or returns something unusable, the bot falls back
to a scripted line built from the same memory. Games never wait on the model.

## The model server

The `LGBrain` autoload (`addons/linuxgroove/llm/brain_service.gd`) talks to
[Lemonade Server](https://github.com/lemonade-sdk/lemonade) through its
OpenAI-compatible API. Settings > AI picks the mode:

| Mode | What it does |
| --- | --- |
| auto (default) | Use the embedded server if the build has one, otherwise a Lemonade already running at the configured URL, otherwise scripted bots |
| embedded | Start the bundled `lemond` |
| external | Only use the configured URL (any OpenAI-compatible server) |
| off | Scripted bots only |

The embedded server is started only when a lobby with bots asks for it. It
listens on 127.0.0.1 on a random port with a random API key known only to the
game process, and it is stopped when the game exits. Nothing is reachable from
the network.

Models download on first use into `$SNAP_USER_COMMON/lemonade` (or the Godot
user data folder outside the snap), so they survive snap refreshes. The lobby
shows the download and loading progress.

## Memory

| Model | Download | RAM while loaded |
| --- | --- | --- |
| Qwen3-4B-Instruct-2507 (default) | about 2.5 GB | about 3.5 GB |
| LFM2.5-1.2B-Instruct (lighter) | about 0.8 GB | about 1.2 GB |

The game itself uses well under 1 GB, so the default model leaves plenty of
room on a 16 GB machine such as the Legion Go S. Machines with 8 GB should
pick the lighter model. Requests are short (a few hundred tokens out, 4096
context) and only one bot talks at a time, so CPU inference is fast enough
for meetings; a GPU backend is used when Lemonade finds one.

## Trying it without the snap

Run any Lemonade Server (or another OpenAI-compatible server) locally, set
Settings > AI > Mode to external and point the URL at it, for example
`http://127.0.0.1:8000/api/v1`.
