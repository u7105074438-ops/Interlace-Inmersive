# save_load_case.gd — Cuerpo de test_save_load (§21): guardar y cargar reproduce el estado exacto de todos los sistemas; escritura atómica; permadeath variante A (§12.7).
# PROPIETARIO DE: el directorio temporal de guardado del caso (lo crea y lo borra).
# ESCUCHA: run_loaded (solo para comprobarla).
extends TestCase

## "Exacto" = comparación estricta (_diff): mismos tipos (int ≠ float, String ≠ StringName,
## arrays tipados), mismos valores (float bit a bit) y mismas claves.

const OTHER_SEED := 777
const STORAGE_FORMAT := "user://test_save_load_%d"
## Los once sistemas con estado de partida (BUILD_NOTES §2), en el orden de project.godot.
const EXPECTED_PERSISTENT: Array[String] = [
	"Database", "GameClock", "PlayerState", "BeliefNet", "NPCDirector", "SocialGraph", "Security",
	"Company", "Market", "NewsFeed", "IdeaPool", "Tracking",
]
const BLOB_MARKER := "\"GameClock\":\""
const VICTORY_BLOOD := 60
const HUSK_RUIN := 150

var _dir: String = ""
var _loaded_days: Array[int] = []


func run_case() -> void:
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	EventBus.run_loaded.connect(func(day: int) -> void: _loaded_days.append(day))
	_test_contract()
	_test_lossless_encoding()
	check(new_run(DEFAULT_SEED), "Database loaded and a populated run started")
	_play_a_little()
	var before: Dictionary = _states()
	_test_save(before)
	_test_load_into_fresh_run(before)
	_test_scene_nodes_and_difficulty()
	_test_atomic_write()
	_test_recovery()
	_test_corrupt_run_is_rejected()
	_test_permadeath()
	_test_victory_unlock()
	_cleanup()


func _test_contract() -> void:
	check_eq(SaveSystemNode.RUN_PATH, "user://run.json", "RUN_PATH (§19.13)")
	check_eq(SaveSystemNode.PROFILE_PATH, "user://profile.json", "PROFILE_PATH (§19.13)")
	check_eq(SaveSystemNode.SAVE_VERSION, 1, "SAVE_VERSION (§19.13)")
	check_eq(SaveSystem.get_run_path(), _dir.path_join("run.json"), "the case writes into its own directory")
	SaveSystem.delete_run()
	check(not SaveSystem.run_exists(), "no run saved yet")
	check(not SaveSystem.load_run(), "load_run() without a file fails quietly")


## El formato de cada estado conserva lo que el JSON de Godot pierde.
func _test_lossless_encoding() -> void:
	var tricky: float = _json_unsafe_float()
	check(not is_nan(tricky), "found a float that a JSON round trip does not return intact")
	var typed: Array[String] = ["a", "b"]
	var state: Dictionary = {"f": tricky, "i": 3, "whole": 2.0, 7: "int key", "typed": typed,
			"v": Vector2i(4, 5), "nested": {"x": [1, 2.5, "s"]}}
	var back: Variant = SaveSystemNode.decode_state(SaveSystemNode.encode_state(state))
	check_eq(_diff(back, state, "state"), "", "encode/decode keeps floats, int/float, int keys and typed arrays")
	check(_diff({"n": 1}, {"n": 1.0}, "x") != "" and _diff({"f": tricky}, {"f": tricky + 0.0000001}, "x") != "",
			"the strict compare tells int from float and any float difference")


## Estado no trivial en varios sistemas, solo por sus API públicas y señales.
func _play_a_little() -> void:
	PlayerState.add_money(750, "test")
	PlayerState.set_player_name("Ana Test")
	GameClock.advance_minutes(95.0)
	NewsFeed.publish("NEWS_FRAUD_UNCOVERED", -0.2, true)
	var victim: NPCRuntime = NPCDirector.get_all_npcs()[0]
	NPCDirector.remove_npc(victim.id, "eliminated")
	EventBus.crime_committed.emit("theft_product", "factory_floor", {"value": 4100})
	EventBus.bribe_offered.emit("npc_bree_nash", 2500, "silence")
	EventBus.bribe_result.emit("npc_bree_nash", true, "accepted")
	check(Tracking.get_axis("blood") > 0 and Tracking.get_axis("gold") > 0, "the run has tracked acts")


func _test_save(before: Dictionary) -> void:
	check_eq(SaveSystem.get_persistent_autoloads(), EXPECTED_PERSISTENT,
			"the eleven state systems and Database's difficulty preset are saved, in project order (not EventBus, SaveSystem)")
	check(SaveSystem.save_run(), "save_run() succeeds")
	check(SaveSystem.run_exists(), "run.json exists after saving")
	check(not FileAccess.file_exists(SaveSystem.get_run_path() + ".tmp"), "the atomic write leaves no .tmp")
	var data: Dictionary = SaveSystem.read_verified(SaveSystem.get_run_path(), "systems")
	check(not data.is_empty(), "run.json passes the integrity check")
	check_eq(int(data.get("version", 0)), SaveSystemNode.SAVE_VERSION, "file carries the save version")
	check_eq(int(data.get("day", 0)), GameClock.get_day(), "file carries the day")
	var systems: Variant = SaveSystemNode.decode_systems(data.get("systems"))
	check(systems is Dictionary and (systems as Dictionary).size() == EXPECTED_PERSISTENT.size(),
			"one decodable entry per persistent autoload")
	var json_drift: int = 0
	for autoload_name: String in EXPECTED_PERSISTENT:
		var stored: Variant = (systems as Dictionary).get(autoload_name) if systems is Dictionary else null
		check_eq(_diff(stored, before[autoload_name], autoload_name), "",
				"%s: file holds exactly its save_state()" % autoload_name)
		var via_json: Variant = JSON.parse_string(JSON.stringify(before[autoload_name], "", true, true))
		json_drift += 0 if _diff(via_json, before[autoload_name], autoload_name).is_empty() else 1
	check(json_drift > 0, "(a plain JSON body would have altered %d of these states)" % json_drift)


func _test_load_into_fresh_run(before: Dictionary) -> void:
	new_run(OTHER_SEED)
	check_eq(Tracking.get_axis("blood"), 0, "a fresh run with another seed starts clean")
	check(_diff(_states(), before, "run") != "", "the fresh run differs from the saved one")
	_loaded_days.clear()
	check(SaveSystem.load_run(), "load_run() succeeds")
	check_eq(_loaded_days, [GameClock.get_day()], "run_loaded(day) emitted once with the saved day")
	var after: Dictionary = _states()
	for autoload_name: String in EXPECTED_PERSISTENT:
		check_eq(_diff(after[autoload_name], before[autoload_name], autoload_name), "",
				"%s: save → load reproduces the exact state" % autoload_name)
	check_eq(GameClock.get_run_seed(), DEFAULT_SEED, "the run seed comes back with the save")
	check(SaveSystem.is_run_active(), "a loaded run is the live run")
	EventBus.run_started.emit(DEFAULT_SEED)
	check(SaveSystem.run_exists(), "run_started after load_run() keeps the loaded run's file")


## Nodos de escena con estado (grupo SCENE_GROUP) y preset de dificultad (Database) viajan en run.json.
func _test_scene_nodes_and_difficulty() -> void:
	new_run(DEFAULT_SEED)
	check(Database.set_difficulty_preset("interno"), "precondition: 'interno' preset")
	var node: Node = _scene_node("TestSceneNode", 7)
	var expected: Array[String] = ["TestSceneNode"]
	check_eq(SaveSystem.get_persistent_scene_nodes(), expected,
			"a node in SaveSystemNode.SCENE_GROUP is saved with the run")
	check(SaveSystem.save_run(), "save_run() with a scene node")
	node.set("value", 99)
	Database.set_difficulty_preset("auditoria")
	check(SaveSystem.load_run(), "load_run()")
	check_eq(int(node.get("value")), 7, "the scene node already in the tree gets its state back")
	check_eq(Database.get_difficulty_preset(), "interno", "the run's difficulty preset is restored")
	node.queue_free()
	remove_child(node)
	check(SaveSystem.load_run(), "load_run() with the node gone")
	check_eq(SaveSystem.claim_scene_state("TestSceneNode"), {"value": 7},
			"a node created later claims its pending state…")
	check(SaveSystem.claim_scene_state("TestSceneNode").is_empty(), "…only once")
	Database.set_difficulty_preset("estandar")


## Nodo mínimo con save_state/load_state y get_save_key (el contrato de CaughtHandler/DutySystem).
func _scene_node(key: String, value: int) -> Node:
	var script: GDScript = GDScript.new()
	script.source_code = "extends Node\nvar value: int = 0\nfunc get_save_key() -> String:\n\treturn \"%s\"\nfunc save_state() -> Dictionary:\n\treturn {\"value\": value}\nfunc load_state(d: Dictionary) -> void:\n\tvalue = int(d.get(\"value\", 0))\n" % key
	script.reload()
	var node: Node = Node.new()
	node.set_script(script)
	node.set("value", value)
	node.add_to_group(SaveSystemNode.SCENE_GROUP)
	add_child(node)
	return node


## save_run() escribe SIEMPRE a través de run.json.tmp; un temporal dañado nunca sustituye al bueno.
func _test_atomic_write() -> void:
	var path: String = SaveSystem.get_run_path()
	var good: String = FileAccess.get_file_as_string(path)
	DirAccess.make_dir_absolute(path + ".tmp")
	check(not SaveSystem.save_run(), "save_run() fails when run.json.tmp cannot be written…")
	check_eq(FileAccess.get_file_as_string(path), good, "…and run.json is untouched: it is never written directly")
	DirAccess.remove_absolute(path + ".tmp")
	_write(path + ".tmp", good.left(good.length() >> 1))
	check(SaveSystem.load_run(), "a half-written .tmp left by a crash does not affect loading")
	var tampered: String = _tamper(good)
	check(tampered != good, "test built a tampered copy of the save")
	check(not SaveSystem.write_atomic(path, tampered, "systems"), "a tmp whose checksum fails is rejected")
	check(not SaveSystem.write_atomic(path, good.left(good.length() - 1), "systems"),
			"a truncated tmp is rejected")
	check_eq(FileAccess.get_file_as_string(path), good, "the good file is never replaced by a corrupted tmp")
	check(not FileAccess.file_exists(path + ".tmp"), "rejected temporaries are removed")
	PlayerState.add_money(5, "test")
	check(SaveSystem.save_run(), "saving again overwrites the single run file")
	check(not FileAccess.file_exists(path + ".tmp"), "no .tmp after a successful overwrite")
	check(FileAccess.get_file_as_string(path) != good, "the new save replaced the old one")


## Corte entre la verificación del .tmp y el renombrado (o durante él): se recupera el .tmp.
func _test_recovery() -> void:
	var path: String = SaveSystem.get_run_path()
	var good: String = FileAccess.get_file_as_string(path)
	var expected: Dictionary = _states()
	DirAccess.rename_absolute(path, path + ".tmp")
	check(SaveSystem.run_exists(), "a verified .tmp alone still counts as a saved run")
	PlayerState.add_money(9, "test")
	check(SaveSystem.load_run(), "run.json missing + verified .tmp → the tmp is loaded")
	check_eq(_diff(_states(), expected, "run"), "", "…restoring the saved state")
	check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"),
			"…and promoted to run.json")
	_write(path, good.left(good.length() >> 1))
	_write(path + ".tmp", good)
	check(SaveSystem.load_run(), "a damaged run.json with a verified .tmp recovers the tmp")
	check_eq(FileAccess.get_file_as_string(path), good, "…which replaces the damaged file")
	DirAccess.remove_absolute(path)
	_write(path + ".tmp", good.left(good.length() >> 1))
	check(not SaveSystem.load_run(), "run.json missing + damaged .tmp → nothing to load")
	_write(path, good)
	DirAccess.remove_absolute(path + ".tmp")


func _test_corrupt_run_is_rejected() -> void:
	var path: String = SaveSystem.get_run_path()
	var good: String = FileAccess.get_file_as_string(path)
	var before: Dictionary = Tracking.save_state()
	Tracking.add("silk", 99, "test")
	var changed: Dictionary = Tracking.save_state()
	_write(path, _tamper(good))
	check(not SaveSystem.load_run(), "a run.json whose checksum fails is not loaded")
	check_eq(_diff(Tracking.save_state(), changed, "Tracking"), "", "a rejected load touches no system")
	_write(path, good.replace("\"version\":1", "\"version\":99"))
	check(not SaveSystem.load_run(), "a run.json from another save version is not loaded")
	_write(path, good)
	check(SaveSystem.load_run(), "the intact file loads again")
	check_eq(_diff(Tracking.save_state(), before, "Tracking"), "", "…restoring the saved state")


## Permadeath variante A (§12.7): game_over borra la partida y la cierra; solo el perfil sobrevive.
func _test_permadeath() -> void:
	SaveSystem.reset_for_new_run()
	check(SaveSystem.save_run(), "a run is saved at bedtime")
	SaveSystem.reset_for_new_run()
	EventBus.game_over.emit("starvation", "the_gap", {})
	check(SaveSystem.run_exists(), "a process with no live run (tests, menus) deletes nothing")
	check(SaveSystem.is_run_over() and not SaveSystem.save_run(), "…but after any game over nothing is saved")
	EventBus.run_started.emit(DEFAULT_SEED)
	check(not SaveSystem.run_exists(), "a NEW run discards the previous character's run.json (one file)")
	check(SaveSystem.is_run_active() and not SaveSystem.is_run_over(), "run_started marks a live run")
	check(SaveSystem.save_run(), "saved again")
	EventBus.game_over.emit("investigation_conclusive", "the_file",
			Tracking.get_snapshot_for_cause("investigation_conclusive"))
	check(not SaveSystem.run_exists(), "game_over deletes run.json")
	check(not FileAccess.file_exists(SaveSystem.get_run_path() + ".tmp"), "…and any temporary")
	check(not SaveSystem.is_run_active(), "no live run after the game over")
	check(not SaveSystem.save_run(), "save_run() after the game over is refused (no resurrection)…")
	check(not SaveSystem.run_exists() and not SaveSystem.is_run_active(), "…so the dead run is not written back")
	check(not SaveSystem.load_run(), "there is nothing to load back: no undo")
	check(SaveSystem.get_unlocked_endings().has("the_file"), "the ending is unlocked in the profile")
	var profile: Dictionary = SaveSystem.read_verified(SaveSystem.get_profile_path(), "profile")
	check((profile.get("profile", {}).get("unlocked_endings", []) as Array).has("the_file"),
			"the unlocked ending is written to profile.json")


## El final de la galería lo decide Tracking (ya conoce la causa), no el payload.
func _test_victory_unlock() -> void:
	new_run(DEFAULT_SEED, false)
	EventBus.run_started.emit(DEFAULT_SEED)
	PlayerState.set_occupation("ceo", "test")
	PlayerState.add_item("ownership_documents")
	EventBus.ownership_notarised.emit()
	Tracking.add("blood", VICTORY_BLOOD, "test")
	Tracking.add("ruin", HUSK_RUIN, "test")
	check(SaveSystem.save_run(), "the next run saves")
	EventBus.game_over.emit("ownership_notarised", "the_gap", Tracking.get_snapshot_for_cause("ownership_notarised"))
	var unlocked: Array[String] = SaveSystem.get_unlocked_endings()
	check(unlocked.has("the_butcher") and unlocked.has("the_butcher@husk"),
			"the ending Tracking evaluates (THE BUTCHER, husk) is unlocked with its ruin variant")
	check(not unlocked.has("the_gap"), "a wrong ending id in the payload is not trusted")
	new_run(DEFAULT_SEED, false)
	check(FileAccess.file_exists(SaveSystem.get_profile_path()), "profile.json survives the new run")
	SaveSystem.forget_profile()
	check(SaveSystem.load_profile(), "the profile loads in the next session")
	check(SaveSystem.get_unlocked_endings().has("the_file"), "the gallery survives permadeath")


# ─── Utilidades ───────────────────────────────────────────────

## {autoload: copia profunda de save_state()}.
func _states() -> Dictionary:
	var out: Dictionary = {}
	for autoload_name: String in SaveSystem.get_persistent_autoloads():
		var state: Variant = autoload(autoload_name).call("save_state")
		out[autoload_name] = (state as Dictionary).duplicate(true) if state is Dictionary else state
	return out


## "" si a y b son idénticos (tipos y valores); si no, la ruta de la primera diferencia.
static func _diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: %s ≠ %s" % [path, type_string(typeof(a)), type_string(typeof(b))]
	if a is Dictionary:
		return _diff_dict(a, b, path)
	if a is Array:
		return _diff_array(a, b, path)
	if a is float and is_nan(a) and is_nan(b):
		return ""
	return "" if a == b else "%s: %s ≠ %s" % [path, var_to_str(a), var_to_str(b)]


static func _diff_dict(a: Dictionary, b: Dictionary, path: String) -> String:
	if a.size() != b.size():
		return "%s: %d keys ≠ %d keys" % [path, a.size(), b.size()]
	if a.is_typed() != b.is_typed() or a.get_typed_key_builtin() != b.get_typed_key_builtin() \
			or a.get_typed_value_builtin() != b.get_typed_value_builtin():
		return "%s: dictionary typing differs" % path
	for key: Variant in a:
		if not b.has(key):
			return "%s: key %s (%s) missing" % [path, var_to_str(key), type_string(typeof(key))]
		var inner: String = _diff(a[key], b[key], "%s.%s" % [path, str(key)])
		if not inner.is_empty():
			return inner
	return ""


static func _diff_array(a: Array, b: Array, path: String) -> String:
	if a.size() != b.size():
		return "%s: %d items ≠ %d items" % [path, a.size(), b.size()]
	if a.is_typed() != b.is_typed() or a.get_typed_builtin() != b.get_typed_builtin():
		return "%s: array typing differs" % path
	for i: int in a.size():
		var inner: String = _diff(a[i], b[i], "%s[%d]" % [path, i])
		if not inner.is_empty():
			return inner
	return ""


## Un float que JSON.stringify(precisión completa) → parse no devuelve idéntico (NAN si no hay).
static func _json_unsafe_float() -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = DEFAULT_SEED
	for _i: int in 1000:
		var value: float = rng.randf() * 1000.0
		var back: Variant = JSON.parse_string(JSON.stringify(value, "", true, true))
		if not back is float or back != value:
			return value
	return NAN


## Cambia un carácter del estado de GameClock sin tocar el checksum.
static func _tamper(text: String) -> String:
	var at: int = text.find(BLOB_MARKER) + BLOB_MARKER.length()
	var swapped: String = "B" if text[at] == "A" else "A"
	return text.left(at) + swapped + text.substr(at + 1)


static func _write(path: String, text: String) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _cleanup() -> void:
	SaveSystem.delete_run()
	for file_name: String in ["profile.json", "profile.json.tmp"]:
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)
	SaveSystem.set_storage_dir("")
	SaveSystem.forget_profile()
	SaveSystem.reset_for_new_run()
	check(not DirAccess.dir_exists_absolute(_dir), "the case leaves no files behind")
	check_eq(SaveSystem.get_run_path(), SaveSystemNode.RUN_PATH, "storage back on user://run.json")
	check_eq(SaveSystem.get_profile_path(), SaveSystemNode.PROFILE_PATH, "…and user://profile.json")
