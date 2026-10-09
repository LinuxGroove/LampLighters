# Screenshots

Every screen of Graveyard Hollow, made with:

    xvfb-run -a -s "-screen 0 1280x800x24" godot --path . --resolution 1280x800 tools/screenshot.tscn -- --all=docs/screenshots

The nights are staged by `tools/screenshot_gallery.gd`: it picks your role, places the bots and puts out lanterns where a shot needs the dark. Install `mesa-vulkan-drivers` first, so Godot renders with Vulkan as the game does rather than a paler OpenGL fallback.

## Menus and the lobby

**Choosing a name on the first run**

![Choosing a name on the first run](menus/first-name.jpg)

**The on-screen keyboard, for typing with a controller**

![The on-screen keyboard, for typing with a controller](menus/keyboard.jpg)

**The welcome, offering the tutorial and the practice round**

![The welcome, offering the tutorial and the practice round](menus/welcome.jpg)

**The title menu**

![The title menu](menus/title.jpg)

**How to play**

![How to play](menus/how-to-play.jpg)

**Tutorial page 1: The goal**

![Tutorial page 1: The goal](menus/tutorial-1.jpg)

**Tutorial page 2: A night in the village**

![Tutorial page 2: A night in the village](menus/tutorial-2.jpg)

**Tutorial page 3: Bells and meetings**

![Tutorial page 3: Bells and meetings](menus/tutorial-3.jpg)

**Tutorial page 4: How to win**

![Tutorial page 4: How to win](menus/tutorial-4.jpg)

**Tutorial page 5: Roles**

![Tutorial page 5: Roles](menus/tutorial-5.jpg)

**Tutorial page 6: Controls**

![Tutorial page 6: Controls](menus/tutorial-6.jpg)

**Tutorial page 6: Controls, on a keyboard**

![Tutorial page 6: Controls, on a keyboard](menus/tutorial-6-keyboard.jpg)

**Settings**

![Settings](menus/settings.jpg)

**About Graveyard Hollow**

![About Graveyard Hollow](menus/about.jpg)

**Local network play**

![Local network play](menus/local-network.jpg)

**Joining a game on the same network**

![Joining a game on the same network](menus/join.jpg)

**Play online**

![Play online](menus/online.jpg)

**The lobby for a game with bots: players, house rules and your look**

![The lobby for a game with bots: players, house rules and your look](menus/lobby.jpg)

**Changing a house rule**

![Changing a house rule](menus/lobby-setting.jpg)

**Hosting on the local network, with the join code at the top**

![Hosting on the local network, with the join code at the top](menus/lobby-lan.jpg)

## Moonpatch Village

**Moonpatch Village from above, every lantern lit**

![Moonpatch Village from above, every lantern lit](village/overview.jpg)

**Moonpatch Village from above, brightened to show the layout**

![Moonpatch Village from above, brightened to show the layout](village/overview-bright.jpg)

**The square**

![The square](village/square.jpg)

**The fountain**

![The fountain](village/fountain.jpg)

**The bell**

![The bell](village/bell.jpg)

**The chapel**

![The chapel](village/chapel.jpg)

**The graveyard**

![The graveyard](village/graveyard.jpg)

**The graveyard gate**

![The graveyard gate](village/graveyard-gate.jpg)

**The market**

![The market](village/market.jpg)

**The farm**

![The farm](village/farm.jpg)

**The broken fence**

![The broken fence](village/broken-fence.jpg)

**The hayfield**

![The hayfield](village/hayfield.jpg)

**The woodpile**

![The woodpile](village/woodpile.jpg)

**The campfire**

![The campfire](village/campfire.jpg)

**The houses**

![The houses](village/houses.jpg)

**The north houses**

![The north houses](village/north-houses.jpg)

**The old house**

![The old house](village/old-house.jpg)

**The square with every other lantern out**

![The square with every other lantern out](village/square-dark.jpg)

## A night

**A night begins: the clock, the village's chores and lanterns at the top, your chores on the right**

![A night begins: the clock, the village's chores and lanterns at the top, your chores on the right](play/night.jpg)

**Emotes on the d-pad**

![Emotes on the d-pad](play/emotes.jpg)

**The map: lanterns, your chores, and where you are**

![The map: lanterns, your chores, and where you are](play/map.jpg)

**The pause menu, with the controls shown**

![The pause menu, with the controls shown](play/pause.jpg)

**A one-time tip, the first time a lantern goes dark**

![A one-time tip, the first time a lantern goes dark](play/tip.jpg)

## Roles

**The Lamplighter's card**

![The Lamplighter's card](roles/lamplighter-card.jpg)

**Lamplighter: next to a dark lantern**

![Lamplighter: next to a dark lantern](roles/lamplighter-relight.jpg)

**Lamplighter: holding to relight it**

![Lamplighter: holding to relight it](roles/lamplighter-relighting.jpg)

**The Hollow's card, naming the other Hollow**

![The Hollow's card, naming the other Hollow](roles/hollow-card.jpg)

**Hollow: next to a lit lantern, with the other Hollow marked in red**

![Hollow: next to a lit lantern, with the other Hollow marked in red](roles/hollow-snuff.jpg)

**Hollow: the next snuff waits for its cooldown**

![Hollow: the next snuff waits for its cooldown](roles/hollow-cooldown.jpg)

**Hollow: a villager alone in the dark**

![Hollow: a villager alone in the dark](roles/hollow-take.jpg)

**Hollow: what's left after a take, for someone to find**

![Hollow: what's left after a take, for someone to find](roles/hollow-taken.jpg)

**The Seer's card**

![The Seer's card](roles/seer-card.jpg)

**Seer: next to a villager, ready to look closely**

![Seer: next to a villager, ready to look closely](roles/seer-look.jpg)

**Seer: what the look showed**

![Seer: what the look showed](roles/seer-result.jpg)

**The Watchman's card**

![The Watchman's card](roles/watchman-card.jpg)

**Watchman: fresh footprints show where someone just walked**

![Watchman: fresh footprints show where someone just walked](roles/watchman-footprints.jpg)

**Taken: you're a ghost now, and you learn who took you**

![Taken: you're a ghost now, and you learn who took you](roles/ghost-taken.jpg)

**Ghost: still doing chores, and next to a lantern to flicker as a hint**

![Ghost: still doing chores, and next to a lantern to flicker as a hint](roles/ghost-flicker.jpg)

**Ghost: the lantern flickers for everyone nearby**

![Ghost: the lantern flickers for everyone nearby](roles/ghost-flickering.jpg)

## Chores

**Your chore stations glow; walk up to one to start**

![Your chore stations glow; walk up to one to start](chores/station.jpg)

**Pump water at the fountain (tap quickly)**

![Pump water at the fountain (tap quickly)](chores/water.jpg)

**Mend the broken fence (tap in the green zone)**

![Mend the broken fence (tap in the green zone)](chores/fence.jpg)

**Feed the animals (hold)**

![Feed the animals (hold)](chores/animals.jpg)

**Light the chapel candles (press the directions in order)**

![Light the chapel candles (press the directions in order)](chores/candles.jpg)

**Stack the hay (hold)**

![Stack the hay (hold)](chores/hay.jpg)

**Bring wood to the campfire (hold)**

![Bring wood to the campfire (hold)](chores/wood.jpg)

**Carrying the wood to the campfire, the second step**

![Carrying the wood to the campfire, the second step](chores/wood-carry.jpg)

**Tidy the market stall (press the directions in order)**

![Tidy the market stall (press the directions in order)](chores/market.jpg)

**Dig at the old grave (tap quickly)**

![Dig at the old grave (tap quickly)](chores/grave.jpg)

**A station with no lit lantern nearby is too dark to work at**

![A station with no lit lantern nearby is too dark to work at](chores/too-dark.jpg)

## Meetings

**Finding a villager's dropped lantern in the dark**

![Finding a villager's dropped lantern in the dark](meetings/found.jpg)

**A meeting called by a report: bots say what they saw**

![A meeting called by a report: bots say what they saw](meetings/report.jpg)

**Quick chat: choosing who you suspect**

![Quick chat: choosing who you suspect](meetings/quick-chat.jpg)

**Quick chat: choosing where you saw them**

![Quick chat: choosing where you saw them](meetings/quick-chat-place.jpg)

**Voting, in secret**

![Voting, in secret](meetings/vote.jpg)

**Vote sent, waiting for the others**

![Vote sent, waiting for the others](meetings/voted.jpg)

**Banished, and they were Hollow**

![Banished, and they were Hollow](meetings/banished-hollow.jpg)

**At the bell in the square, ready to call a meeting**

![At the bell in the square, ready to call a meeting](meetings/bell-ring.jpg)

**A meeting called by the bell**

![A meeting called by the bell](meetings/bell.jpg)

**Banished, and they were not Hollow**

![Banished, and they were not Hollow](meetings/banished-villager.jpg)

**A tie: nobody is banished**

![A tie: nobody is banished](meetings/tie.jpg)

**Most chose to skip**

![Most chose to skip](meetings/skipped.jpg)

**With secret votes off, everyone sees who voted for whom**

![With secret votes off, everyone sees who voted for whom](meetings/open-votes.jpg)

**With role reveal off, a banished villager's role stays secret**

![With role reveal off, a banished villager's role stays secret](meetings/secret-role.jpg)

**A meeting seen by a ghost, who can't speak or vote**

![A meeting seen by a ghost, who can't speak or vote](meetings/ghost.jpg)

## Endings

**The village wins: every Hollow was found**

![The village wins: every Hollow was found](endings/village-found.jpg)

**The village wins at dawn with enough chores done**

![The village wins at dawn with enough chores done](endings/village-dawn.jpg)

**The Hollow win, seen by a Hollow: they outnumber the village**

![The Hollow win, seen by a Hollow: they outnumber the village](endings/hollow-outnumber.jpg)

**The Hollow win: the village fell dark**

![The Hollow win: the village fell dark](endings/hollow-dark.jpg)

**The Hollow win at dawn with too many chores undone**

![The Hollow win at dawn with too many chores undone](endings/hollow-dawn.jpg)

## The practice round

**The practice round starts: walk around**

![The practice round starts: walk around](practice/walk.jpg)

**Practice: the guide points at a dark lantern**

![Practice: the guide points at a dark lantern](practice/relight.jpg)

**Practice: the guide points at your next chore and says how its game works**

![Practice: the guide points at your next chore and says how its game works](practice/chores.jpg)

**Practice: open the map**

![Practice: open the map](practice/map.jpg)

**Practice: ring the bell to call a meeting**

![Practice: ring the bell to call a meeting](practice/bell.jpg)

**Practice: talk with quick chat, then vote**

![Practice: talk with quick chat, then vote](practice/meeting.jpg)

**The end of the practice round**

![The end of the practice round](practice/done.jpg)
