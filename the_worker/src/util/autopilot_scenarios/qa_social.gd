# qa_social.gd (escenario) — QA adversarial de §7-§8: rasgos y sobornos de los 23 nominados, utilidad por
# rango, percepción de Nate frente a George, rumor plantado en Debbie, ser visto, soborno a Tom y
# propagación en la cafetería.
# PROPIETARIO DE: nada (conduce al jugador; saltos de QA: teletransporte y reloj).
# ESCUCHA: señales de EventBus (solo para el registro).
extends Node

## tools/screenshot.sh /tmp/qa_social qa_social --seed=7
## Capturas: qa_social_01_rumour · 02_rumour_done · 03_seen · 04_tom_bribe · 05_tom_result · 06_after_lunch

const DEBBIE := "npc_debbie_foyle"
const GEORGE := "npc_george_penn"
const NATE := "npc_nate_brackley"
const CLAUDIA := "npc_claudia_reeves"
const TOM := "npc_tom_iverson"
const WING := "wing_3b"
const SHORT := 8

var _pilot: Autopilot = null
var _game: GameRoot = null
var _ops: Node = null


func run(pilot: Autopilot) -> void:
	_pilot = pilot
	GameLaunch.prepare_new_run("QA Social", "estandar", true, false)
	if not GameLaunch.start_game(get_tree()):
		push_error("qa_social: no game scene")
		return
	await pilot.frames(SHORT)
	_game = GameRoot.find(get_tree())
	if _game == null:
		push_error("qa_social: GameRoot missing")
		return
	# Reutiliza los ayudantes de conducción de social_ops (caminar, pulsar E, teclas).
	_ops = (load("res://src/util/autopilot_scenarios/social_ops.gd") as GDScript).new()
	add_child(_ops)
	_ops.set("_pilot", pilot)
	_ops.set("_game", _game)
	_hook_signals()
	PlayerState.add_money(3000, "qa")
	GameClock.advance_minutes(maxf(570.0 - GameClock.get_day_minutes(), 0.0))
	_audit_cast()
	_audit_utility()
	_audit_perception()
	await _rumour()
	await _get_seen()
	await _tom()
	await _lunch()
	_log("END money=%d susp=%.1f rep=%.1f" % [PlayerState.get_money(), PlayerState.get_suspicion(), PlayerState.get_reputation()])


func _hook_signals() -> void:
	EventBus.player_seen_partially.connect(func(n: String, c: float, r: String) -> void: _log("SIG seen_partially %s c=%.2f %s" % [n, c, r]))
	EventBus.player_caught_redhanded.connect(func(n: String, c: String, w: int) -> void: _log("SIG caught %s crime=%s w=%d" % [n, c, w]))
	EventBus.suspicion_changed.connect(func(a: float, b: float) -> void: _log("SIG suspicion %.1f -> %.1f" % [a, b]))
	EventBus.bribe_result.connect(func(n: String, ok: bool, o: String) -> void: _log("SIG bribe_result %s %s %s" % [n, ok, o]))
	EventBus.game_over.connect(func(c: String, e: String, _t: Dictionary) -> void: _log("SIG GAME_OVER %s %s" % [c, e]))


func _audit_cast() -> void:
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if Database.get_named_npc(npc.id) == null:
			continue
		var fair: int = Bribery.fair_price(npc, "look_away_once")
		var silence: int = Bribery.fair_price(npc, "silence_witnessed")
		var p: float = Bribery.acceptance_probability(npc, silence, "silence_witnessed")
		_log("CAST %s arch=%s traits=%s wage=%d look=%d silence=%d P(fair silence)=%.2f unbribable=%s reject=%s block=%s" % [
				npc.id, npc.archetype, str(npc.traits), Bribery.npc_daily_wage(npc), fair, silence, p,
				Bribery.is_npc_unbribable(npc), Bribery.rejection_outcome(npc.traits, silence, silence),
				SocialRules.bribe_block(npc)])


func _audit_utility() -> void:
	for id: String in [GEORGE, NATE, DEBBIE, TOM, "npc_bernard_lasker", "npc_rose_miller", "npc_alvin_pyne", "npc_frank_rudd", "npc_sonia_vail", "npc_ray_cudmore"]:
		var low: Dictionary = NPCDirector.decide(id, "belief", {"certainty": 0.9, "player_rank": 1})
		var high: Dictionary = NPCDirector.decide(id, "belief", {"certainty": 0.9, "player_rank": 28})
		_log("UTIL %s rank1=%s rank28=%s" % [id, str(low.get("action", low)), str(high.get("action", high))])


func _audit_perception() -> void:
	for id: String in [NATE, GEORGE, "npc_ray_cudmore"]:
		var perc: int = NPCDirector.get_effective_perception(id)
		_log("PERC %s eff=%d fill@4m walk=%.3f still=%.3f crouch=%.3f sprint=%.3f" % [id, perc,
				Perception.fill_rate(4.0, perc, "walk", false, false), Perception.fill_rate(4.0, perc, "still", false, false),
				Perception.fill_rate(4.0, perc, "walk", true, false), Perception.fill_rate(4.0, perc, "sprint", false, false)])


func _rumour() -> void:
	await _ops.call("_go", WING)
	var menu: NPCInteractionMenu = await _ops.call("_talk_to", DEBBIE)
	if menu == null:
		_log("FAIL no menu for Debbie")
		return
	if not menu.press_option(SocialRules.OPT_RUMOUR):
		_log("FAIL rumour option closed")
		return
	await _pilot.seconds(0.3)
	var choices: Array[Dictionary] = SocialRules.rumour_choices(DEBBIE)
	_log("rumour choices: %s" % str(choices.map(func(c: Dictionary) -> String: return "%s(%s)" % [c["id"], c["enabled"]])))
	await _pilot.shot("qa_social_01_rumour")
	var subject: String = CLAUDIA if choices.any(func(c: Dictionary) -> bool: return c["id"] == CLAUDIA) else str(choices[-1]["id"])
	menu.press_choice(subject)
	await _pilot.seconds(0.5)
	_log("reply: %s" % menu.get_reply_text())
	_log("injected: %s" % str(SocialGraph.get_injected_rumours()))
	await _pilot.shot("qa_social_02_rumour_done")
	await _ops.call("_key", KEY_ESCAPE)
	await _close_modals("after rumour")


func _close_modals(where: String) -> void:
	while _game.ui.has_modal():
		_log("modal open %s: %s" % [where, str(_game.ui.get_top_modal())])
		_game.ui.close_modal()
		await _pilot.frames(2)
	if NPCInteractionMenu.find(get_tree()) != null:
		await _ops.call("_key", KEY_ESCAPE)


## Entra en una sala vetada donde haya gente y se queda quieto dentro del campo de visión.
func _get_seen() -> void:
	var target: String = ""
	for room: RoomData in Database.get_all_rooms():
		if room.clearance_required > PlayerState.get_clearance() and not NPCDirector.get_npcs_in_room(room.id).is_empty():
			target = room.id
			break
	_log("forbidden room with people: %s" % target)
	if target.is_empty():
		return
	var before: float = PlayerState.get_suspicion()
	await _ops.call("_go", DatabaseSystem.get_room_base_id(target))
	var nodes: Array = _game.npc_layer.get_nodes()
	if not nodes.is_empty():
		var nearest: NPCNode = nodes[0]
		for n: NPCNode in nodes:
			if n.global_position.distance_to(_game.player.global_position) < nearest.global_position.distance_to(_game.player.global_position):
				nearest = n
		await _ops.call("_walk_to", _ops.call("_stand_point", nearest))
	for i: int in 8:
		await _pilot.seconds(0.5)
		var info: Array[String] = []
		for n: NPCNode in _game.npc_layer.get_nodes():
			var d: float = n.global_position.distance_to(_game.player.global_position) / RoomBuilder.cell_px()
			if d < 10.0 and n.get_perception() != null:
				info.append("%s d=%.1f c=%.2f st=%d sees=%s" % [n.npc_id, d, n.get_perception().get_counter(), n.get_perception().get_state(), n.get_perception().sees_point(_game.player.global_position)])
		_log("t=%.1f room=%s exposure=%s npcs=%s" % [i * 0.5, PlayerState.get_room(), str(Perception.assess_exposure(_game.player, PlayerState.get_room())), str(info)])
	await _pilot.shot("qa_social_03_seen")
	_log("seen: susp %.1f -> %.1f; beliefs about player=%d" % [before, PlayerState.get_suspicion(), BeliefNet.get_beliefs_about("player").size()])
	for row: Dictionary in BeliefNet.get_suspicion_breakdown():
		_log("  breakdown %s" % str(row))
	# §7.3: the proximity sense can now catch the trespass in the act; let the window run out.
	var caught: CaughtHandler = _game.sim_nodes.get("CaughtHandler") as CaughtHandler
	if caught != null and caught.is_window_open():
		_log("caught window after trespass: resolving by inaction -> %s" % str(caught.resolve_inaction()))
		await _pilot.frames(4)
	while _game.ui.has_modal():
		_log("modal open after being seen: %s" % str(_game.ui.get_top_modal()))
		_game.ui.close_modal()
		await _pilot.frames(2)


func _tom() -> void:
	var tom: NPCRuntime = NPCDirector.get_npc(TOM)
	var room: String = NPCDirector.get_current_location(TOM)
	_log("Tom location=%s home=%s" % [room, tom.home_room])
	await _ops.call("_go", DatabaseSystem.get_room_base_id(room if not room.is_empty() else tom.home_room))
	var menu: NPCInteractionMenu = await _ops.call("_talk_to", TOM)
	if menu == null:
		_log("FAIL Tom menu")
		return
	if not menu.press_option(SocialRules.OPT_LOOK):
		_log("FAIL look-away option closed")
		return
	await _pilot.seconds(0.3)
	var panel: BribePanel = menu.get_bribe_panel()
	if panel == null:
		_log("FAIL no bribe panel")
		return
	var fair: int = Bribery.fair_price(tom, "look_away_once")
	_log("Tom fair look_away=%d (manual: 210) susp=%.1f P=%.2f" % [fair, PlayerState.get_suspicion(), Bribery.acceptance_probability(tom, fair, "look_away_once")])
	panel.set_amount(fair)
	await _pilot.shot("qa_social_04_tom_bribe")
	panel.request_offer()
	panel.confirm_offer()
	await _pilot.seconds(0.6)
	_log("Tom result: %s" % str(panel.get_last_result()))
	_log("Tom ledger: %s" % str(NPCDirector.get_ledger(TOM)))
	for row: Dictionary in BeliefNet.get_suspicion_breakdown():
		_log("  breakdown after bribe %s" % str(row))
	if int(panel.get_last_result().get("asked_price", 0)) > 0:
		var tok: Dictionary = panel.get_last_result()["counteroffer"]
		var fair_now: int = Bribery.fair_price(tom, "look_away_once")
		_log("counteroffer check: asked=%d fair_now=%d min_valid=%d standing=%s" % [int(tok.get("asked_price", 0)), fair_now,
				Bribery.counteroffer_price(fair_now, 0.0), str(Bribery.standing_counteroffer(tom, "look_away_once", fair_now, {"counteroffer": tok}))])
		panel.accept_counteroffer()
		panel.confirm_offer()
		await _pilot.seconds(0.6)
		_log("Tom 2nd (pay counteroffer): %s paid=%s susp=%.1f" % [panel.get_last_result().get("outcome"), panel.get_last_result().get("paid"), PlayerState.get_suspicion()])
	await _pilot.shot("qa_social_05_tom_result")
	await _ops.call("_key", KEY_ESCAPE)
	await _close_modals("after Tom")


func _lunch() -> void:
	var fact_prefix: String = "%s:" % SocialKit.bs("rumor.hecho_colega")
	GameClock.advance_minutes(maxf(13.0 * 60.0 + 50.0 - GameClock.get_day_minutes(), 0.0))
	await _pilot.seconds(0.5)
	GameClock.advance_minutes(30.0)
	await _pilot.seconds(0.5)
	var holders: Array[String] = []
	var about_player: Dictionary = {}
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		for b: Belief in BeliefNet.get_beliefs_held_by(npc.id):
			if b.fact.begins_with(fact_prefix):
				holders.append("%s(%.2f)" % [npc.id, b.certainty])
			if b.subject == "player":
				about_player[npc.id] = "%s %.2f %s" % [b.fact, b.certainty, b.source]
	_log("rumour holders after lunch (%d): %s" % [holders.size(), str(holders)])
	_log("beliefs about player after lunch: %s" % str(about_player))
	_log("cafeteria session: %s" % str(SocialGraph.get_last_session("cafeteria_clan")))
	_log("George last decision: %s" % str(NPCDirector.get_last_decision(GEORGE)))
	await _go_floor()
	await _pilot.shot("qa_social_06_after_lunch")


func _go_floor() -> void:
	await _ops.call("_go", WING)


func _log(label: String) -> void:
	print("[qa_social] %s | %s" % [label, GameClock.get_time_string()])
