# interactions_social_case.gd — Cuerpo de test_interactions_social: reglas del módulo social sin escena (opciones y motivos, charla, trato por escalón, rumores, favores, sobornos entregados, chantaje, delegación, ideas, mérito regalado, eliminación sin testigos) y el menú no modal sobre la escena de juego real.
# PROPIETARIO DE: nada (monta y libera la escena de juego; su carpeta de guardado se borra al final).
# ESCUCHA: EventBus.crime_committed, npc_reported_player (solo para comprobar lo emitido).
extends TestCase

const GAME_SCENE := "res://scenes/world/game.tscn"
const MODULE := "res://src/world/interactions/social.gd"
const STORAGE_FORMAT := "user://test_interactions_social_%d"
const RUN_SEED := 5151
const FRAMES_SETTLE := 3
const WAIT_MS := 4000
const DEBBIE := "npc_debbie_foyle"
const GEORGE := "npc_george_penn"
const NATE := "npc_nate_brackley"
const CLAUDIA := "npc_claudia_reeves"
const RAY := "npc_ray_cudmore"
const SONIA := "npc_sonia_vail"
const BERNARD := "npc_bernard_lasker"
const AMELIA := "npc_amelia_cole"
const TOM := "npc_tom_iverson"
const FRANK := "npc_frank_rudd"
const IGGY := "npc_iggy_robbins"
const PLAYER := "player"
const ROOM := "wing_3b"
const RICH := 50000
const BIG_DEBT := 200

var _dir: String = ""
var _game: GameRoot = null
var _crimes: Array[Dictionary] = []
var _reports: Array[String] = []


func run_case() -> void:
	allowed_engine_errors = 0
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	SaveSystem.delete_run()
	GameRoot.spawn_audio = false
	MenuKit.spawn_audio = false
	check(new_run(RUN_SEED), "Database loaded")
	InteractionRouter.reset()
	check(InteractionRouter.register_module(load(MODULE) as Script), "social module honours the router contract")
	check_eq(InteractionRouter.handled_types_map().get("npc", ""), MODULE, "the social module claims 'npc'")
	SocialDeals.hook()
	EventBus.crime_committed.connect(func(crime: String, room: String, details: Dictionary) -> void:
		_crimes.append({"crime": crime, "room": room, "details": details}))
	EventBus.npc_reported_player.connect(func(npc_id: String, _t: String, _w: float, _l: String) -> void:
		_reports.append(npc_id))
	_test_options()
	_test_chat()
	_test_rank_lines()
	_test_rumours()
	_test_favours()
	_test_bribe_delivery()
	_test_blackmail()
	_test_ideas()
	_test_credit()
	_test_eliminate_rules()
	await _test_delegation()
	await _test_menu_scene()
	_cleanup()


# ─── Utilidades ───────────────────────────────────────────────

func _fresh() -> void:
	new_run(RUN_SEED)
	_crimes.clear()
	_reports.clear()


func _env(witnesses: Array[String] = [], cameras: Array[String] = []) -> Dictionary:
	return {"room_id": ROOM, "witnesses": witnesses, "cameras": cameras}


func _option(npc_id: String, option_id: String, env: Dictionary = {}) -> Dictionary:
	for opt: Dictionary in SocialRules.options(npc_id, env if not env.is_empty() else _env()):
		if str(opt["id"]) == option_id:
			return opt
	return {}


func _choice(option_id: String, npc_id: String, choice_id: String) -> Dictionary:
	for entry: Dictionary in SocialRules.choices(option_id, npc_id):
		if str(entry["id"]) == choice_id:
			return entry
	return {}


func _crime_seen(crime: String) -> bool:
	return _crimes.any(func(c: Dictionary) -> bool: return str(c["crime"]) == crime)


func _set_tier(tier: int) -> bool:
	for occupation: OccupationData in Database.get_occupations_by_tier(tier):
		PlayerState.set_occupation(occupation.id, "test")
		return PlayerState.get_tier() == tier
	return false


func _has_grievance(npc_id: String, kind: String) -> bool:
	for entry: Variant in NPCDirector.get_ledger(npc_id).get("grievances", []):
		if str((entry as Dictionary).get("type", "")) == kind:
			return true
	return false


func _has_favour(npc_id: String, kind: String) -> bool:
	for entry: Variant in NPCDirector.get_ledger(npc_id).get("favours", []):
		if str((entry as Dictionary).get("type", "")) == kind:
			return true
	return false


# ─── Opciones y motivos ───────────────────────────────────────

func _test_options() -> void:
	_fresh()
	var ids: Array[String] = []
	for opt: Dictionary in SocialRules.options(DEBBIE, _env()):
		ids.append(str(opt["id"]))
	for always: String in ["chat", "directions", "rumour", "favour", "bribe", "eliminate"]:
		check(ids.has(always), "options: '%s' is always offered" % always)
	for hidden: String in ["blackmail", "delegate", "cede_idea", "buy_idea", "credit", "look_away"]:
		check(not ids.has(hidden), "options: '%s' is hidden when it does not apply to Debbie" % hidden)
	check(bool(_option(DEBBIE, "chat")["enabled"]), "options: small talk is open")
	check_eq(str(_option(DEBBIE, "favour")["hint"]), TranslationServer.translate("SOCIAL_HINT_NO_DEBT"), "options: favour shows she owes you nothing")
	check(_option(TOM, "look_away").size() > 0, "options: a guard offers 'look the other way' (Tom Iverson)")
	check(_option(GEORGE, "credit").size() > 0, "options: George (loves recognition) offers 'give credit'")
	var iggy: Dictionary = _option(IGGY, "bribe")
	check(not bool(iggy["enabled"]) and str(iggy["reason"]) == TranslationServer.translate("SOCIAL_REASON_NO_CASH"),
			"options: Iggy Robbins does not take cash (favours only)")
	PlayerState.spend_money(PlayerState.get_money(), "test")
	check(not bool(_option(DEBBIE, "bribe")["enabled"]), "options: no money, no bribe (with its reason)")


# ─── Charla ───────────────────────────────────────────────────

func _test_chat() -> void:
	_fresh()
	var before: int = NPCDirector.get_affection(DEBBIE)
	var minute: float = GameClock.get_total_minutes()
	var res: Dictionary = SocialRules.perform("chat", "", DEBBIE, _env())
	check(bool(res["ok"]) and not (res["lines"] as Array).is_empty(), "chat: Debbie answers")
	check_eq(NPCDirector.get_affection(DEBBIE) - before, SocialKit.bi("charla.afecto"), "chat: affection rises by social.charla.afecto")
	check(GameClock.get_total_minutes() > minute, "chat: small talk costs clock minutes")
	check(not bool(_option(DEBBIE, "chat")["enabled"]), "chat: once per colleague and day (closed with its reason)")
	check(not bool(SocialRules.perform("chat", "", DEBBIE, _env())["ok"]), "chat: a second chat today does nothing")
	NPCDirector.add_affection(NATE, Database.get_balance_int("movil.afecto_minimo_contacto"))
	check(not PlayerState.has_contact(NATE), "chat: Nate's number is not known yet")
	SocialRules.perform("chat", "", NATE, _env())
	check_eq(PlayerState.get_contact_source(NATE), "proximity", "chat: a friendly chat gets the phone number (proximity)")
	_test_routine_hint()
	_test_ray_secret()


func _test_routine_hint() -> void:
	var next: Dictionary = SocialTalk.next_plan_entry(CLAUDIA)
	var notes: int = PlayerState.get_notebook_entries().size()
	var res: Dictionary = SocialTalk.chat(CLAUDIA)
	if next.is_empty():
		check(bool(res["ok"]), "routine: no later plan today, the chat still works")
		return
	var keys: Array = (res["lines"] as Array).map(func(line: Array) -> String: return str(line[0]))
	check(keys.has("SOCIAL_HINT_ROUTINE"), "routine: Claudia mentions where she'll be later")
	check(PlayerState.get_notebook_entries().size() > notes, "routine: the hint goes to the notebook")


func _test_ray_secret() -> void:
	var first: Dictionary = SocialTalk.chat(RAY)
	var keys: Array = (first["lines"] as Array).map(func(line: Array) -> String: return str(line[0]))
	check(not keys.has("SOCIAL_RAY_SECRET_1"), "Ray: no building secrets without his respect")
	NPCDirector.add_affection(RAY, SocialKit.bi("confidentes.npc_ray_cudmore.afecto_minimo"))
	GameClock.advance_to_next_day()
	var second: Dictionary = SocialTalk.chat(RAY)
	keys = (second["lines"] as Array).map(func(line: Array) -> String: return str(line[0]))
	check(keys.has("SOCIAL_RAY_SECRET_1"), "Ray: with respect, old Ray reveals a building secret (§8.3)")
	var toasts: Array = [str(second["toast_key"])]
	for extra: Variant in second.get("more_toasts", []):
		toasts.append(str(extra[0]))
	check(toasts.has("SOCIAL_TOAST_SECRET"), "Ray: the secret is announced (notebook)")


# ─── Trato por escalón (§6.4) ─────────────────────────────────

func _test_rank_lines() -> void:
	_fresh()
	var bernard: NPCRuntime = NPCDirector.get_npc(BERNARD)
	check_eq(SocialTalk.bucket(bernard), "t1", "rank: at tier 1 your wing chief ignores you / sends you for coffee")
	check(SocialTalk.directions(BERNARD, "desk")["lines"][0][0] == "SOCIAL_DIR_IGNORED", "rank: tier 1 — superiors don't give directions")
	check(str(SocialTalk.greeting(bernard)[0]).begins_with("SOCIAL_LINE_T1_"), "rank: tier-1 lines are chosen for a superior")
	if _set_tier(4):
		check_eq(SocialTalk.bucket(NPCDirector.get_npc(NATE)), "t4_peer", "rank: at tier 4 former peers flatter you")
	if _set_tier(8):
		var nate: NPCRuntime = NPCDirector.get_npc(NATE)
		check_eq(SocialTalk.bucket(nate), "top", "rank: at tier 8 nobody tells you the truth")
		var res: Dictionary = SocialTalk.directions(NATE, "desk")
		check(str(res["lines"][0][0]).begins_with("SOCIAL_LINE_TOP_") and str(res["toast_key"]) == "SOCIAL_TOAST_NO_TRUTH",
				"rank: at the top the answers are flattery, not information")
	_fresh()
	NPCDirector.add_affection(NATE, SocialKit.bi("lineas.afecto_hostil") - 10)
	check_eq(SocialTalk.bucket(NPCDirector.get_npc(NATE)), "hostile", "rank: the ledger turns the tone hostile")


# ─── Rumores (§7.7, §8.3) ─────────────────────────────────────

func _test_rumours() -> void:
	_fresh()
	var subjects: Array[String] = SocialRules.rumour_subjects(DEBBIE)
	if not check(not subjects.is_empty(), "rumour: Debbie has colleagues to talk about"):
		return
	var silk: int = PlayerState.get_tracking(TrackingSystem.AXIS_SILK)
	var res: Dictionary = SocialRules.perform("rumour", subjects[0], DEBBIE, _env())
	check(bool(res["ok"]), "rumour: planted with Debbie")
	var injected: Array[Dictionary] = SocialGraph.get_injected_rumours()
	check(not injected.is_empty() and str(injected.back()["target"]) == DEBBIE
			and str(injected.back()["fact"]) == "steals_ideas:" + subjects[0], "rumour: SocialGraph.inject_rumour about the colleague")
	check(_crime_seen("rumour_planted"), "rumour: it is the crime rumour_planted")
	check_eq(PlayerState.get_tracking(TrackingSystem.AXIS_SILK) - silk, 3, "rumour: silk +3 (Tracking)")
	check_eq(str(res["toast_key"]), "SOCIAL_TOAST_RUMOUR_SPREAD", "rumour: Debbie (gossip) will spread it everywhere")
	check(not bool(_option(DEBBIE, "rumour")["enabled"]), "rumour: one per person and day")
	var management: Dictionary = _choice("rumour", NATE, "management")
	var discontent: int = Company.get_discontent()
	if bool(management.get("enabled", false)):
		check(bool(SocialRules.perform("rumour", "management", NATE, _env())["ok"]) and Company.get_discontent() > discontent,
				"rumour: about management goes through Strike (discontent rises)")
	var sonia: Dictionary = SocialRules.perform("rumour", NATE, SONIA, _env())
	check_eq(str(sonia["toast_key"]), "SOCIAL_TOAST_RUMOUR_DEAD", "rumour: Sonia (rookie, no links) tells nobody")


# ─── Favores a cuenta de la deuda ─────────────────────────────

func _test_favours() -> void:
	_fresh()
	check(not bool(_choice("favour", NATE, "alibi")["enabled"]), "favour: no debt, no alibi")
	NPCDirector.add_debt(NATE, BIG_DEBT)
	check(not bool(_choice("favour", NATE, "alibi")["enabled"]), "favour: no open case, nothing to cover")
	var case_id: String = Security.open_investigation("object_missing", 1, "hr_office")
	var debt: int = NPCDirector.get_debt(NATE)
	check(bool(SocialRules.perform("favour", "alibi", NATE, _env())["ok"]), "favour: Nate agrees to cover for you")
	check_eq(str(Security.get_alibi(case_id).get("provider", "")), NATE, "favour: Security records Nate's alibi in the case")
	check_eq(debt - NPCDirector.get_debt(NATE), SocialDeals.cost("alibi"), "favour: the alibi costs debt")
	check(bool(SocialRules.perform("favour", "lend", NATE, _env())["ok"]), "favour: Nate lends you his card")
	var card: ItemData = null
	for item: ItemData in PlayerState.get_inventory():
		if item.id == SocialKit.bs("prestamo.tarjeta"):
			card = item
	check(card != null and str(card.extra.get("owner", "")) == NATE, "favour: the lent card carries Nate's name")
	_test_frank()
	_test_look_away()


## Frank Rudd presta el uniforme de mantenimiento por una miseria (§8.3), sin deuda.
func _test_frank() -> void:
	var money: int = PlayerState.get_money()
	var lend: Dictionary = _choice("favour", FRANK, "lend")
	check(bool(lend.get("enabled", false)), "Frank: he lends without owing you anything")
	check(bool(SocialRules.perform("favour", "lend", FRANK, _env())["ok"]), "Frank: lends the maintenance uniform")
	check_eq(money - PlayerState.get_money(), SocialKit.bi("prestamo.precio_especial"), "Frank: for a pittance")
	check(PlayerState.has_item("uniform_maintenance"), "Frank: the uniform is in the inventory")
	check_eq(PlayerState.get_disguise(), "uniform_maintenance", "Frank: and you are wearing it")


func _test_look_away() -> void:
	NPCDirector.set_current_location(TOM, NPCDirector.get_npc(TOM).home_room)
	var before: String = NPCDirector.get_current_location(TOM)
	check(not SocialDeals.break_room_for(NPCDirector.get_npc(TOM)).is_empty(), "look away: Tom has somewhere to slip off to")
	NPCDirector.add_debt(TOM, BIG_DEBT)
	check(bool(SocialRules.perform("favour", "look_away", TOM, _env())["ok"]), "look away: Tom takes a coffee break")
	var after: String = NPCDirector.get_current_location(TOM)
	check(after != before and not after.is_empty(), "look away: Tom leaves his post (%s → %s)" % [before, after])


# ─── Sobornos aceptados: entrega en el mundo ──────────────────

func _test_bribe_delivery() -> void:
	_fresh()
	PlayerState.add_money(RICH, "test")
	var tom: NPCRuntime = NPCDirector.get_npc(TOM)
	var price: int = Bribery.fair_price(tom, "look_away_once")
	check(price > 0 and price <= Bribery.base_price(Bribery.npc_daily_wage(tom), "look_away_once") * 2,
			"bribe: Tom's look-away is the cheap favour (%d €)" % price)
	NPCDirector.set_current_location(TOM, tom.home_room)
	var before: String = NPCDirector.get_current_location(TOM)
	var res: Dictionary = Bribery.offer(tom, price, "look_away_once", Bribery.CHANNEL_IN_PERSON,
			{"room_id": ROOM, "witnesses": [NATE], "cameras": [], "roll": 0.0})
	check(bool(res["accepted"]), "bribe: Tom accepts in person")
	check(NPCDirector.get_current_location(TOM) != before, "bribe: the accepted look-away is delivered (he leaves his post)")
	check(bool(Bribery.offer(tom, price, "look_away_once", Bribery.CHANNEL_IN_PERSON, {"room_id": ROOM, "witnesses": [NATE], "roll": 0.0})["ok"]),
			"bribe: in person works with witnesses around")
	var witnessed: bool = BeliefNet.get_beliefs_held_by(NATE).any(func(b: Belief) -> bool: return b.fact == Bribery.FACT_WITNESSED)
	check(witnessed, "bribe: a witness of an in-person bribe believes it (witness risk)")
	var frank: NPCRuntime = NPCDirector.get_npc(FRANK)
	Bribery.offer(frank, Bribery.fair_price(frank, "lend_access") * 2, "lend_access", Bribery.CHANNEL_MOBILE_CHAT, {"roll": 0.0})
	check(PlayerState.has_item("uniform_maintenance"), "bribe: a paid 'lend access' hands over the loan (Frank's uniform)")


# ─── Chantaje ─────────────────────────────────────────────────

func _blackmail_file(npc_id: String) -> void:
	var src: ItemData = InventoryRules.make_item("blackmail_file")
	var doc: ItemData = ItemData.make(src.id, src.name_key, src.category)
	doc.extra = {"npc_id": npc_id, "stackable": false}
	PlayerState.add_item_data(doc)


func _test_blackmail() -> void:
	_fresh()
	check(_option(GEORGE, "blackmail").is_empty(), "blackmail: no material, no option")
	_blackmail_file(GEORGE)
	check(not _option(GEORGE, "blackmail").is_empty(), "blackmail: George's HR note makes it possible")
	check(not (_choice("blackmail", GEORGE, "money").get("confirm", {}) as Dictionary).is_empty(), "blackmail: every demand asks for confirmation")
	var money: int = PlayerState.get_money()
	var fear: int = NPCDirector.get_fear(GEORGE)
	var res: Dictionary = SocialRules.perform("blackmail", "money", GEORGE, _env())
	check(bool(res["ok"]) and PlayerState.get_money() > money, "blackmail: George pays up")
	check(NPCDirector.get_fear(GEORGE) > fear and _has_grievance(GEORGE, "blackmailed"), "blackmail: fear and a permanent grievance")
	check(not bool(_option(GEORGE, "blackmail")["enabled"]), "blackmail: George cannot be squeezed again at once")
	_blackmail_file(BERNARD)
	var brave: Dictionary = SocialRules.perform("blackmail", "silence", BERNARD, _env())
	check(not bool(brave["ok"]) and _reports.has(BERNARD), "blackmail: brave Bernard refuses and reports you")
	PlayerState.grant_full_file(CLAUDIA, "hr_intrusion")
	check(not SocialLeverage.material_on(CLAUDIA).is_empty(), "blackmail: a secret read in her full file is material")
	check(not bool(_choice("blackmail", CLAUDIA, "promotion").get("enabled", true)), "blackmail: promotion help only from someone above you")


# ─── Ideas (§11.1) ────────────────────────────────────────────

func _test_ideas() -> void:
	_fresh()
	check(_option(CLAUDIA, "cede_idea").is_empty(), "ideas: no idea, no idea options")
	var idea_id: String = IdeaPool.generate_idea(CLAUDIA, "general")
	if not check(not idea_id.is_empty(), "ideas: Claudia has an idea"):
		return
	check(not bool(_option(CLAUDIA, "cede_idea")["enabled"]), "ideas: she won't hand it over without a debt")
	NPCDirector.add_debt(CLAUDIA, Database.get_balance_int("ideas.deuda_minima_cesion"))
	check(bool(SocialRules.perform("cede_idea", "", CLAUDIA, _env())["ok"]), "ideas: with a high debt she gives it away")
	check_eq(IdeaPool.get_idea(idea_id).acquisition_method, "gifted", "ideas: acquired as 'gifted' (no trace)")
	PlayerState.add_money(RICH, "test")
	var amelia_idea: String = IdeaPool.generate_idea(AMELIA, "general")
	var amelia: NPCRuntime = NPCDirector.get_npc(AMELIA)
	var idea: Idea = IdeaPool.get_idea(amelia_idea)
	check(SocialLeverage.idea_price(amelia, idea, true) > SocialLeverage.idea_price(amelia, idea, false), "ideas: the generous offer costs more")
	var money: int = PlayerState.get_money()
	var refused: Dictionary = SocialRules.perform("buy_idea", "generous", AMELIA, _env())
	check(not bool(refused["ok"]) and PlayerState.get_money() == money, "ideas: incorruptible Amelia never sells (no money spent)")
	check(_crime_seen("bribe"), "ideas: a purchase offer is a bribe (crime_committed)")
	var ernie_idea: String = IdeaPool.generate_idea(GEORGE, "general")
	var bought: Dictionary = SocialRules.perform("buy_idea", "fair", GEORGE, _env())
	var got: bool = IdeaPool.get_idea(ernie_idea).acquired_by == PLAYER
	check(bool(bought["ok"]) == got and got == (PlayerState.get_money() < money), "ideas: a sale spends the money and gives you the idea (or neither)")


# ─── Mérito regalado (George Penn, §8.3) ──────────────────────

func _test_credit() -> void:
	_fresh()
	PlayerState.modify_reputation(SocialKit.bf("credito.coste_reputacion") * 4.0, "test")
	var rep: float = PlayerState.get_reputation()
	var opt: Dictionary = _option(GEORGE, "credit")
	check(not (opt.get("confirm", {}) as Dictionary).is_empty(), "credit: giving credit asks for confirmation")
	check(bool(SocialRules.perform("credit", "", GEORGE, _env())["ok"]), "credit: George takes the credit")
	check(_has_favour(GEORGE, "credit_given"), "credit: a favour in his ledger")
	check(NPCDirector.get_debt(GEORGE) >= SocialKit.bi("credito.deuda"), "credit: he owes you (neutralised for a while)")
	check(PlayerState.get_reputation() < rep, "credit: it costs a bit of your reputation")
	check(not bool(_option(GEORGE, "credit")["enabled"]), "credit: not again for a few days")


# ─── Eliminación: la regla de §12.2 ───────────────────────────

func _test_eliminate_rules() -> void:
	_fresh()
	var watched: Dictionary = _option(NATE, "eliminate", _env([DEBBIE] as Array[String]))
	check(not bool(watched["enabled"]) and bool(watched["red"]), "eliminate: disabled and red with a witness")
	var filmed: Dictionary = _option(NATE, "eliminate", _env([] as Array[String], ["cam_x"] as Array[String]))
	check(not bool(filmed["enabled"]) and bool(filmed["red"]), "eliminate: disabled and red under a camera")
	check(not bool(SocialRules.perform("eliminate", "", NATE, _env([DEBBIE] as Array[String]))["ok"]) and NPCDirector.is_active(NATE),
			"eliminate: the rule is enforced in logic too (nobody dies with witnesses)")
	var clear: Dictionary = _option(NATE, "eliminate")
	check(bool(clear["enabled"]) and bool(clear["danger"]), "eliminate: open (and flagged dangerous) with nobody watching")
	var res: Dictionary = SocialRules.perform("eliminate", "", NATE, _env())
	check(bool(res["ok"]) and bool(res["close"]), "eliminate: done; the menu closes")
	check(not NPCDirector.is_alive(NATE) and not NPCDirector.get_body_info(NATE).is_empty(), "eliminate: removed as 'eliminated' with a body")
	check(_crime_seen("elimination"), "eliminate: crime_committed('elimination')")


# ─── Delegación (§10.5) ───────────────────────────────────────

func _test_delegation() -> void:
	_fresh()
	var ds: DutySystem = DutySystem.new()
	add_child(ds)
	await wait_frames(1)
	check(_option(NATE, "delegate").is_empty(), "delegate: not below tier 4")
	var sub_id: String = ""
	for tier: int in [4, 5, 6]:
		if _set_tier(tier) and not ds.get_subordinates().is_empty():
			sub_id = ds.get_subordinates()[0].id
			break
	if not check(not sub_id.is_empty(), "delegate: a tier-4+ post with subordinates"):
		ds.queue_free()
		return
	check(not _option(sub_id, "delegate").is_empty(), "delegate: offered to a subordinate at tier %d" % PlayerState.get_tier())
	var duties: Array[Dictionary] = SocialRules.choices("delegate", sub_id)
	if duties.is_empty():
		check(not bool(_option(sub_id, "delegate")["enabled"]), "delegate: no delegable duty → closed with its reason")
	else:
		var res: Dictionary = SocialRules.perform("delegate", str(duties[0]["id"]), sub_id, _env())
		check(bool(res["ok"]), "delegate: the subordinate takes the duty")
		check(_has_grievance(sub_id, "overworked"), "delegate: the subordinate resents it (grievance)")
	ds.queue_free()
	await wait_frames(1)


# ─── Menú en la escena real ───────────────────────────────────

func _spawn_game() -> GameRoot:
	var game: GameRoot = (load(GAME_SCENE) as PackedScene).instantiate() as GameRoot
	game.request_overrides = {"mode": "new", "seed": RUN_SEED, "player_name": "Sam Social", "skip_intro": true}
	game.epilogue_delay_override = 0.0
	get_tree().root.add_child(game)
	get_tree().current_scene = game
	game.travel.instant = true
	game.time_skip.instant = true
	game.promotion.instant = true
	game.bridges.instant = true
	await _settle()
	return game


func _settle() -> void:
	for i: int in FRAMES_SETTLE:
		await get_tree().physics_frame
	await get_tree().process_frame


func _wait(condition: Callable) -> bool:
	var deadline: int = Time.get_ticks_msec() + WAIT_MS
	while Time.get_ticks_msec() < deadline:
		if bool(condition.call()):
			return true
		await get_tree().process_frame
	return bool(condition.call())


## Un personaje con nodo en la planta, el jugador a su lado y la capa congelada (nadie se mueve).
func _talk_target() -> NPCNode:
	_game.travel.teleport_to_room(ROOM)
	await _settle()
	_game.npc_layer.sync_now()
	var nodes: Array[NPCNode] = _game.npc_layer.get_nodes()
	if nodes.is_empty():
		return null
	var target: NPCNode = nodes[0]
	_game.npc_layer.process_mode = Node.PROCESS_MODE_DISABLED
	for node: NPCNode in nodes:
		node.process_mode = Node.PROCESS_MODE_DISABLED
	var spot: Vector2 = _game.streamer.nearest_walkable_point(target.global_position + Vector2.RIGHT * RoomBuilder.cell_px())
	_game.player.global_position = spot if spot.is_finite() else target.global_position
	await _settle()
	return target


func _test_menu_scene() -> void:
	SocialKit.qa_instant = true
	_game = await _spawn_game()
	var target: NPCNode = await _talk_target()
	if not check(target != null, "scene: a colleague stands next to the player"):
		return
	var ctx: Dictionary = InteractionRouter.build_context(target.interactable, _game.player)
	check_eq(InteractionRouter.prompt_key_for(target.interactable), "UI_INTERACT_NPC", "scene: the prompt says 'Talk'")
	SocialInteractions.interact(target.interactable, _game.player, ctx)
	var menu: NPCInteractionMenu = NPCInteractionMenu.find(get_tree())
	if not check(menu != null, "scene: E opens the conversation menu"):
		return
	await _settle()
	check(not _game.ui.has_modal() and not GameClock.is_paused_by(UIRoot.UI_PAUSE_OWNER), "scene: not a modal — the world keeps running")
	check(_game.player.is_input_locked(), "scene: the player stands still while talking")
	check(not menu.get_reply_text().is_empty(), "scene: the colleague greets you (rank-dependent line)")
	await _menu_card(menu, target)
	await _menu_keys(menu)
	await _menu_witness(menu, target)
	await _menu_chat(menu, target)
	await _menu_walk_away(target)
	await _menu_eliminate(target)
	SocialKit.qa_instant = false


func _menu_card(menu: NPCInteractionMenu, target: NPCNode) -> void:
	menu.call("_open_card")
	await _settle()
	var card: CharacterCard = _game.npc_layer.get_card()
	check(card != null and card.npc_id == target.npc_id, "scene: the header opens the quick card (§13.7)")
	_game.npc_layer.close_card()


func _press_key(keycode: Key) -> void:
	for pressed: bool in [true, false]:
		var event: InputEventKey = InputEventKey.new()
		event.keycode = keycode
		event.physical_keycode = keycode
		event.pressed = pressed
		Input.parse_input_event(event)
		await get_tree().process_frame
	await _settle()


## Teclado real: el número abre la opción, Esc vuelve a la lista principal.
func _menu_keys(menu: NPCInteractionMenu) -> void:
	await _press_key(KEY_2)
	check_eq(menu.get_page(), NPCInteractionMenu.PAGE_CHOICES, "keys: '2' opens the directions submenu")
	await _press_key(KEY_ESCAPE)
	check(is_instance_valid(menu) and menu.get_page() == NPCInteractionMenu.PAGE_MAIN, "keys: Esc goes back to the main list")
	check(not _game.ui.has_modal(), "keys: Esc inside the menu does not open the pause menu")


## Alejarse (o que el otro se aleje) termina la conversación con un aviso.
func _menu_walk_away(target: NPCNode) -> void:
	SocialInteractions.interact(target.interactable, _game.player, InteractionRouter.build_context(target.interactable, _game.player))
	await _settle()
	check(NPCInteractionMenu.find(get_tree()) != null, "walk away: the menu is open again")
	var here: Vector2 = target.global_position
	target.global_position = here + Vector2.RIGHT * SocialWorld.talk_range_px() * 3.0
	check(await _wait(func() -> bool: return NPCInteractionMenu.find(get_tree()) == null), "walk away: out of talking range the menu closes")
	target.global_position = here
	await _settle()


## Un segundo compañero junto al jugador: «Eliminar» se apaga y se pone en rojo en vivo.
func _menu_witness(menu: NPCInteractionMenu, target: NPCNode) -> void:
	var holder: NPCNode = null
	for node: NPCNode in _game.npc_layer.get_nodes():
		if node != target:
			holder = node
			break
	if not check(holder != null, "scene: a second person for the witness test"):
		return
	holder.global_position = _game.player.global_position + Vector2.LEFT * RoomBuilder.cell_px()
	await _settle()
	var watched: bool = await _wait(func() -> bool:
		return not (menu.get_exposure().get("witnesses", []) as Array).is_empty())
	var row: Dictionary = {}
	for entry: Dictionary in menu.get_entries():
		if str(entry["id"]) == "eliminate":
			row = entry
	check(watched and not bool(row.get("enabled", true)) and bool(row.get("red", false)),
			"scene: with someone right there, 'silence them' is disabled and red")
	check(not menu.press_option("eliminate"), "scene: pressing the red option does nothing")


func _menu_chat(menu: NPCInteractionMenu, target: NPCNode) -> void:
	var before: int = NPCDirector.get_affection(target.npc_id)
	check(menu.press_option("chat"), "scene: small talk from the menu")
	await _settle()
	check(NPCDirector.get_affection(target.npc_id) > before or SocialTalk.bucket(NPCDirector.get_npc(target.npc_id)) == "hostile",
			"scene: the chat raises affection")
	check(menu.press_option("directions"), "scene: the directions submenu opens")
	check_eq(menu.get_page(), NPCInteractionMenu.PAGE_CHOICES, "scene: a submenu page")
	check(menu.press_choice("desk"), "scene: ask where your desk is")
	await _settle()
	check(menu.get_reply_text().length() > 0 and menu.get_page() == NPCInteractionMenu.PAGE_MAIN, "scene: the answer shows and the menu returns")
	check(menu.press_option("bribe") or not bool(SocialRules.options(target.npc_id, menu.get_exposure()).filter(
			func(o: Dictionary) -> bool: return o["id"] == "bribe")[0]["enabled"]), "scene: the in-person bribe opens (or explains why not)")
	if menu.get_page() == NPCInteractionMenu.PAGE_BRIBE:
		check(menu.get_bribe_panel() != null and menu.get_bribe_panel().get_channel() == Bribery.CHANNEL_IN_PERSON,
				"scene: BribePanel in the in-person channel")
	menu.close()
	await _settle()
	check(NPCInteractionMenu.find(get_tree()) == null and not _game.player.is_input_locked(), "scene: closing frees the player")


## Sin nadie más en la planta ni cámaras: confirmación → acto → fundido → cuerpo.
func _menu_eliminate(target: NPCNode) -> void:
	for node: NPCNode in _game.npc_layer.get_nodes():
		if node != target:
			node.global_position = Vector2(-100000, -100000)
	get_tree().call_group(SecurityCamera.GROUP, "set_active", false)
	await _settle()
	var victim: String = target.npc_id
	SocialInteractions.interact(target.interactable, _game.player, InteractionRouter.build_context(target.interactable, _game.player))
	var menu: NPCInteractionMenu = NPCInteractionMenu.find(get_tree())
	await _settle()
	if not check(menu != null and menu.press_option("eliminate"), "eliminate scene: the option is open with nobody around"):
		return
	check(await _wait(func() -> bool: return _game.ui.get_top_modal() is DialogBox), "eliminate scene: explicit confirmation first (§13.7)")
	(_game.ui.get_top_modal() as DialogBox).choose(0)
	check(await _wait(func() -> bool: return not NPCDirector.is_alive(victim)), "eliminate scene: the colleague is gone")
	check(await _wait(func() -> bool: return NPCInteractionMenu.find(get_tree()) == null), "eliminate scene: the menu closes after the fade")
	check(not NPCDirector.get_body_info(victim).is_empty(), "eliminate scene: a body is left to hide")
	check(not _game.player.is_input_locked(), "eliminate scene: control returns to the player")


func _cleanup() -> void:
	if _game != null and is_instance_valid(_game):
		get_tree().current_scene = null
		_game.queue_free()
	SaveSystem.delete_run()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(_dir))
