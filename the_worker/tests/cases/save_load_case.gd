# save_load_case.gd — Cuerpo de test_save_load (§21): guardar y cargar reproduce el estado exacto de todos los sistemas; escritura atómica; permadeath variante A (§12.7).
# PROPIETARIO DE: el directorio temporal de guardado del caso (lo crea y lo borra).
# ESCUCHA: run_loaded (solo para comprobarla).
extends TestCase

const OTHER_SEED := 777
const STORAGE_FORMAT := "user://test_save_load_%d"
const NEVER_PERSISTED: Array[String] = ["EventBus", "SaveSystem"]
const TAMPER_FROM := "\"GameClock\":{"
const TAMPER_TO := "\"GameClock\":{\"tampered\":1,"

var _dir: String = ""
var _loaded_days: Array[int] = []


func run_case() -> void:
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	EventBus.run_loaded.connect(func(day: int) -> void: _loaded_days.append(day))
	_test_contract()
	check(new_run(DEFAULT_SEED), "Database loaded and a populated run started")
	_play_a_little()
	var before: Dictionary = _states()
	_test_save(before)
	_test_load_into_fresh_run(before)
	_test_atomic_write()
	_test_corrupt_run_is_rejected()
	_test_permadeath()
	_cleanup()


func _test_contract() -> void:
	check_eq(SaveSystemNode.RUN_PATH, "user://run.json", "RUN_PATH (§19.13)")
	check_eq(SaveSystemNode.PROFILE_PATH, "user://profile.json", "PROFILE_PATH (§19.13)")
	check_eq(SaveSystemNode.SAVE_VERSION, 1, "SAVE_VERSION (§19.13)")
	check_eq(SaveSystem.get_run_path(), _dir.path_join("run.json"), "the case writes into its own directory")
	SaveSystem.delete_run()
	check(not SaveSystem.run_exists(), "no run saved yet")
	check(not SaveSystem.load_run(), "load_run() without a file fails quietly")


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
	var persistent: Array[String] = SaveSystem.get_persistent_autoloads()
	for autoload_name: String in _autoload_names():
		var node: Node = autoload(autoload_name)
		var expected: bool = node.has_method("save_state") and node.has_method("load_state") \
				and not NEVER_PERSISTED.has(autoload_name)
		check_eq(persistent.has(autoload_name), expected,
				"%s %s saved" % [autoload_name, "is" if expected else "is not"])
	check(SaveSystem.save_run(), "save_run() succeeds")
	check(SaveSystem.run_exists(), "run.json exists after saving")
	check(not FileAccess.file_exists(SaveSystem.get_run_path() + ".tmp"), "the atomic write leaves no .tmp")
	var data: Dictionary = SaveSystem.read_verified(SaveSystem.get_run_path(), "systems")
	check(not data.is_empty(), "run.json passes the integrity check")
	check_eq(int(data.get("version", 0)), SaveSystemNode.SAVE_VERSION, "file carries the save version")
	check_eq(int(data.get("day", 0)), GameClock.get_day(), "file carries the day")
	var systems: Dictionary = data.get("systems", {})
	check_eq(systems.size(), persistent.size(), "one entry per persistent autoload")
	for autoload_name: String in persistent:
		check_eq(_canon(systems.get(autoload_name)), before[autoload_name],
				"%s: file holds exactly its save_state()" % autoload_name)


func _test_load_into_fresh_run(before: Dictionary) -> void:
	new_run(OTHER_SEED)
	check_eq(Tracking.get_axis("blood"), 0, "a fresh run with another seed starts clean")
	check(_states() != before, "the fresh run differs from the saved one")
	_loaded_days.clear()
	check(SaveSystem.load_run(), "load_run() succeeds")
	check_eq(_loaded_days, [GameClock.get_day()], "run_loaded(day) emitted once with the saved day")
	var after: Dictionary = _states()
	for autoload_name: String in before:
		check_eq(after[autoload_name], before[autoload_name],
				"%s: save → load reproduces the exact state" % autoload_name)
	check_eq(GameClock.get_run_seed(), DEFAULT_SEED, "the run seed comes back with the save")
	check(SaveSystem.is_run_active(), "a loaded run is the live run")


## Un corte a mitad de escritura (temporal basura) o un temporal que no verifica nunca sustituyen
## al archivo bueno.
func _test_atomic_write() -> void:
	var path: String = SaveSystem.get_run_path()
	var good: String = FileAccess.get_file_as_string(path)
	_write(path + ".tmp", good.left(good.length() >> 1))
	check(SaveSystem.load_run(), "a half-written .tmp left by a crash does not affect loading")
	var tampered: String = good.replace(TAMPER_FROM, TAMPER_TO)
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


func _test_corrupt_run_is_rejected() -> void:
	var path: String = SaveSystem.get_run_path()
	var good: String = FileAccess.get_file_as_string(path)
	var before: String = _canon(Tracking.save_state())
	Tracking.add("silk", 99, "test")
	var changed: String = _canon(Tracking.save_state())
	_write(path, good.replace(TAMPER_FROM, TAMPER_TO))
	check(not SaveSystem.load_run(), "a run.json whose checksum fails is not loaded")
	check_eq(_canon(Tracking.save_state()), changed, "a rejected load touches no system")
	_write(path, good.replace("\"version\":1", "\"version\":99"))
	check(not SaveSystem.load_run(), "a run.json from another save version is not loaded")
	_write(path, good)
	check(SaveSystem.load_run(), "the intact file loads again")
	check_eq(_canon(Tracking.save_state()), before, "…restoring the saved state")


## Permadeath variante A (§12.7): game_over borra la partida; solo el perfil sobrevive.
func _test_permadeath() -> void:
	SaveSystem.reset_for_new_run()
	check(SaveSystem.save_run(), "a run is saved at bedtime")
	SaveSystem.reset_for_new_run()
	EventBus.game_over.emit("starvation", "the_gap", {})
	check(SaveSystem.run_exists(), "a process with no live run (tests, menus) deletes nothing")
	EventBus.run_started.emit(DEFAULT_SEED)
	check(SaveSystem.is_run_active(), "run_started marks the live run")
	check(SaveSystem.save_run(), "saved again")
	EventBus.game_over.emit("investigation_conclusive", "the_file", Tracking.get_snapshot())
	check(not SaveSystem.run_exists(), "game_over deletes run.json")
	check(not FileAccess.file_exists(SaveSystem.get_run_path() + ".tmp"), "…and any temporary")
	check(not SaveSystem.is_run_active(), "no live run after the game over")
	check(not SaveSystem.load_run(), "there is nothing to load back: no undo")
	check(SaveSystem.get_unlocked_endings().has("the_file"), "the ending is unlocked in the profile")
	var profile: Dictionary = SaveSystem.read_verified(SaveSystem.get_profile_path(), "profile")
	check((profile.get("profile", {}).get("unlocked_endings", []) as Array).has("the_file"),
			"the unlocked ending is written to profile.json")
	check(SaveSystem.save_run(), "the next run saves")
	EventBus.game_over.emit("ownership_notarised", "the_butcher", {"ruin_tier": "husk"})
	var unlocked: Array[String] = SaveSystem.get_unlocked_endings()
	check(unlocked.has("the_butcher") and unlocked.has("the_butcher@husk"),
			"a victory also unlocks its ruin variant")
	new_run(DEFAULT_SEED, false)
	check(FileAccess.file_exists(SaveSystem.get_profile_path()), "profile.json survives the new run")
	SaveSystem.forget_profile()
	check(SaveSystem.load_profile(), "the profile loads in the next session")
	check(SaveSystem.get_unlocked_endings().has("the_file"), "the gallery survives permadeath")


# ─── Utilidades ───────────────────────────────────────────────

## {autoload: save_state() en forma canónica (JSON ordenado, números como en el archivo)}.
func _states() -> Dictionary:
	var out: Dictionary = {}
	for autoload_name: String in SaveSystem.get_persistent_autoloads():
		out[autoload_name] = _canon(autoload(autoload_name).call("save_state"))
	return out


static func _canon(value: Variant) -> String:
	var json: JSON = JSON.new()
	json.parse(JSON.stringify(value, "", true, true))
	return JSON.stringify(json.data, "", true, true)


static func _autoload_names() -> Array[String]:
	var out: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = str(property["name"])
		if property_name.begins_with("autoload/"):
			out.append(property_name.trim_prefix("autoload/"))
	return out


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
	check(not DirAccess.dir_exists_absolute(_dir), "the case leaves no files behind")
	check_eq(SaveSystem.get_run_path(), SaveSystemNode.RUN_PATH, "storage back on user://run.json")
	check_eq(SaveSystem.get_profile_path(), SaveSystemNode.PROFILE_PATH, "…and user://profile.json")
