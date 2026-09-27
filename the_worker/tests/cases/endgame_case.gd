# endgame_case.gd — Cuerpo de test_endgame: revelación por rango, tres vías de la combinación con sus riesgos, ventana de Voss y accesos, documentos (registro, pérdida), notaría (presencia, firma, comprobación de tres jornadas y sus desenlaces, autorización falsa) y los finales de la resolución.
# PROPIETARIO DE: nada.
# ESCUCHA: game_over, ownership_documents_obtained, ownership_notarised, noise_emitted, crime_committed, npc_reported_player (solo para comprobar).
extends TestCase

## El estado de los demás sistemas se prepara con su API pública de «manos» o con señales de
## EventBus (las que escucha el nodo Endgame). La tirada de Endgame se fija con Endgame.roll_source.

const VOSS := "npc_harlan_voss"
const PEARL := "npc_pearl_osgood"
const PRESTON := "npc_preston_vaile"
const BREE := "npc_bree_nash"
const DOCS := "ownership_documents"
const FORGED := "forged_authorization"
const STAMP := "stamp"
const TOOLS := "cutting_tools"
const OFFICE := "ceo_office"
const SECRETARIAT := "ceo_secretariat"
const HR_OFFICE := "hr_office"
const LEGAL_ARCHIVE := "legal_archive"
const NOTARY := "notary"
const LEGAL := "legal_director"
const COORDINATOR := "meeting_coordinator"
const R25 := "comms_director"
const R30 := "board_investor"
const R33 := "ceo"
const STASH_ROOM := "dead_archive"
const STASH_SPOT := "hide_dead_archive_west"
const HIGH_REPUTATION := 80.0
const FORGER_REPUTATION := 70.0
const VERIFY_SUSPICION := 55.0
const SEARCH_SUSPICION := 70.0
const MAX_BELIEFS := 200
const FEAR := 40
const BOARD_CONFIDENCE := 100
# Valores del manual / balance que la prueba fija (§11.8, §12.4, endings.json).
const OFFICE_HOURS := Vector2i(600, 1020)
const VOSS_LUNCH := Vector2i(780, 840)
const VOSS_MEETING := Vector2i(930, 975)
const MORNING_BAND := Vector2i(540, 780)
const VERIFICATION_DAYS := 3
const FORGED_WEIGHT := 5.0
const SURVEILLANCE_BONUS := 15
const SAFE_NOISE := 10.0
const SILK_FORGERY := 5
const FIGUREHEAD_QUARTERS := 4
const EPS := 0.001

var _game_overs: Array = []
var _obtained: int = 0
var _notarised: int = 0
var _noises: Array = []
var _crimes: Array = []
var _reports: Array = []
var _node: Endgame = null


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded the data files")
	_connect_signals()
	_node = Endgame.new()
	add_child(_node)
	_test_revelation()
	_test_pearl_failure_and_surveillance()
	_test_pearl_success_routes()
	_test_pearl_favours()
	_test_voss_files()
	_test_window_and_meetings()
	_test_access_routes()
	_test_physical_route()
	_test_documents_in_search()
	await _test_documents_lost()
	_test_notary_presence()
	_test_notary_signs()
	_test_notary_verification()
	_test_verification_outcomes()
	_test_forged_path()
	_test_forgery_detected()
	_test_endings_by_axis()
	_test_figurehead()
	_test_figurehead_via_signals()
	_test_preston()
	_test_persistence()
	Endgame.roll_source = Callable()


func _connect_signals() -> void:
	EventBus.game_over.connect(func(c: String, e: String, s: Dictionary) -> void:
		_game_overs.append([c, e, s]))
	EventBus.ownership_documents_obtained.connect(func() -> void: _obtained += 1)
	EventBus.ownership_notarised.connect(func() -> void: _notarised += 1)
	EventBus.noise_emitted.connect(func(p: Vector2, r: float, s: String) -> void:
		_noises.append([p, r, s]))
	EventBus.crime_committed.connect(func(t: String, room: String, _d: Dictionary) -> void:
		_crimes.append([t, room]))
	EventBus.npc_reported_player.connect(func(n: String, t: String, _w: float, _l: String) -> void:
		_reports.append([n, t]))


# ─── Fase 1: revelación ───────────────────────────────────────

func _test_revelation() -> void:
	_setup(false, "email_worker_3b")
	check(not Endgame.is_objective_revealed(), "R1: the second objective stays hidden")
	check_eq(Endgame.get_phase(), "hidden", "phase hidden before R26")
	check_eq(Endgame.get_objective_text_key(), "OBJECTIVE_HIDDEN", "objective text: climb, no ownership talk")
	check_eq(Endgame.approach_pearl("blackmail")["reason"], "objective_hidden", "no mission actions while hidden")
	check_eq(Endgame.forge_authorization()["reason"], "objective_hidden", "no forging for the notary while hidden")
	check_eq(Endgame.do_pearl_favour("bury_annex")["reason"], "objective_hidden", "no favours for Pearl while hidden")
	PlayerState.set_occupation(R25, "test")
	check(not Endgame.is_objective_revealed(), "R25 (comms director) still does not know how ownership moves")
	check_eq(_note_count("ENDGAME_NOTE_REVEALED"), 0, "no revelation note yet")
	PlayerState.set_occupation(LEGAL, "test")
	check_eq(Endgame.get_revelation_rank(), 26, "revelation rank = legal_director (R26)")
	check(Endgame.is_objective_revealed(), "legal_director reveals the documents and the procedure")
	check_eq(_note_count("ENDGAME_NOTE_REVEALED"), 1, "the notebook records the revelation once")
	check_eq(Endgame.get_objective_text_key(), "OBJECTIVE_COMBINATION", "objective now names the safe")
	check(tr(Endgame.get_objective_text_key()) != Endgame.get_objective_text_key(), "objective text translated")
	PlayerState.set_occupation(R25, "test")
	check(Endgame.is_objective_revealed(), "a demotion does not make the player forget")
	check_eq(_note_count("ENDGAME_NOTE_REVEALED"), 1, "…and the note is not repeated")


# ─── Fase 2: Pearl Osgood ─────────────────────────────────────

func _test_pearl_failure_and_surveillance() -> void:
	_setup(true, LEGAL)
	check(not Endgame.is_bribe_viable(PEARL), "Pearl Osgood cannot be bribed (loyalty 96)")
	var result: Dictionary = Endgame.approach_pearl("bribe")
	check(not result["ok"] and result["reason"] == "unbribable" and result.get("informed_voss", false),
			"a bribe attempt fails and Pearl informs Voss")
	check_eq(_pearl_reports(), 1, "Pearl's report goes to her superior (channel superior)")
	check(not NPCDirector.get_personal_surveillance(VOSS).is_empty(), "Voss starts personal surveillance")
	check(NPCDirector.get_full_lod_reasons(VOSS).has("personal_surveillance"), "Voss is forced to LOD 0")
	_at(11, 0)
	EventBus.room_entered.emit("legal_director_office", true)
	check_eq(NPCDirector.get_current_location(VOSS), "legal_director_office", "Voss follows the player")
	check_eq(NPCDirector.get_follow_target(VOSS), "player", "the NPC node is told to follow the player")
	var agenda: Array[Dictionary] = Endgame.get_voss_absence_windows(GameClock.get_day())
	check(_has_window(agenda, VOSS_LUNCH, "ceo_private_room") and _has_window(agenda, VOSS_MEETING, "ceo_boardroom"),
			"while he follows the player, the agenda still shows his real schedule")
	check(Endgame.is_office_holder_following(), "…and warns that he is following the player now")
	check_eq(Endgame.reassure_voss_via(BREE)["reason"], "unwilling", "an intermediary with no reason to lie refuses")
	result = Endgame.approach_pearl("blackmail")
	check(result["reason"] == "no_material" and result.get("informed_voss", false), "blackmail without her HR file fails")
	check_eq(_pearl_reports(), 1, "no second formal report while Voss already watches on her word")
	NPCDirector.add_fear(BREE, FEAR)
	check(Endgame.reassure_voss_via(BREE)["ok"], "fear is reason enough to lie to Voss")
	check(not NPCDirector.is_player_under_surveillance(), "…and he stops watching (nobody tells him the truth)")
	Endgame.approach_pearl("bribe")
	check_eq(_pearl_reports(), 2, "a new failure after he stopped watching is reported again")
	var watched: int = NPCDirector.get_effective_perception(VOSS)
	NPCDirector.add_debt(PRESTON, 20)
	check(Endgame.reassure_voss_via(PRESTON)["ok"], "Voss believes an intermediary who owes the player")
	check_eq(watched - NPCDirector.get_effective_perception(VOSS), SURVEILLANCE_BONUS, "surveillance perception bonus")
	check_eq(NPCDirector.get_current_location(VOSS), OFFICE, "back to his schedule (office at 11:00)")
	check(not NPCDirector.get_full_lod_reasons(VOSS).has("personal_surveillance"), "LOD 0 released")
	check(not Endgame.knows_combination(), "no combination after failures")
	NPCDirector.begin_personal_surveillance(VOSS, 2, "test")
	NPCDirector.remove_npc(VOSS, "eliminated")
	check(not NPCDirector.is_player_under_surveillance() and NPCDirector.get_surveillance_watchers().is_empty(),
			"a watcher who leaves the staff no longer watches")


func _test_pearl_success_routes() -> void:
	_setup(true, LEGAL)
	PlayerState.grant_full_file(PEARL, "hr_intrusion")
	check(Endgame.knows_pearl_secret(), "her HR file is the blackmail material")
	check(Endgame.approach_pearl("blackmail")["ok"], "blackmail with her HR file secret works")
	check_eq(Endgame.get_combination_source(), "pearl", "combination from Pearl")
	check(NPCDirector.get_fear(PEARL) > 0, "Pearl now fears the player (blackmail_initiated)")
	check_eq(_pearl_reports(), 0, "a successful approach is not reported")
	check_eq(Endgame.approach_pearl("favour")["reason"], "already_known", "once known, nothing to ask")
	_setup(true, LEGAL)
	NPCDirector.add_favour(PEARL, "bribe_paid", 10)
	var small: Dictionary = Endgame.approach_pearl("favour")
	check(small["reason"] == "favour_too_small" and small.get("informed_voss", false), "an ordinary favour is not enough")
	check_eq(Endgame.do_pearl_favour("bury_annex")["reason"], "no_secret", "covering her secret requires knowing it")
	PlayerState.grant_full_file(PEARL, "hr_intrusion")
	check_eq(Endgame.do_pearl_favour("bury_annex")["reason"], "wrong_room", "the annex is in the HR office")
	EventBus.room_entered.emit(HR_OFFICE, true)
	var favour: Dictionary = Endgame.do_pearl_favour("bury_annex")
	check(favour["ok"] and favour["magnitude"] >= Database.get_balance_int("final.pearl.magnitud_favor_extraordinario"),
			"removing the annex from her file is a favour of extraordinary size")
	check(_crimes.has(["records_deleted", HR_OFFICE]), "tampering with an HR file is a crime")
	check_eq(Endgame.do_pearl_favour("bury_annex")["reason"], "already_done", "only one secret to cover")
	check_eq(Endgame.approach_pearl("blackmail")["reason"], "no_material", "a covered secret is no blackmail material")
	check(Endgame.approach_pearl("favour")["ok"], "the extraordinary favour buys the combination")
	check_eq(_note_count("ENDGAME_NOTE_PEARL_FAVOUR"), 1, "notebook: Pearl repaid the favour")
	check_eq(Endgame.get_phase(), "safe", "phase: open the safe")


func _test_pearl_favours() -> void:
	_setup(true, R30)
	PlayerState.grant_full_file(PEARL, "hr_intrusion")
	EventBus.room_entered.emit(LEGAL_ARCHIVE, true)
	var listed: Array[Dictionary] = Endgame.get_pearl_favours()
	check(listed.size() == 2 and listed.all(func(f: Dictionary) -> bool:
		return tr(str(f["name_key"])) != str(f["name_key"])), "two extraordinary favours, both named")
	check_eq(Endgame.do_pearl_favour("ratify_signatures")["reason"], "no_authority", "only the legal director ratifies")
	PlayerState.set_occupation(LEGAL, "test")
	check(Endgame.do_pearl_favour("ratify_signatures")["ok"], "as legal director, ratifying her signatures is a favour")
	check(not _crimes.any(func(c: Array) -> bool: return c[0] == "records_deleted"), "…and a legitimate one")
	check(Endgame.approach_pearl("favour")["ok"], "Pearl repays it with the combination")


func _pearl_reports() -> int:
	return _reports.filter(func(r: Array) -> bool: return r == [PEARL, "superior"]).size()


# ─── Fase 2: archivos de Voss ─────────────────────────────────

func _test_voss_files() -> void:
	_setup(true, LEGAL)
	check_eq(Endgame.search_voss_files(10)["reason"], "not_in_office", "files only inside the CEO office")
	_at(11, 0)
	EventBus.room_entered.emit(OFFICE, true)
	check(Endgame.is_voss_in_office(), "11:00: Voss occupies the office")
	var seen: Dictionary = Endgame.search_voss_files(10)
	check(seen["reason"] == "observed" and seen["witness"] == VOSS, "searching under Voss's nose fails")
	_at(13, 10)
	check(not Endgame.is_voss_in_office(), "13:10: Voss is at his private lunch")
	Endgame.roll_source = func() -> float: return 0.99
	check_eq(Endgame.search_voss_files(20)["progress"], 20, "20 unobserved minutes accumulate")
	EventBus.room_entered.emit(SECRETARIAT, true)
	EventBus.room_entered.emit(OFFICE, true)
	check_eq(Endgame.search_voss_files(20)["progress"], 20, "leaving the office loses the visit: two short visits do not add up")
	Endgame.register_office_entry("roof_ledge")
	check_eq(Endgame.get_files_progress(), 0, "a new entry is a new visit")
	Endgame.roll_source = func() -> float: return 0.0
	var pearl: Dictionary = Endgame.search_voss_files(5)
	check(pearl["reason"] == "observed" and pearl["witness"] == PEARL and pearl["progress"] == 0,
			"Pearl looks in from the secretariat: progress lost")
	check(_has_belief(PEARL, "seen_partially", OFFICE), "…and she has a partial sighting")
	Endgame.roll_source = func() -> float: return 0.99
	check_eq(Endgame.search_voss_files(25)["reason"], "in_progress", "prolonged presence required")
	GameClock.advance_to_next_day()
	_at(13, 10)
	check_eq(Endgame.get_files_progress(), 0, "yesterday's minutes do not count today")
	check_eq(Endgame.search_voss_files(25)["progress"], 25, "a new day starts from zero")
	var done: Dictionary = Endgame.search_voss_files(20)
	check(done["ok"] and Endgame.get_combination_source() == "voss_files", "45 quiet minutes in one visit: the combination")
	check(_crimes.has(["file_copied", OFFICE]), "reading Voss's private computer leaves a server trace")


# ─── Fase 3: ventana y reuniones ──────────────────────────────

func _test_window_and_meetings() -> void:
	_setup(true, COORDINATOR)
	check_eq(Endgame.provoke_long_meeting("work_morning")["reason"], "objective_hidden",
			"R18: no mission meetings before the revelation")
	_setup(true, LEGAL)
	check_eq(Endgame.get_office_hours(), OFFICE_HOURS, "Voss's office hours 10:00-17:00 (npcs_named)")
	var windows: Array[Dictionary] = Endgame.get_voss_absence_windows(GameClock.get_day())
	check(_has_window(windows, VOSS_LUNCH, "ceo_private_room"), "window: private lunch 13:00-14:00")
	check(_has_window(windows, VOSS_MEETING, "ceo_boardroom"), "window: boardroom meeting 15:30-16:15")
	check(not Endgame.is_office_holder_following(), "no surveillance: the agenda is where he will be")
	var inside: bool = windows.all(func(w: Dictionary) -> bool:
		return w["start"] >= OFFICE_HOURS.x and w["end"] <= OFFICE_HOURS.y and w["room"] != OFFICE)
	check(inside, "every window lies inside office hours and away from the office")
	var tomorrow: Array[Dictionary] = Endgame.get_voss_absence_windows(GameClock.get_day() + 1)
	check(not tomorrow.is_empty() and tomorrow == Endgame.get_voss_absence_windows(GameClock.get_day() + 1),
			"tomorrow's agenda is readable and deterministic")
	check_eq(Endgame.provoke_long_meeting("work_morning")["reason"], "no_authority", "only the meeting coordinator calls them")
	check_eq(Endgame.provoke_long_meeting("lunch", PRESTON)["reason"], "invalid_band", "only in working bands")
	check_eq(Endgame.get_preston_stance(), "ally", "Preston is a tactical ally against Voss")
	var meeting: Dictionary = Endgame.provoke_long_meeting("work_morning", PRESTON)
	check(meeting["ok"] and meeting["window"] == {"start": MORNING_BAND.x, "end": MORNING_BAND.y},
			"Preston drags Voss into a long morning meeting")
	check_eq(Endgame.provoke_long_meeting("work_afternoon", PRESTON)["reason"], "already_today", "one per day")
	_at(11, 0)
	check_eq(NPCDirector.get_current_location(VOSS), "ceo_boardroom", "11:00: Voss is in the boardroom")
	windows = Endgame.get_voss_absence_windows(GameClock.get_day())
	check(windows.any(func(w: Dictionary) -> bool: return w["start"] == OFFICE_HOURS.x),
			"the provoked meeting opens a window from 10:00")
	GameClock.advance_to_next_day()
	PlayerState.set_occupation(COORDINATOR, "test")
	PlayerState.set_occupation(LEGAL, "test")
	_at(13, 10)
	check_eq(Endgame.provoke_long_meeting("work_morning")["reason"], "band_over", "a morning that is over cannot be booked")
	check(Endgame.provoke_long_meeting("work_afternoon")["ok"], "having held meeting_coordinator is enough")


func _test_access_routes() -> void:
	_setup(true, COORDINATOR)
	check(Endgame.register_office_entry("vent")["ok"], "entering is a world hook, also before the revelation")
	_setup(true, LEGAL)
	var ids: Array = Endgame.get_access_routes().map(func(r: Dictionary) -> String: return r["id"])
	ids.sort()
	check_eq(ids, ["main_door", "roof_ledge", "vent"], "three accesses: door, roof ledge, machine-room vent")
	var office: RoomData = Database.get_room(OFFICE)
	for route: Dictionary in Endgame.get_access_routes():
		check(tr(str(route["name_key"])) != str(route["name_key"]), "%s has a name" % route["id"])
		check(Database.get_room(str(route["from_room"])) != null and _route_reaches(office, route),
				"%s: from %s into the office" % [route["id"], route["from_room"]])
	check_eq(Endgame.register_office_entry("window")["reason"], "unknown_route", "unknown access")
	var vent: Dictionary = Endgame.register_office_entry("vent")
	check(vent["ok"] and vent["minutes"] == 10 and vent["witness"] == "", "the vent is slow but unwatched")
	_at(11, 0)
	var door: Dictionary = Endgame.register_office_entry("main_door")
	check(door["witness"] == PEARL and _has_belief(PEARL, "seen_partially", SECRETARIAT),
			"the main door passes Pearl's desk without clearance")


# ─── Fase 2/4: vía física y documentos ────────────────────────

func _test_physical_route() -> void:
	_setup(true, LEGAL)
	_at(13, 10)
	EventBus.room_entered.emit(OFFICE, true)
	check_eq(Endgame.work_on_safe(30)["reason"], "no_means", "the legal director has no means to force it")
	PlayerState.set_disguise("uniform_maintenance")
	check(Endgame.has_forcing_post(), "a maintenance uniform gives the cover")
	check_eq(Endgame.work_on_safe(30)["reason"], "no_tools", "…but not the forcing tools")
	PlayerState.add_item(TOOLS)
	check(Endgame.has_physical_means(), "uniform + cutting tools from the maintenance store: the means")
	PlayerState.set_disguise("")
	PlayerState.set_occupation("maintenance_aide", "test")
	PlayerState.set_occupation(LEGAL, "test")
	check(not Endgame.has_forcing_post(), "having been a maintenance aide at R8 is not enough")
	PlayerState.set_occupation("security_director", "test")
	PlayerState.set_occupation(LEGAL, "test")
	check(Endgame.has_physical_means(), "having been security director (with the tools) gives the means")
	_noises.clear()
	var slow: Dictionary = Endgame.work_on_safe(40, Vector2(10, 20))
	check(slow["reason"] == "in_progress" and slow["required"] == 90, "slow: 90 minutes of work")
	check(_noises.size() == 1 and is_equal_approx(float(_noises[0][1]), SAFE_NOISE)
			and _noises[0][2] == "safe_forced", "noisy: a noise of radius 10 per work stretch")
	var done: Dictionary = Endgame.work_on_safe(50)
	check(done["ok"] and done["route"] == "physical" and PlayerState.is_carrying(DOCS), "the safe gives up the documents")
	check_eq(_obtained, 1, "ownership_documents_obtained emitted")
	check(_crimes.has(["lock_forced", OFFICE]), "evident: lock_forced in the office")
	check(not _office_case(), "no investigation yet on the same day")
	GameClock.advance_to_next_day()
	check(_office_case(), "next day: guaranteed investigation of the forced safe")
	check(not str(PlayerState.get_flag("endgame.safe_case", "")).is_empty(), "the case id is remembered")


func _test_documents_in_search() -> void:
	_setup(true, LEGAL)
	_learn_combination_from_pearl()
	_at(13, 10)
	EventBus.room_entered.emit(OFFICE, true)
	check(Endgame.open_safe()["ok"] and Endgame.get_documents_state() == "carried", "combination opens the safe")
	check_eq(Endgame.open_safe()["reason"], "already_taken", "the safe is empty afterwards")
	check_eq(Endgame.get_phase(), "custody", "phase: custody")
	check(Endgame.hide_documents(STASH_SPOT, STASH_ROOM), "the documents can be hidden")
	check(Endgame.get_documents_state() == "hidden" and Tracking.has_ownership_documents(), "hidden still owned")
	_raise_suspicion(SEARCH_SUSPICION)
	check(Security.can_search_player() and not Endgame.are_documents_at_risk(), "hidden: a search is harmless")
	check_eq(InventoryRules.perform_body_search(Security.get_effective_suspicion())["outcome"], "clean", "clean search")
	check(Endgame.retrieve_documents(STASH_SPOT) >= 0 and PlayerState.is_carrying(DOCS), "…and retrieved later")
	check(Endgame.are_documents_at_risk(), "carrying them with high suspicion = at risk")
	var search: Dictionary = InventoryRules.perform_body_search(Security.get_effective_suspicion())
	check(search["found_hot_items"] >= 1 and search["outcome"] == "conviction_major", "found in a search: conviction")
	check(not PlayerState.has_item(DOCS), "the documents are confiscated")
	GameClock.advance_to_next_day()
	check(not _game_overs.is_empty() and _game_overs[0][0] == "investigation_conclusive"
			and _game_overs[0][1] == "the_file", "…and the run is lost at the verdict (THE FILE)")


func _test_documents_lost() -> void:
	_setup(true, LEGAL)
	_learn_combination_from_pearl()
	_at(13, 10)
	EventBus.room_entered.emit(OFFICE, true)
	check(Endgame.open_safe()["ok"], "combination opens the safe")
	PlayerState.dispose_item(DOCS, "trash_dock")
	await wait_frames(1)
	check(not Tracking.has_ownership_documents() and Endgame.get_phase() == "safe",
			"documents thrown away: back to opening the safe")
	check_eq(_note_count("ENDGAME_NOTE_DOCUMENTS_LOST"), 1, "the notebook says the company has them back")
	check(Endgame.open_safe()["ok"], "…and the safe can be opened again")
	check(Endgame.hide_documents(STASH_SPOT, STASH_ROOM), "hidden in a stash")
	PlayerState.confiscate_stash(STASH_SPOT)
	await wait_frames(1)
	check(Endgame.get_documents_state() == "none" and Endgame.get_objective_text_key() == "OBJECTIVE_SAFE",
			"stash found: the objective points at the safe again")
	check_eq(_note_count("ENDGAME_NOTE_DOCUMENTS_LOST"), 2, "…with a new notebook entry")
	check(Endgame.open_safe()["ok"], "taken again")
	PlayerState.confiscate_hot_items()
	await wait_frames(1)
	check(Endgame.get_phase() == "safe" and _note_count("ENDGAME_NOTE_DOCUMENTS_LOST") == 3,
			"confiscated in a search the player survives: back in the safe")


# ─── Fase 5: notaría ──────────────────────────────────────────

func _test_notary_presence() -> void:
	_setup(true, R33)
	PlayerState.modify_reputation(HIGH_REPUTATION, "test")
	PlayerState.add_item(DOCS)
	_at(23, 0)
	EventBus.room_entered.emit(NOTARY, true)
	var notary: String = Endgame.get_notary_id()
	check(not notary.is_empty() and NPCDirector.get_current_location(notary) != NOTARY, "23:00: the notary has gone home")
	check(not Endgame.is_notary_present(), "nobody at the notary desk")
	check_eq(Endgame.request_notarisation()["reason"], "notary_absent", "an empty desk formalises nothing")
	check_eq(_notarised, 0, "nothing signed at night")
	NPCDirector.set_current_location(notary, NOTARY)
	check(Endgame.is_notary_present() and Endgame.request_notarisation()["ok"], "with the notary at the desk it goes through")


func _test_notary_signs() -> void:
	_setup(true, R33)
	PlayerState.modify_reputation(HIGH_REPUTATION, "test")
	Tracking.add("sweat", 50, "test")
	check_eq(Endgame.request_notarisation()["reason"], "not_at_notary", "formalise only at the notary")
	_enter_notary()
	check_eq(Endgame.request_notarisation()["reason"], "no_documents", "no documents, no transfer")
	PlayerState.add_item(DOCS)
	check(not Endgame.get_notary_id().is_empty(), "the in-house notary exists")
	check_eq(Endgame.preview_notary_decision(), "signed", "high reputation: signs without verification")
	var signed: Dictionary = Endgame.request_notarisation()
	check(signed["ok"] and signed["outcome"] == "signed" and signed["title"] == "ceo", "the notary signs at once")
	check_eq(_notarised, 1, "ownership_notarised emitted")
	check(_game_overs.size() == 1 and _game_overs[0][0] == "ownership_notarised" and _game_overs[0][1] == "the_worker",
			"victory is a game_over: R33 + documents + notarised + sweat → THE WORKER")
	check_eq(_game_overs[0][2].get("notary_title", ""), "ceo", "snapshot says how it was formalised")
	check_eq(Endgame.get_phase(), "resolved", "phase resolved")
	check_eq(Endgame.request_notarisation()["reason"], "run_over", "nothing happens after the end")
	_setup(true, R30)
	_enter_notary()
	PlayerState.add_item(DOCS)
	check_eq(Endgame.request_notarisation()["reason"], "no_title", "R30 without chair or authorisation: refused")


func _test_notary_verification() -> void:
	_setup(true, R33)
	PlayerState.modify_reputation(HIGH_REPUTATION, "test")
	Tracking.add("gold", 40, "test")
	_raise_suspicion(VERIFY_SUSPICION)
	var case_id: String = Security.report_incident("direct_witness_report", 1, "turnstiles", true,
			{"always_opens": true, "subject": "player", "weight": 0.5})
	var weight: float = Security.get_case_weight_against("player", case_id)
	PlayerState.add_item(DOCS)
	_enter_notary()
	var result: Dictionary = Endgame.request_notarisation()
	check(result["ok"] and result["outcome"] == "verification" and result["days"] == VERIFICATION_DAYS,
			"high suspicion: the notary asks for verification (3 days) even with high reputation")
	check(not PlayerState.is_carrying(DOCS) and Endgame.get_documents_state() == "with_notary", "documents lodged")
	check(Tracking.has_ownership_documents(), "lodged documents still count as owned")
	check(Endgame.is_player_max_vulnerable() and Endgame.get_objective_args() == [VERIFICATION_DAYS],
			"maximum vulnerability for 3 days")
	check(Security.get_case_weight_against("player", case_id) > weight + EPS, "open cases weigh more meanwhile")
	check_eq(Endgame.request_notarisation()["reason"], "verification_pending", "one request at a time")
	GameClock.advance_to_next_day()
	GameClock.advance_to_next_day()
	check(_notarised == 0 and Endgame.get_verification_days_left() == 1, "day 2 of 3: still verifying")
	GameClock.advance_to_next_day()
	check_eq(_notarised, 1, "after three days the notary signs")
	check(not _game_overs.is_empty() and _game_overs.back()[1] == "the_buyer", "…→ THE BUYER (gold)")


## Desenlaces de la comprobación con el título de ese momento, y el notario que desaparece.
func _test_verification_outcomes() -> void:
	_setup(true, R33)
	PlayerState.modify_reputation(HIGH_REPUTATION, "test")
	PlayerState.add_item(DOCS)
	_raise_suspicion(VERIFY_SUSPICION)
	_enter_notary()
	check_eq(Endgame.request_notarisation()["outcome"], "verification", "CEO under suspicion: verification")
	PlayerState.set_occupation("vice_ceo", "test")
	_advance_days(VERIFICATION_DAYS)
	check(_notarised == 0 and _game_overs.is_empty(), "chair lost during verification: no transfer")
	check_eq(Endgame.get_documents_state(), "carried", "the notary hands the documents back")
	check_eq(_note_count("ENDGAME_NOTE_TITLE_LOST"), 1, "notebook: the chair was lost")
	_setup(true, R30)
	_forge_and_lodge()
	PlayerState.set_occupation(R33, "test")
	_advance_days(VERIFICATION_DAYS)
	check(_notarised == 1 and _game_overs.size() == 1 and _game_overs[0][2].get("notary_title", "") == "ceo",
			"reaching the chair during verification: the notary signs as CEO")
	check(str(PlayerState.get_flag("endgame.forgery_case", "")).is_empty(), "…and never examines the forgery")
	_setup(true, R30)
	_forge_and_lodge()
	NPCDirector.remove_npc(str(Endgame.get_verification()["notary"]), "fired")
	check(not Endgame.is_verification_pending(), "the verifying notary left: verification cancelled")
	check(PlayerState.is_carrying(DOCS) and PlayerState.is_carrying(FORGED), "papers handed back, unsigned")
	check_eq(_note_count("ENDGAME_NOTE_NOTARY_GONE"), 1, "notebook: the notary is gone")
	_advance_days(VERIFICATION_DAYS)
	check(_notarised == 0 and str(PlayerState.get_flag("endgame.forgery_case", "")).is_empty(),
			"no signature and no forgery case")
	check_eq(Endgame.request_notarisation()["reason"], "no_notary", "no notary left to sign")


func _test_forged_path() -> void:
	_setup(true, R30)
	check_eq(Endgame.forge_authorization()["reason"], "no_stamp", "forging needs the desk stamp")
	PlayerState.add_item(STAMP)
	check_eq(Endgame.forge_authorization()["reason"], "low_reputation", "a nobody's forged signature convinces nobody")
	PlayerState.modify_reputation(FORGER_REPUTATION, "test")
	var forged: Dictionary = Endgame.forge_authorization()
	check(forged["ok"] and PlayerState.is_carrying(FORGED), "forged with the desk stamp")
	check_eq(Tracking.get_axis("silk"), SILK_FORGERY, "forgery → SILK +5")
	check(BeliefNet.is_record_neutral(str(forged["record_id"])), "an unverified stamped document (neutral record)")
	check_near(Endgame.forgery_reputation_required(), 60.0, EPS, "reputation threshold from balance")
	PlayerState.set_occupation("c10_director", "test")
	PlayerState.set_occupation(R30, "test")
	check_near(Endgame.forgery_reputation_required(), 40.0, EPS, "having been C10 director makes it credible")
	PlayerState.add_item(DOCS)
	_enter_notary()
	var signed: Dictionary = Endgame.request_notarisation()
	check(signed["ok"] and signed["title"] == "forged", "low suspicion: the forged authorisation passes")
	check(_game_overs.size() == 1 and _game_overs[0][1] == "the_owner_in_exile",
			"documents without the chair → THE OWNER IN EXILE")


func _test_forgery_detected() -> void:
	_setup(true, R30)
	var record: String = _forge_and_lodge()
	check(Endgame.is_verification_pending() and not PlayerState.is_carrying(FORGED), "forged path verified")
	check_eq(Tracking.evaluate_ending_for_cause("investigation_conclusive"), "the_owner_in_exile",
			"falling during verification still leaves the owner in exile")
	_advance_days(VERIFICATION_DAYS)
	check_eq(_notarised, 0, "the forgery is not formalised")
	var case_id: String = str(PlayerState.get_flag("endgame.forgery_case", ""))
	var inv: Investigation = Security.get_investigation(case_id)
	check(inv != null and inv.evidence.any(_is_forged_piece), "verified forgery = evidence 5.0 against the player")
	check(not BeliefNet.is_record_neutral(record), "the stamped document now weighs in suspicion")
	check(not Tracking.has_ownership_documents(), "the documents went back to the safe")
	check_eq(_note_count("ENDGAME_NOTE_FORGERY_DETECTED"), 1, "notebook: forgery exposed")


# ─── Fase 6: finales ──────────────────────────────────────────

func _test_endings_by_axis() -> void:
	var cases: Dictionary = {
		"the_butcher": {"blood": 40}, "the_buyer": {"gold": 40}, "the_ghost": {"silk": 40},
		"the_worker": {"sweat": 40}, "the_full_suite": {"blood": 10, "gold": 10, "silk": 10, "sweat": 10},
	}
	for ending: String in cases:
		_setup(true, R33)
		PlayerState.modify_reputation(HIGH_REPUTATION, "test")
		for axis: String in cases[ending]:
			Tracking.add(axis, int(cases[ending][axis]), "test")
		PlayerState.add_item(DOCS)
		_enter_notary()
		Endgame.request_notarisation()
		check(_game_overs.size() == 1 and _game_overs[0][1] == ending,
				"R33 + documents + notarised + %s → %s" % [str(cases[ending]), ending])


func _test_figurehead() -> void:
	_setup(false, "vice_ceo")
	GameClock.set_time(3, 9, 0)
	PlayerState.set_occupation(R33, "test")
	Endgame.process_quarter(1)
	check_eq(Endgame.get_figurehead_quarters(), 0, "a quarter started before the chair does not count")
	PlayerState.add_item(DOCS)
	for quarter: int in range(2, 1 + FIGUREHEAD_QUARTERS):
		Endgame.process_quarter(quarter)
	check(_game_overs.is_empty(), "three full quarters: still in office")
	Endgame.process_quarter(1 + FIGUREHEAD_QUARTERS)
	check(_game_overs.size() == 1 and _game_overs[0][0] == "ceo_term_without_ownership"
			and _game_overs[0][1] == "the_figurehead", "four quarters with un-notarised papers → THE FIGUREHEAD")


## La misma regla por la vía real: occupation_changed y quarter_closed (con el consejo contento,
## para que la presión del consejo no destituya antes al CEO).
func _test_figurehead_via_signals() -> void:
	_setup(false, "vice_ceo")
	GameClock.set_time(3, 9, 0)
	PlayerState.set_occupation(R33, "test")
	PlayerState.add_item(DOCS)
	for quarter: int in range(1, 1 + FIGUREHEAD_QUARTERS):
		_please_the_board()
		EventBus.quarter_closed.emit(quarter)
	check(_game_overs.is_empty() and Endgame.get_figurehead_quarters() == FIGUREHEAD_QUARTERS - 1,
			"quarter_closed counts only the full quarters in the chair")
	_please_the_board()
	EventBus.quarter_closed.emit(1 + FIGUREHEAD_QUARTERS)
	check(_game_overs.size() == 1 and _game_overs[0][0] == "ceo_term_without_ownership"
			and _game_overs[0][1] == "the_figurehead", "the node fires THE FIGUREHEAD on the fourth full quarter")


func _test_preston() -> void:
	_setup(true, LEGAL)
	check(Endgame.get_preston_stance() == "ally" and not Endgame.is_hostile_rival(PRESTON), "R26: tactical ally")
	PlayerState.set_occupation("vice_ceo", "test")
	check(Endgame.is_hostile_rival(PRESTON), "R32: Preston competes for the same chair")
	var grudges: Array = NPCDirector.get_ledger(PRESTON)["grievances"].filter(
			func(g: Dictionary) -> bool: return g["type"] == "rival_for_chair")
	check_eq(grudges.size(), 1, "one rivalry grievance in his ledger")
	PlayerState.set_occupation("board_secretary", "test")
	check_eq(Endgame.get_preston_stance(), "hostile", "he stays an enemy after a step down")
	check_eq(_note_count("ENDGAME_NOTE_PRESTON_HOSTILE"), 1, "the notebook warns once")


func _test_persistence() -> void:
	_setup(true, R30)
	_forge_and_lodge()
	NPCDirector.begin_personal_surveillance(VOSS, 2, "test")
	var player: Variant = JSON.parse_string(JSON.stringify(PlayerState.save_state()))
	var npcs: Variant = JSON.parse_string(JSON.stringify(NPCDirector.save_state()))
	PlayerState.load_state(player)
	NPCDirector.load_state(npcs)
	var v: Dictionary = Endgame.get_verification()
	check(typeof(v["end_day"]) == TYPE_INT and Endgame.get_verification_days_left() == VERIFICATION_DAYS,
			"the verification window survives a JSON save")
	check(Endgame.is_objective_revealed() and Tracking.has_ownership_documents(), "mission flags survive")
	check_eq(NPCDirector.get_personal_surveillance(VOSS).get("until_day"), GameClock.get_day() + 2,
			"Voss's surveillance survives a save")
	_advance_days(VERIFICATION_DAYS)
	check(_notarised == 0 and _note_count("ENDGAME_NOTE_FORGERY_DETECTED") == 1,
			"after loading, the verification keeps ticking and exposes the forgery")


# ─── Utilidades ───────────────────────────────────────────────

func _setup(with_population: bool, occupation: String) -> void:
	new_run(DEFAULT_SEED, with_population)
	Endgame.roll_source = Callable()
	PlayerState.set_occupation(occupation, "test")
	_game_overs.clear()
	_noises.clear()
	_crimes.clear()
	_reports.clear()
	_obtained = 0
	_notarised = 0


## En la notaría con el notario en su mesa (lo que haría su nodo del mundo).
func _enter_notary() -> void:
	EventBus.room_entered.emit(NOTARY, true)
	NPCDirector.set_current_location(Endgame.get_notary_id(), NOTARY)


## Estampa, reputación, autorización falsa, documentos y sospecha alta: la comprobación se abre.
## Devuelve el registro neutro de la falsificación.
func _forge_and_lodge() -> String:
	PlayerState.add_item(STAMP)
	PlayerState.modify_reputation(FORGER_REPUTATION, "test")
	var record: String = str(Endgame.forge_authorization()["record_id"])
	PlayerState.add_item(DOCS)
	_raise_suspicion(VERIFY_SUSPICION)
	_enter_notary()
	Endgame.request_notarisation()
	return record


func _learn_combination_from_pearl() -> void:
	PlayerState.grant_full_file(PEARL, "hr_intrusion")
	Endgame.approach_pearl("blackmail")


func _please_the_board() -> void:
	for investor: InvestorData in Market.get_investors():
		Market.modify_investor_confidence(investor.id, BOARD_CONFIDENCE, "test")


func _advance_days(days: int) -> void:
	for _i: int in days:
		GameClock.advance_to_next_day()


## Avanza el reloj de hoy hasta hh:mm (solo hacia delante).
func _at(hour: int, minute: int) -> void:
	var target: float = float(hour * 60 + minute)
	if target > GameClock.get_day_minutes():
		GameClock.advance_minutes(target - GameClock.get_day_minutes())


func _raise_suspicion(target: float) -> void:
	var i: int = 0
	while PlayerState.get_suspicion() < target and i < MAX_BELIEFS:
		BeliefNet.create_belief("npc_t_witness_%d" % i, "player", "caught_redhanded:theft_small",
				1.0, "direct", "turnstiles")
		i += 1


func _note_count(text_key: String) -> int:
	return PlayerState.get_notebook_entries().filter(
			func(e: Dictionary) -> bool: return e["text_key"] == text_key).size()


func _has_belief(holder: String, fact_type: String, location: String) -> bool:
	return BeliefNet.get_beliefs_held_by(holder).any(func(b: Belief) -> bool:
		return b.subject == "player" and b.fact.begins_with(fact_type) and b.location == location)


func _has_window(windows: Array[Dictionary], span: Vector2i, room: String) -> bool:
	return windows.any(func(w: Dictionary) -> bool:
		return w["start"] == span.x and w["end"] == span.y and w["room"] == room)


func _is_forged_piece(piece: Dictionary) -> bool:
	return piece["type"] == "forged_document" and piece["points_to"] == "player" \
			and is_equal_approx(float(piece["weight"]), FORGED_WEIGHT)


func _office_case() -> bool:
	return Security.get_active_investigations().any(
			func(inv: Investigation) -> bool: return inv.location == OFFICE)


## La puerta conecta con la secretaría; cornisa y conducto llevan de su sala al despacho.
func _route_reaches(office: RoomData, route: Dictionary) -> bool:
	var interactable: String = str(route["interactable"])
	if interactable.is_empty():
		return office.connects_to.has(str(route["from_room"]))
	for entry: Dictionary in office.interactables:
		if entry.get("id", "") == interactable:
			return (entry.get("leads_to", []) as Array).has(route["from_room"])
	return false
