# player_memory_case.gd — Cuerpo de test_player_memory: memoria externa del jugador en PlayerState (§13.3-§13.5): notas, bloc, registro del cuaderno, contactos (proximidad, favores, mensajes, RR. HH., compra), objetivos marcados con LOD 0, expedientes, estudios, banderas y persistencia.
# PROPIETARIO DE: nada.
# ESCUCHA: notebook_entry_added (conexión temporal, para comprobarla).
extends TestCase

const EPS := 0.0001
const DEBBIE := "npc_debbie_foyle"
const GEORGE := "npc_george_penn"
const CLAUDIA := "npc_claudia_reeves"
const OFFICE := "wing_3b"
const WORK_DAY := 1
const WORK_HOUR := 9
const HR_OCCUPATION := "hr_assistant"
const LOD_REASON := "marked_target"
const FLAG := "ownership_procedure_phase"

var _entries: Array = []


func run_case() -> void:
	check(new_run(DEFAULT_SEED), "Database loaded and a populated run started")
	EventBus.notebook_entry_added.connect(_on_entry)
	_test_notes()
	_test_notebook_log()
	_test_contacts_by_hand()
	_test_automatic_contacts()
	_test_proximity_contacts()
	_test_hr_department()
	_test_marked_targets()
	_test_files_studies_flags()
	_test_save_load()
	EventBus.notebook_entry_added.disconnect(_on_entry)


func _on_entry(category: String, text_key: String, args: Array) -> void:
	_entries.append([category, text_key, args])


func _name(npc_id: String) -> String:
	return NPCDirector.get_npc(npc_id).name


# ─── Notas y bloc (§13.3) ──────────────────────────────────────

func _test_notes() -> void:
	new_run(DEFAULT_SEED)
	GameClock.set_time(WORK_DAY, WORK_HOUR, 15)
	_entries.clear()
	var first: int = PlayerState.add_note("  Claudia leaves at 18:00  ")
	var second: int = PlayerState.add_note("Feed her the rumour", DEBBIE)
	check(first > 0 and second == first + 1, "notes get increasing ids")
	check_eq(PlayerState.add_note("   "), PlayerRecords.NO_NOTE, "an empty note is refused")
	var notes: Array[Dictionary] = PlayerState.get_notes()
	check(notes.size() == 2 and notes[0]["text"] == "Claudia leaves at 18:00"
			and notes[0]["day"] == WORK_DAY and notes[0]["hour"] == WORK_HOUR
			and notes[0]["minute"] == 15, "a note keeps its trimmed text and game time stamp")
	check_eq(PlayerState.get_notes_about(DEBBIE).size(), 1, "notes linked to a character")
	check(_entries.has(["personnel", "PERS_NOTE_ENTRY", [_name(DEBBIE), "Feed her the rumour"]]),
			"a personnel annotation is also logged in the notebook")
	check(PlayerState.remove_note(first) and not PlayerState.remove_note(first),
			"remove_note removes once")
	var cap: int = Database.get_balance_int("ordenador.cuaderno_max_caracteres")
	PlayerState.set_notepad("x".repeat(cap + 10))
	check_eq(PlayerState.get_notepad().length(), cap, "the notepad is capped at the notebook limit")
	var max_notes: int = Database.get_balance_int("jugador.notas_max")
	for i: int in max_notes + 2:
		PlayerState.add_note("note %d" % i)
	check_eq(PlayerState.get_notes().size(), max_notes, "at most jugador.notas_max notes (oldest dropped)")


# ─── Registro automático del cuaderno (§13.7) ──────────────────

func _test_notebook_log() -> void:
	new_run(DEFAULT_SEED)
	GameClock.set_time(WORK_DAY, WORK_HOUR, 0)
	EventBus.notebook_entry_added.emit("duties", "NOTE_TEST_ONE", [3])
	EventBus.notebook_entry_added.emit("duties", "NOTE_TEST_ONE", [3])
	GameClock.advance_minutes(1.0)
	EventBus.notebook_entry_added.emit("duties", "NOTE_TEST_ONE", [3])
	var entries: Array[Dictionary] = PlayerState.get_notebook_entries()
	check_eq(entries.size(), 2, "every notebook entry is kept; an identical one in the same minute counts once")
	check(entries[0]["category"] == "duties" and entries[0]["text_key"] == "NOTE_TEST_ONE"
			and entries[0]["args"] == [3] and entries[0]["hour"] == WORK_HOUR
			and entries[1]["minute"] == 1,
			"entries carry category, key, args and the game time")


# ─── Contactos (§13.5) ─────────────────────────────────────────

func _test_contacts_by_hand() -> void:
	new_run(DEFAULT_SEED)
	_entries.clear()
	check(PlayerState.get_contacts().is_empty() and not PlayerState.has_contact(DEBBIE),
			"no numbers at the start")
	check(PlayerState.add_contact(DEBBIE, "purchase"), "a bought number")
	check(not PlayerState.add_contact(DEBBIE, "favour"), "a contact is added once (first source kept)")
	check(PlayerState.add_contact(GEORGE, "colleague"), "UI alias 'colleague' is accepted")
	check(not PlayerState.add_contact(CLAUDIA, "stolen"), "an unknown source is refused")
	check(not PlayerState.add_contact("npc_nobody", "purchase"), "only real characters")
	check(not PlayerState.add_contact("player", "purchase"), "the player is not a contact")
	check_eq(PlayerState.get_contact_source(GEORGE), "proximity", "aliases map to the canonical source")
	var ids: Array = PlayerState.get_contacts().map(func(c: Dictionary) -> String: return c["npc_id"])
	check_eq(ids, [DEBBIE, GEORGE], "get_contacts in acquisition order")
	check(_entries.has(["contacts", "NOTE_CONTACT_ADDED", [_name(DEBBIE), "CONTACT_SOURCE_PURCHASE"]]),
			"a new contact is noted in the notebook")


func _test_automatic_contacts() -> void:
	new_run(DEFAULT_SEED)
	EventBus.favour_added.emit(DEBBIE, "promotion", 2)
	EventBus.blackmail_demanded.emit(GEORGE, "money", 500)
	EventBus.phone_message_received.emit(CLAUDIA, "PHONE_TEST", true)
	EventBus.phone_message_received.emit("hr_system", "PHONE_TEST", false)
	check_eq([PlayerState.get_contact_source(DEBBIE), PlayerState.get_contact_source(GEORGE),
			PlayerState.get_contact_source(CLAUDIA)], ["favour", "messaged", "messaged"],
			"favours, blackmail demands and messages give the number")
	check_eq(PlayerState.get_contacts().size(), 3, "a message from a non-character adds nothing")


func _test_proximity_contacts() -> void:
	new_run(DEFAULT_SEED)
	GameClock.set_time(WORK_DAY, WORK_HOUR, 0)
	EventBus.room_entered.emit(OFFICE, true)
	var needed: int = Database.get_balance_int("movil.horas_proximidad_contacto")
	for i: int in needed - 1:
		_pin_and_tick(WORK_HOUR + i)
	check(not PlayerState.has_contact(DEBBIE) and PlayerState.get_proximity_hours(DEBBIE) == needed - 1,
			"%d shared working hours are not enough yet" % (needed - 1))
	_pin_and_tick(WORK_HOUR + needed)
	check_eq(PlayerState.get_contact_source(DEBBIE), "proximity",
			"after %d hours working in the same room the colleague gives the number" % needed)
	check(not PlayerState.has_contact(CLAUDIA), "someone in another room does not")
	GameClock.set_time(WORK_DAY, 21, 0)
	for i: int in needed:
		NPCDirector.set_current_location(GEORGE, OFFICE)
		EventBus.hour_passed.emit(21, WORK_DAY)
	check(not PlayerState.has_contact(GEORGE), "hours outside the working day do not count")


## PlayerState oye hour_passed antes que NPCDirector: las salas fijadas justo antes son las que ve.
func _pin_and_tick(hour: int) -> void:
	NPCDirector.set_current_location(DEBBIE, OFFICE)
	NPCDirector.set_current_location(CLAUDIA, "cafeteria")
	EventBus.hour_passed.emit(hour, WORK_DAY)


func _test_hr_department() -> void:
	new_run(DEFAULT_SEED)
	PlayerState.set_occupation(HR_OCCUPATION, "test")
	var all: int = NPCDirector.get_all_npcs().size()
	check(PlayerState.has_contact(CLAUDIA), "§13.5: working in HR gives every number")
	check_eq(PlayerState.get_contacts().size(), all, "get_contacts lists the whole staff from HR")
	check_eq(PlayerState.get_contact_source(CLAUDIA), "hr", "…with source hr")
	new_run(DEFAULT_SEED)
	check(PlayerState.grant_full_file(CLAUDIA, "hr_intrusion"), "an HR intrusion grants the full file")
	check(PlayerState.has_full_file(CLAUDIA) and PlayerState.get_contact_source(CLAUDIA) == "hr",
			"…and the number (contact from HR)")
	check(PlayerState.grant_full_file(GEORGE, "blackmail") and not PlayerState.has_contact(GEORGE),
			"a full file by other means gives no number")


# ─── Objetivos marcados (§13.4, §13.6) ─────────────────────────

func _test_marked_targets() -> void:
	new_run(DEFAULT_SEED)
	_entries.clear()
	check(PlayerState.mark_target(CLAUDIA), "mark_target")
	check(not PlayerState.mark_target(CLAUDIA) and not PlayerState.mark_target("npc_nobody"),
			"marking twice or a stranger does nothing")
	var expected: Array[String] = [CLAUDIA]
	check(PlayerState.is_marked(CLAUDIA) and PlayerState.get_marked_targets() == expected,
			"the target list")
	check(_entries.has(["targets", "PERS_NOTE_TARGET_MARKED", [_name(CLAUDIA)]]),
			"the notebook records the new target")
	check(NPCDirector.get_full_lod_reasons(CLAUDIA).has(LOD_REASON)
			and NPCDirector.get_lod(CLAUDIA) == NPCRuntime.LOD_FULL,
			"NPCDirector hears it and keeps the target at full LOD")
	check(PlayerState.unmark_target(CLAUDIA) and not PlayerState.unmark_target(CLAUDIA), "unmark once")
	check(not NPCDirector.get_full_lod_reasons(CLAUDIA).has(LOD_REASON),
			"unmarking releases the forced LOD")
	check(_entries.has(["targets", "PERS_NOTE_TARGET_CLEARED", [_name(CLAUDIA)]]),
			"…and the notebook records it")


func _test_files_studies_flags() -> void:
	new_run(DEFAULT_SEED)
	PlayerState.record_study(DEBBIE, "bribe", {"minutes": 20, "probability": 0.4})
	check_eq(PlayerState.get_studies(DEBBIE), {"bribe": {"minutes": 20, "probability": 0.4}},
			"studies are kept per character and action")
	check(PlayerState.get_flag(FLAG) == null and PlayerState.get_flag(FLAG, 0) == 0,
			"a missing flag gives the default")
	PlayerState.set_flag(FLAG, 2)
	check(PlayerState.has_flag(FLAG) and PlayerState.get_flag(FLAG) == 2, "set_flag / get_flag")
	PlayerState.set_flag(FLAG, null)
	check(not PlayerState.has_flag(FLAG), "null clears a flag")


# ─── Persistencia ──────────────────────────────────────────────

func _test_save_load() -> void:
	new_run(DEFAULT_SEED)
	PlayerState.add_note("remember", GEORGE)
	PlayerState.set_notepad("pad")
	PlayerState.add_contact(DEBBIE, "purchase")
	PlayerState.mark_target(CLAUDIA)
	PlayerState.grant_full_file(GEORGE, "blackmail")
	PlayerState.record_study(GEORGE, "report", {"probability": 0.25})
	PlayerState.set_flag("notarised", true)
	EventBus.notebook_entry_added.emit("security", "NOTE_TEST_TWO", ["a"])
	var json_text: String = JSON.stringify(PlayerState.save_state())
	new_run(DEFAULT_SEED)
	check(PlayerState.get_notes().is_empty() and PlayerState.get_contacts().is_empty(),
			"a new run forgets the previous memory")
	PlayerState.load_state(JSON.parse_string(json_text))
	check_eq(JSON.stringify(PlayerState.save_state()), json_text, "save → JSON → load → save is identical")
	check(PlayerState.get_notes_about(GEORGE).size() == 1 and PlayerState.get_notepad() == "pad",
			"notes and notepad survive")
	check(PlayerState.get_contact_source(DEBBIE) == "purchase" and PlayerState.is_marked(CLAUDIA),
			"contacts and targets survive")
	check(PlayerState.get_full_file_reason(GEORGE) == "blackmail"
			and is_equal_approx(float(PlayerState.get_studies(GEORGE)["report"]["probability"]), 0.25),
			"files and studies survive")
	check(PlayerState.get_flag("notarised") == true, "flags survive")
	check(PlayerState.get_notebook_entries().any(func(e: Dictionary) -> bool:
		return e["text_key"] == "NOTE_TEST_TWO" and e["args"] == ["a"]), "the notebook log survives")
	var next: int = PlayerState.add_note("after load")
	check(next > int(PlayerState.get_notes()[0]["id"]), "note ids keep increasing after a load")
