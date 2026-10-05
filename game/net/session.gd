extends Node
## The lobby and transport for one play session (autoload: Session).
##
## Every mode runs the same host-authoritative game:
##   SOLO     this device hosts with bots, no network (OfflineMultiplayerPeer)
##   LAN      ENet on the local network, found by LanBeacon or a join code
##   ONLINE   Nakama relay through the shared game server, joined by room code
## Peer 1 is always the host. Bots get negative ids and exist only on the host.

signal roster_changed
signal settings_changed
signal hosts_found(hosts: Array)
signal joined
signal left(reason: String)
signal status(text: String)
## Host: a player's device has loaded the village and can receive the match.
signal peer_loaded(id: int)

enum Mode { NONE, SOLO, LAN_HOST, LAN_CLIENT, ONLINE_HOST, ONLINE_CLIENT }

const HELLO_TIMEOUT := 6.0

var mode := Mode.NONE
## actor id -> {"name", "look", "bot", "ready"}
var players := {}
var settings := Rules.DEFAULT_SETTINGS.duplicate()
var join_code := ""
var lan_address := ""
var in_match := false
var match_config := {}
## Host: peers whose game scene is ready, so match messages can reach them.
var loaded_peers := {}
var rounds_played := 0

var _beacon: LanBeacon
var _pending_hello := {}


func _ready() -> void:
	_beacon = LanBeacon.new()
	_beacon.name = "Beacon"
	add_child(_beacon)
	_beacon.hosts_changed.connect(func(h): hosts_found.emit(_filter_hosts(h)))
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)


func is_host() -> bool:
	return mode in [Mode.SOLO, Mode.LAN_HOST, Mode.ONLINE_HOST]


func local_id() -> int:
	return multiplayer.get_unique_id()


func player_name() -> String:
	var n := str(LGSettings.get_value("player", "name")).strip_edges()
	return n if n != "" else "Lamplighter"


func player_look() -> int:
	return int(LGSettings.get_value("player", "look"))


# --- Starting and joining ----------------------------------------------

func start_solo(bots := 5) -> void:
	leave()
	mode = Mode.SOLO
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	players = {1: _me()}
	for i in bots:
		add_bot()
	joined.emit()
	roster_changed.emit()


func host_lan() -> bool:
	leave()
	var port := int(LGSettings.get_value("lan", "port"))
	var peer := LanNet.create_host(port, GameConfig.MAX_PLAYERS - 1)
	if peer == null:
		status.emit("Couldn't host on port %d. Is another game already hosting?" % port)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_HOST
	players = {1: _me()}
	lan_address = LanNet.local_address()
	join_code = JoinCode.encode(lan_address, port, port) if lan_address != "" else ""
	_beacon.start_advertising(_beacon_info(), int(LGSettings.get_value("lan", "beacon_port")))
	joined.emit()
	roster_changed.emit()
	return true


func browse_lan() -> void:
	_beacon.start_listening(int(LGSettings.get_value("lan", "beacon_port")))


func stop_browsing() -> void:
	if mode == Mode.NONE:
		_beacon.stop()


func join_lan(address: String, port: int) -> bool:
	leave()
	var peer := LanNet.create_client(address, port)
	if peer == null:
		status.emit("Couldn't reach %s." % address)
		return false
	multiplayer.multiplayer_peer = peer
	mode = Mode.LAN_CLIENT
	status.emit("Connecting to %s..." % address)
	return true


func join_lan_code(code: String) -> bool:
	var port := int(LGSettings.get_value("lan", "port"))
	var target := JoinCode.decode(code, port)
	if target.is_empty():
		status.emit("That code doesn't look right.")
		return false
	return join_lan(target.ip, target.port)


func host_online() -> bool:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	var code: String = await LGOnline.host_room_async(GameConfig.GAME_ID)
	if code == "":
		status.emit(LGOnline.last_error)
		return false
	multiplayer.multiplayer_peer = LGOnline.bridge.multiplayer_peer
	mode = Mode.ONLINE_HOST
	join_code = code
	players = {1: _me()}
	joined.emit()
	roster_changed.emit()
	return true


func join_online(code: String) -> bool:
	leave()
	status.emit("Connecting to the game server...")
	if not await LGOnline.connect_async(player_name(), GameConfig.GAME_ID):
		status.emit(LGOnline.last_error)
		return false
	if not await LGOnline.join_room_async(GameConfig.GAME_ID, code):
		status.emit("No room with code %s." % code)
		return false
	multiplayer.multiplayer_peer = LGOnline.bridge.multiplayer_peer
	mode = Mode.ONLINE_CLIENT
	join_code = LGOnline.normalize_code(code)
	# The bridge reports the host as connected right away.
	_send_hello.call_deferred()
	return true


func leave(reason := "") -> void:
	var was := mode
	_beacon.stop()
	if mode in [Mode.ONLINE_HOST, Mode.ONLINE_CLIENT]:
		LGOnline.leave_room()
	if multiplayer.multiplayer_peer and not (multiplayer.multiplayer_peer is OfflineMultiplayerPeer):
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = OfflineMultiplayerPeer.new()
	mode = Mode.NONE
	players.clear()
	join_code = ""
	in_match = false
	match_config = {}
	loaded_peers.clear()
	rounds_played = 0
	_pending_hello.clear()
	if was != Mode.NONE:
		left.emit(reason)


# --- Host: lobby management ---------------------------------------------

func add_bot() -> void:
	if not is_host() or players.size() >= GameConfig.MAX_PLAYERS:
		return
	var id := -1
	while players.has(id):
		id -= 1
	var used_names := []
	var used_looks := []
	for p in players.values():
		used_names.append(p.name)
		used_looks.append(p.look)
	var name := "Bot"
	for n in GameConfig.BOT_NAMES:
		if not n in used_names:
			name = n
			break
	players[id] = {"name": name, "look": _free_look(used_looks), "bot": true}
	_broadcast_roster()


func remove_bot() -> void:
	if not is_host():
		return
	var bot_ids := players.keys().filter(func(k): return players[k].bot)
	if bot_ids.is_empty():
		return
	bot_ids.sort()
	players.erase(bot_ids[0])
	_broadcast_roster()


func set_setting(key: String, value: Variant) -> void:
	if not is_host():
		return
	settings[key] = value
	_broadcast_roster()


func can_start() -> bool:
	return is_host() and players.size() >= GameConfig.MIN_PLAYERS and not in_match


## Host: deals out the match and tells everyone to load the village.
func start_match() -> void:
	if not can_start():
		return
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var config := {
		"seed": rng.randi(),
		"players": players.duplicate(true),
		"settings": settings.duplicate(),
		"map": "res://game/world/moonpatch_village.tscn",
	}
	_beacon.update_info({"state": "playing"})
	loaded_peers.clear()
	for peer_id in multiplayer.get_peers():
		_h_start_match.rpc_id(peer_id, config)
	_h_start_match(config)


## Host: deals a fresh match with the same players.
func restart_match() -> void:
	if is_host():
		in_match = false
		start_match()


## Host of an online room: reports the round to the game server for stats
## and leaderboards. Bots aren't reported.
func report_round(result: Dictionary) -> void:
	if mode != Mode.ONLINE_HOST or LGOnline.bridge == null:
		return
	rounds_played += 1
	var players := []
	for id in result.players:
		if id <= 0 or result.players[id].get("bot", false):
			continue
		var uid := LGOnline.user_id_for_peer(id)
		if uid == "":
			continue
		players.append({
			"user_id": uid,
			"team": "hollow" if Rules.team_of(result.roles[id]) == Rules.Team.HOLLOW else "village",
			"survived": bool(result.players[id].alive),
		})
	LGOnline.rpc_async("%s.round_report" % GameConfig.GAME_ID, {
		"match_id": LGOnline.bridge.match_id,
		"round": rounds_played,
		"winner": "hollow" if int(result.winner) == Rules.Team.HOLLOW else "village",
		"players": players,
	})


## Host: everyone goes back to the lobby after a match.
func return_to_lobby() -> void:
	if not is_host():
		return
	_beacon.update_info({"state": "lobby"})
	for peer_id in multiplayer.get_peers():
		_h_return_to_lobby.rpc_id(peer_id)
	_h_return_to_lobby()


## Called by the game scene once it is in the tree. The host learns which
## peers are ready through Session (always present) rather than the game
## scene, which may not exist yet on the host when a fast client reports.
func report_loaded() -> void:
	if is_host():
		loaded_peers[1] = true
		peer_loaded.emit(1)
	else:
		_c_match_loaded.rpc_id(1)


func set_look(look: int) -> void:
	LGSettings.set_value("player", "look", look)
	if is_host():
		players[1].look = look
		_broadcast_roster()
	elif mode != Mode.NONE:
		_c_set_look.rpc_id(1, look)


# --- Network events -----------------------------------------------------

func _on_peer_connected(id: int) -> void:
	if is_host():
		_pending_hello[id] = Time.get_ticks_msec()
		get_tree().create_timer(HELLO_TIMEOUT).timeout.connect(func():
			if _pending_hello.has(id):
				_pending_hello.erase(id)
				_kick(id, "No hello from this game version."))


func _on_peer_disconnected(id: int) -> void:
	_pending_hello.erase(id)
	if is_host() and players.has(id):
		var name: String = players[id].name
		players.erase(id)
		_broadcast_roster()
		status.emit("%s left." % name)
		var game := get_tree().current_scene
		if in_match and game and game.has_method("on_player_left"):
			game.on_player_left(id)


func _on_connected_to_server() -> void:
	_send_hello()


func _send_hello() -> void:
	_c_hello.rpc_id(1, GameConfig.version(), GameConfig.PROTOCOL, player_name(), player_look())


func _on_connection_failed() -> void:
	status.emit("Couldn't connect to the host.")
	leave("Couldn't connect to the host.")


func _on_server_disconnected() -> void:
	leave("The host left the game.")


# --- RPCs ---------------------------------------------------------------

@rpc("any_peer", "reliable")
func _c_hello(version: String, protocol: int, name: String, look: int) -> void:
	if not is_host():
		return
	var id := multiplayer.get_remote_sender_id()
	_pending_hello.erase(id)
	if protocol != GameConfig.PROTOCOL:
		_kick(id, "This game is version %s. Update Lantern Out to play together." % GameConfig.version())
		return
	if in_match:
		_kick(id, "A night is already under way. Join after it ends.")
		return
	if players.size() >= GameConfig.MAX_PLAYERS:
		# Make room by removing a bot if possible.
		var bots := players.keys().filter(func(k): return players[k].bot)
		if bots.is_empty():
			_kick(id, "This game is full.")
			return
		players.erase(bots[0])
	var used_looks := []
	for p in players.values():
		used_looks.append(p.look)
	if look in used_looks:
		look = _free_look(used_looks)
	players[id] = {"name": _unique_name(name.strip_edges().left(16)), "look": look, "bot": false}
	_broadcast_roster()
	status.emit("%s joined." % players[id].name)


@rpc("any_peer", "reliable")
func _c_match_loaded() -> void:
	if is_host() and in_match:
		var id := multiplayer.get_remote_sender_id()
		loaded_peers[id] = true
		peer_loaded.emit(id)


@rpc("any_peer", "reliable")
func _c_set_look(look: int) -> void:
	var id := multiplayer.get_remote_sender_id()
	if is_host() and players.has(id):
		for k in players:
			if k != id and players[k].look == look:
				return
		players[id].look = clampi(look, 0, GameConfig.LOOKS.size() - 1)
		_broadcast_roster()


@rpc("authority", "reliable")
func _h_roster(p_players: Dictionary, p_settings: Dictionary, p_code: String) -> void:
	var first := players.is_empty()
	players = p_players
	settings = p_settings
	join_code = p_code
	if first:
		joined.emit()
	roster_changed.emit()
	settings_changed.emit()


@rpc("authority", "reliable")
func _h_kicked(reason: String) -> void:
	leave(reason)


@rpc("authority", "reliable")
func _h_start_match(config: Dictionary) -> void:
	in_match = true
	match_config = config
	LGScenes.change_scene("res://game/game.tscn", func(node): node.set("config", config))


@rpc("authority", "reliable")
func _h_return_to_lobby() -> void:
	in_match = false
	match_config = {}
	LGScenes.change_scene("res://game/ui/lobby.tscn")


func _broadcast_roster() -> void:
	if not is_host():
		return
	if mode != Mode.SOLO:
		for peer_id in multiplayer.get_peers():
			if not _pending_hello.has(peer_id):
				_h_roster.rpc_id(peer_id, players, settings, join_code)
	_beacon.update_info({"players": players.size()})
	roster_changed.emit()
	settings_changed.emit()


func _kick(id: int, reason: String) -> void:
	_h_kicked.rpc_id(id, reason)
	get_tree().create_timer(0.5).timeout.connect(func():
		if multiplayer.multiplayer_peer and multiplayer.multiplayer_peer.has_method("disconnect_peer"):
			multiplayer.multiplayer_peer.disconnect_peer(id))


func _me() -> Dictionary:
	return {"name": player_name(), "look": player_look(), "bot": false}


func _free_look(used: Array) -> int:
	for i in GameConfig.LOOKS.size():
		if not i in used:
			return i
	return 0


func _unique_name(name: String) -> String:
	if name == "":
		name = "Lamplighter"
	var names := []
	for p in players.values():
		names.append(p.name)
	var out := name
	var n := 2
	while out in names:
		out = "%s %d" % [name, n]
		n += 1
	return out


func _beacon_info() -> Dictionary:
	return {
		"game": GameConfig.GAME_ID,
		"version": GameConfig.version(),
		"protocol": GameConfig.PROTOCOL,
		"name": "%s's village" % player_name(),
		"port": int(LGSettings.get_value("lan", "port")),
		"players": players.size(),
		"max": GameConfig.MAX_PLAYERS,
		"state": "lobby",
		"code": join_code,
	}


func _filter_hosts(hosts: Array) -> Array:
	return hosts.filter(func(h): return str(h.get("game", "")) == GameConfig.GAME_ID)
