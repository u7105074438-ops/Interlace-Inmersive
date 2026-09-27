# personnel_app_case.gd — Cuerpo de test_personnel_app: tabla N1–N7 de §13.4, vías de acceso anticipado, filtros y orden (sin filtrar más de lo que muestra la ficha), objetivos, notas, estudio (consume tiempo, se guarda en PlayerState) y la ventana PERSONNEL (compacta incluida).
# PROPIETARIO DE: nada.
# ESCUCHA: notebook_entry_added (solo para comprobarla).
extends TestCase

const N1_OCCUPATION := "email_worker_3b"
const N3_OCCUPATION := "senior_sales"
const N5_OCCUPATION := "hr_director"
const N7_OCCUPATION := "vice_ceo"
const HR_OCCUPATION := "hr_assistant"
const IT_OCCUPATION := "it_director"
const SUBJECT := "npc_debbie_foyle"
const SNITCH := "npc_george_penn"
const N1_FIELDS: Array[String] = ["name", "photo", "post", "floor", "wing"]

var _notes: Array[Array] = []


func run_case() -> void:
	check(new_run(), "database loaded and run created")
	EventBus.notebook_entry_added.connect(func(cat: String, key: String, args: Array) -> void:
		_notes.append([cat, key, args]))
	_check_table()
	_check_levels_grow()
	_check_early_access()
	_check_filters_and_sort()
	_check_targets_and_notes()
	_check_study()
	await _check_window()


func _set_post(occupation_id: String) -> void:
	PlayerState.set_occupation(occupation_id, "test")


## §13.4 exacto: N1 solo identidad (nombre, foto, puesto, planta, ala).
func _check_table() -> void:
	_set_post(N1_OCCUPATION)
	check_eq(PlayerState.get_personnel_file_level(), 1, "email worker files at N1")
	check_eq(PersonnelApp.effective_level(SUBJECT), 1, "effective level N1")
	var file: Dictionary = PersonnelApp.build_file(SUBJECT, 1)
	var sections: Dictionary = file["sections"]
	check_eq(sections.keys(), ["identity"], "N1 shows only the identity block")
	var identity: Dictionary = sections["identity"]
	var keys: Array = identity.keys()
	keys.sort()
	var expected: Array = N1_FIELDS.duplicate()
	expected.sort()
	check_eq(keys, expected, "N1 identity = name, photo, post, floor, wing")
	check_eq(str(identity["name"]), "Debbie Foyle", "N1 name")
	check(not (identity["photo"] as Dictionary).is_empty(), "N1 has a portrait appearance")
	check(str(identity["floor"]).contains("3"), "N1 floor is floor 3")
	check_eq((file["locked"] as Array).size(), PersonnelApp.FILE_SECTIONS.size(), "N1 locks every other section")
	check(not bool(file["exact"]), "N1 has no exact figures")


func _section_set(level: int) -> Array:
	var keys: Array = PersonnelApp.build_file(SUBJECT, level)["sections"].keys()
	keys.sort()
	return keys


func _check_levels_grow() -> void:
	var expected: Dictionary = {
		2: ["character", "identity", "routine"],
		3: ["character", "identity", "links", "routine", "traits"],
		4: ["character", "history", "identity", "links", "routine", "traits", "weakness"],
		5: ["bribe_price", "character", "discipline", "exact_figures", "history", "identity", "links",
				"routine", "traits", "weakness"],
		6: ["bribe_price", "character", "discipline", "exact_figures", "history", "home", "identity",
				"links", "politics", "routine", "secrets", "traits", "weakness"],
	}
	for level: int in expected:
		var wanted: Array = expected[level]
		wanted.sort()
		check_eq(_section_set(level), wanted, "N%d sections match the §13.4 table" % level)
	check_eq(_section_set(7), _section_set(6), "N6 and N7 show the same sections")
	var previous: int = 0
	for level: int in range(1, 8):
		var count: int = _section_set(level).size()
		check(count >= previous, "N%d shows at least as much as N%d" % [level, level - 1])
		previous = count
	var n2: Dictionary = PersonnelApp.build_file(SUBJECT, 2)["sections"]
	check_eq((n2["routine"] as Array).size(), GameClock.get_band_order().size(), "N2 routine by band")
	check(not (n2["character"]["lines"] as Array).is_empty(), "N2 natural-language description")
	check(str(n2["character"]["archetype_name"]).length() > 0, "N2 character type")
	var real: int = NPCDirector.get_trait(SUBJECT, "sociability")
	var n3_traits: Array = PersonnelApp.build_file(SUBJECT, 3)["sections"]["traits"]
	var n5_traits: Array = PersonnelApp.build_file(SUBJECT, 5)["sections"]["traits"]
	check_eq(n3_traits.size(), 6, "N3 six traits")
	check_eq(int(n5_traits[5]["value"]), real, "N5 exact trait value")
	check(int(n3_traits[5]["value"]) != real or real % 20 == 10, "N3 trait value is approximate")
	var n5: Dictionary = PersonnelApp.build_file(SUBJECT, 5)["sections"]
	var prices: Array = n5["bribe_price"]["prices"]
	check(not prices.is_empty(), "N5 estimated bribe prices")
	var npc: NPCRuntime = NPCDirector.get_npc(SUBJECT)
	check_eq(int(prices[0]["price"]), Bribery.estimated_price(npc, str(prices[0]["favour"])),
			"N5 price comes from Bribery.estimated_price")
	var n6: Dictionary = PersonnelApp.build_file(SUBJECT, 6)["sections"]
	check(not (n6["secrets"] as Array).is_empty(), "N6 personal secrets")
	check_eq(str(n6["home"]["room_id"]), npc.home_address, "N6 home address")
	check((n6["politics"] as Array).size() >= (n5["links"] as Array).size(), "N6 full internal politics")


func _check_early_access() -> void:
	_set_post(N1_OCCUPATION)
	_notes.clear()
	check(PersonnelApp.open_full_file(SNITCH, PersonnelApp.REASON_HR_INTRUSION), "HR intrusion grants a file")
	check(PersonnelApp.open_full_file(SNITCH, PersonnelApp.REASON_HR_INTRUSION), "a granted file stays open")
	var file_notes: Array[Array] = []
	for note: Array in _notes:
		if str(note[1]) == "PERS_NOTE_FULL_FILE":
			file_notes.append(note)
	check_eq(file_notes.size(), 1, "the notebook hears about a granted file once")
	check(file_notes.size() == 1 and (file_notes[0][2] as Array).has("PERS_REASON_HR_INTRUSION"),
			"notebook args carry keys, not translated text")
	check_eq(PersonnelApp.full_file_reason(SNITCH), PersonnelApp.REASON_HR_INTRUSION, "reason: HR break-in")
	check_eq(PersonnelApp.effective_level(SNITCH), PersonnelApp.max_level(), "intruded file is complete")
	var lasker: String = "npc_bernard_lasker"
	if NPCDirector.get_npc(lasker) != null:
		PersonnelApp.open_full_file(lasker, PersonnelApp.REASON_BLACKMAIL)
		check_eq(PersonnelApp.full_file_reason(lasker), PersonnelApp.REASON_BLACKMAIL,
				"a file opened by blackmail is labelled blackmail")
	check_eq(PersonnelApp.effective_level(SUBJECT), 1, "other files stay at N1")
	var claudia: String = "npc_claudia_reeves"
	EventBus.blackmail_initiated.emit(claudia, claudia, "test_material")
	check_eq(PersonnelApp.effective_level(claudia), PersonnelApp.max_level(), "blackmail reveals the full file")
	_set_post(HR_OCCUPATION)
	check_eq(PersonnelApp.effective_level(SUBJECT), PersonnelApp.max_level(), "HR post: permanent full access")
	_set_post(IT_OCCUPATION)
	check(PersonnelApp.build_file(SUBJECT, 5)["sections"].has("private_comms"), "IT director reads private comms")
	_set_post(N1_OCCUPATION)
	check(not PersonnelApp.build_file(SUBJECT, 7)["sections"].has("private_comms"), "no comms without IT")


func _ids(filters: Dictionary) -> Array[String]:
	var out: Array[String] = []
	for npc: NPCRuntime in PersonnelApp.list_npcs(filters):
		out.append(npc.id)
	return out


func _check_filters_and_sort() -> void:
	_set_post(N1_OCCUPATION)
	var all: Array[String] = _ids({})
	check_eq(all.size(), NPCDirector.get_all_npcs().size(), "no filter lists the whole staff")
	check_eq(_ids({"query": "debb"}), [SUBJECT], "search by name (case-insensitive)")
	for id: String in _ids({"floor": 3}):
		check_eq(PersonnelApp.npc_floor(NPCDirector.get_npc(id)), 3, "floor filter keeps floor 3 only (%s)" % id)
	var tier_ids: Array[String] = _ids({"tier": 8})
	check(not tier_ids.is_empty(), "rank filter finds the top tier")
	for id: String in tier_ids:
		check_eq(NPCDirector.get_npc(id).tier, 8, "tier filter (%s)" % id)
	check(not _ids({"archetype": "gossip"}).has(SUBJECT), "archetype hidden at N1 → no match")
	for id: String in _ids({"category": PersonnelApp.CAT_BRIBABLE}):
		check_eq(PersonnelApp.effective_level(id), PersonnelApp.max_level(),
				"at N1 only full files can be classed bribable (%s)" % id)
	_set_post(N3_OCCUPATION)
	check(_ids({"archetype": "gossip"}).has(SUBJECT), "archetype filter at N3")
	var bribable: Array[String] = _ids({"category": PersonnelApp.CAT_BRIBABLE})
	check(not bribable.is_empty(), "bribable category at N3")
	check(not bribable.has(SNITCH), "the snitch is not bribable")
	check(_ids({"category": PersonnelApp.CAT_DANGEROUS}).has(SNITCH), "the snitch is dangerous")
	var greed_min: int = Database.get_balance_int("expedientes.sobornable_codicia_min")
	var honest_bars: bool = true
	for id: String in bribable:
		var npc: NPCRuntime = NPCDirector.get_npc(id)
		var exact: bool = PersonnelApp.effective_level(id) >= PersonnelApp.section_level(PersonnelApp.S_EXACT)
		honest_bars = honest_bars and PersonnelApp.shown_value(npc.get_trait("greed"), exact) >= greed_min
	check(honest_bars, "below N5 the bribable filter uses the approximate bars the file shows")
	NPCDirector.add_debt(SUBJECT, 2)
	check_eq(_ids({"category": PersonnelApp.CAT_DEBTORS}), [SUBJECT], "debtors category")
	NPCDirector.add_debt(SUBJECT, -2)
	var by_social: Array[NPCRuntime] = PersonnelApp.list_npcs({"sort": "sociability"})
	check(by_social[0].get_trait("sociability") >= by_social[by_social.size() - 1].get_trait("sociability"),
			"sort by a visible trait (descending)")
	var by_name: Array[NPCRuntime] = PersonnelApp.list_npcs({"sort": PersonnelApp.SORT_NAME})
	check(by_name[0].name <= by_name[1].name, "sort by name")
	var by_rank: Array[NPCRuntime] = PersonnelApp.list_npcs({"sort": PersonnelApp.SORT_RANK})
	check(PersonnelApp.npc_rank(by_rank[0]) >= PersonnelApp.npc_rank(by_rank[1]), "sort by rank")


func _check_targets_and_notes() -> void:
	_notes.clear()
	PersonnelApp.set_marked(SUBJECT, true)
	check(PersonnelApp.is_marked(SUBJECT), "target marked")
	check(NPCDirector.get_full_lod_reasons(SUBJECT).has(PersonnelApp.LOD_REASON_TARGET), "marked target forced to LOD 0")
	check_eq(PersonnelApp.list_npcs({"category": PersonnelApp.CAT_TARGETS}).size(), 1, "targets filter")
	# PlayerState.mark_target anuncia el objetivo (NPCDirector lo oye); mientras PERSONNEL repita su
	# propia nota, el registro del cuaderno (PlayerState) funde las dos idénticas en una.
	var marked_notes: Array = PlayerState.get_notebook_entries().filter(func(e: Dictionary) -> bool:
		return e["text_key"] == "PERS_NOTE_TARGET_MARKED")
	check(not _notes.is_empty() and _notes.all(func(n: Array) -> bool:
		return str(n[1]) == "PERS_NOTE_TARGET_MARKED") and marked_notes.size() == 1,
			"marking writes to the notebook (one log entry)")
	PersonnelApp.set_marked(SUBJECT, false)
	check(not PersonnelApp.is_marked(SUBJECT), "target cleared")
	check(not NPCDirector.get_full_lod_reasons(SUBJECT).has(PersonnelApp.LOD_REASON_TARGET), "LOD released")
	_notes.clear()
	check(PersonnelApp.add_note(SUBJECT, "  Runs the gossip sheet  "), "note added")
	check(not PersonnelApp.add_note(SUBJECT, "   "), "empty note rejected")
	check_eq(PersonnelApp.get_notes(SUBJECT).size(), 1, "note stored with the file")
	check(_notes.size() == 1 and _notes[0][0] == PersonnelApp.NOTE_CAT_PERSONNEL
			and (_notes[0][2] as Array).has("Runs the gossip sheet"), "note linked to the notebook")


func _check_study() -> void:
	var before: float = GameClock.get_total_minutes()
	var result: Dictionary = PersonnelApp.study(SNITCH, PersonnelApp.STUDY_REPORT)
	var spent: float = GameClock.get_total_minutes() - before
	check(int(result["minutes"]) >= 15 and int(result["minutes"]) <= 30, "study costs 15–30 minutes")
	check_near(spent, float(result["minutes"]), 0.01, "study consumes game time via GameClock")
	check(PersonnelApp.PROB_WORD_KEYS.has(str(result["word_key"])), "prediction rendered as a fuzzy word")
	check(float(result["probability"]) > 0.5, "the snitch is predicted to report")
	var gossip: float = PersonnelApp.predict(SUBJECT, PersonnelApp.STUDY_REPORT)
	check(gossip < float(result["probability"]), "the gossip is less likely to report than the snitch")
	var bribe: float = PersonnelApp.predict(SNITCH, PersonnelApp.STUDY_BRIBE)
	check_eq(bribe, 0.0, "the unbribable snitch will not take money")
	check_eq(PersonnelApp.probability_word_key(0.0), "PERS_PROB_VERY_UNLIKELY", "0 → very unlikely")
	check_eq(PersonnelApp.probability_word_key(0.95), "PERS_PROB_VERY_LIKELY", "0.95 → very likely")
	check(PersonnelApp.get_studies(SNITCH).has(PersonnelApp.STUDY_REPORT), "study remembered in the file")
	check(PlayerState.get_studies(SNITCH).has(PersonnelApp.STUDY_REPORT), "studies are saved by PlayerState")


func _check_window() -> void:
	_set_post(N1_OCCUPATION)
	var app: PersonnelApp = PersonnelApp.new()
	app.setup({"npc_id": SUBJECT})
	add_child(app)
	await wait_frames(3)
	check_eq(app.get_selected(), SUBJECT, "window opens the requested file")
	check_eq(app.get_visible_npc_ids().size(), NPCDirector.get_all_npcs().size(), "window lists the staff")
	app.set_filters({"query": "penn"})
	check_eq(app.get_visible_npc_ids(), [SNITCH], "window search")
	app.compare(SUBJECT, SNITCH)
	await wait_frames(2)
	check(app.is_comparing(), "comparison view open")
	app.call("_on_mark_toggled", true)
	await wait_frames(1)
	check(app.is_comparing() and PersonnelApp.is_marked(SUBJECT), "marking while comparing keeps the comparison")
	PersonnelApp.set_marked(SUBJECT, false)
	app.set_filters({"query": ""})
	app.size = Vector2(PersonnelApp.OsKit.px(PersonnelApp.COMPACT_EM * 0.6), app.size.y)
	await wait_frames(2)
	check(app.is_compact(), "a phone-width window switches to the compact layout")
	app.show_list(true)
	app.call("_on_row_picked", SNITCH)
	await wait_frames(1)
	check_eq(app.get_selected(), SNITCH, "compact: picking a row opens that file")
	var closed: Array[bool] = [false]
	app.close_requested.connect(func() -> void: closed[0] = true)
	app.request_close()
	check(closed[0], "close button requests closing")
	app.queue_free()
	await wait_frames(1)
