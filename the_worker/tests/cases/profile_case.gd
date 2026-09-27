# profile_case.gd — Cuerpo de test_profile (§12.7, §19.13): ajustes y galería de finales del perfil persisten entre sesiones y partidas.
# PROPIETARIO DE: el directorio temporal de perfil del caso (lo crea y lo borra).
# ESCUCHA: nada.
extends TestCase

const STORAGE_FORMAT := "user://test_profile_%d"
const DEFAULTS := "menus.ajustes_por_defecto"

var _dir: String = ""


func run_case() -> void:
	check(new_run(DEFAULT_SEED, false), "Database loaded the data files")
	_dir = STORAGE_FORMAT % OS.get_process_id()
	SaveSystem.set_storage_dir(_dir)
	SaveSystem.forget_profile()
	_test_defaults()
	_test_validation()
	_test_endings_gallery()
	_test_persistence()
	_test_merge_never_clobbers()
	_test_recovery()
	_test_corrupt_profile()
	_cleanup()


func _test_defaults() -> void:
	var defaults: Dictionary = Database.get_balance(DEFAULTS)
	for key: String in defaults:
		check(TestCase.values_equal(SaveSystem.get_setting(key), defaults[key]),
				"default %s = %s" % [key, str(defaults[key])])
	check_eq(SaveSystem.get_setting("text_size"), 1, "medium text by default")
	check_eq(typeof(SaveSystem.get_setting("max_agents")), TYPE_INT, "integer defaults come back as int")
	check_eq(SaveSystem.get_setting("language"), "en", "English is the base language")
	check(SaveSystem.get_setting("no_such_setting") == null, "unknown setting → null")
	check(SaveSystem.get_unlocked_endings().is_empty(), "a new profile has no endings unlocked")


func _test_validation() -> void:
	_expect("text_size", 2, 2, "text size large")
	_expect("text_size", 7, 2, "text size clamps to the three levels (0-2)")
	_expect("text_size", -3, 0, "text size clamps at small")
	_expect("text_size", "huge", 0, "a non-numeric text size is ignored")
	_expect("clock_speed", 5.0, Database.get_balance_float("menus.velocidad_reloj.max"), "clock speed max")
	_expect("clock_speed", 0.1, Database.get_balance_float("menus.velocidad_reloj.min"), "clock speed min")
	_expect("max_agents", 10, Database.get_balance_int("menus.agentes.min"), "max agents floor")
	_expect("max_agents", 9999, Database.get_balance_int("lod.max_agentes_total"), "max agents ceiling")
	_expect("music_volume", 1.5, 1.0, "volume clamps to 1")
	_expect("sfx_volume", -0.5, 0.0, "volume clamps to 0")
	_expect("high_contrast", true, true, "high contrast on")
	_expect("high_contrast", "yes", true, "a non-bool toggle is ignored")
	_expect("subtitles", false, false, "subtitles off")
	_expect("difficulty", "auditoria", "auditoria", "difficulty preset")
	_expect("difficulty", "nightmare", "auditoria", "unknown preset ignored")
	_expect("language", "es", "es", "Spanish")
	_expect("language", "xx", "es", "unknown locale ignored")
	check_eq(SaveSystem.get_setting("skip_tutorial_seen"), false, "skip_tutorial_seen defaults to false")
	_expect("skip_seen_intro", true, true, "skip seen intro")
	check_eq(SaveSystem.get_setting("skip_tutorial_seen"), true, "skip_tutorial_seen is the same flag (alias)")
	_expect("tutorial_seen", true, true, "profile flags without default are kept")
	check_eq(typeof(SaveSystem.get_setting("text_size")), TYPE_INT, "int settings stay int")
	check_eq(typeof(SaveSystem.get_setting("clock_speed")), TYPE_FLOAT, "float settings stay float")


func _expect(key: String, value: Variant, expected: Variant, label: String) -> void:
	SaveSystem.set_setting(key, value)
	check(TestCase.values_equal(SaveSystem.get_setting(key), expected),
			"%s (%s → %s)" % [label, str(value), str(SaveSystem.get_setting(key))])


func _test_endings_gallery() -> void:
	SaveSystem.unlock_ending("the_worker")
	SaveSystem.unlock_ending("the_worker@husk")
	SaveSystem.unlock_ending("the_worker")
	SaveSystem.unlock_ending("the_gap@husk")
	SaveSystem.unlock_ending("the_worker@gold")
	SaveSystem.unlock_ending("ending_test")
	check_eq(SaveSystem.get_unlocked_endings(), ["the_worker", "the_worker@husk"] as Array[String],
			"unlocks are unique; unknown endings and variants are refused")


func _test_persistence() -> void:
	check(SaveSystem.save_profile(), "save_profile() writes profile.json")
	check(not FileAccess.file_exists(SaveSystem.get_profile_path() + ".tmp"), "atomic write leaves no .tmp")
	var saved: Dictionary = _snapshot()
	SaveSystem.forget_profile()
	check_eq(SaveSystem.get_setting("text_size"), 1, "a new session starts from defaults")
	check(SaveSystem.load_profile(), "load_profile() reads profile.json")
	check_eq(_snapshot(), saved, "every setting and the gallery survive the session")
	check_eq(typeof(SaveSystem.get_setting("max_agents")), TYPE_INT, "ints survive the JSON round trip as ints")
	new_run(DEFAULT_SEED + 1, false)
	check_eq(_snapshot(), saved, "a new run does not touch the profile (§12.7)")


## Un proceso que nunca leyó el perfil (herramienta, test) no lo pisa al guardar.
func _test_merge_never_clobbers() -> void:
	SaveSystem.forget_profile()
	SaveSystem.set_setting("music_volume", 0.25)
	SaveSystem.unlock_ending("the_file")
	check(SaveSystem.save_profile(), "saving without load_profile() first")
	SaveSystem.forget_profile()
	SaveSystem.load_profile()
	check_eq(SaveSystem.get_setting("text_size"), 0, "settings stored on disk were kept")
	check_eq(SaveSystem.get_setting("language"), "es", "language kept")
	check_near(float(SaveSystem.get_setting("music_volume")), 0.25, 0.0001, "the session's change was applied")
	var unlocked: Array[String] = SaveSystem.get_unlocked_endings()
	check(unlocked.has("the_worker") and unlocked.has("the_file"), "gallery merged, nothing lost")


## Corte durante el renombrado: profile.json falta y su .tmp verificado se recupera.
func _test_recovery() -> void:
	var path: String = SaveSystem.get_profile_path()
	var saved: Dictionary = _snapshot()
	DirAccess.rename_absolute(path, path + ".tmp")
	SaveSystem.forget_profile()
	check(SaveSystem.load_profile(), "profile.json missing + verified .tmp → the profile is recovered")
	check_eq(_snapshot(), saved, "…with every setting and ending")
	check(FileAccess.file_exists(path) and not FileAccess.file_exists(path + ".tmp"), "…promoted to profile.json")


func _test_corrupt_profile() -> void:
	var path: String = SaveSystem.get_profile_path()
	var good: String = FileAccess.get_file_as_string(path)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	file.store_string(good.left(good.length() >> 1))
	file.close()
	check(not SaveSystem.load_profile(), "a damaged profile.json is not loaded")
	check_eq(SaveSystem.get_setting("text_size"), 1, "…and defaults apply")
	check(SaveSystem.get_unlocked_endings().is_empty(), "…with an empty gallery")


func _snapshot() -> Dictionary:
	var out: Dictionary = {"endings": SaveSystem.get_unlocked_endings()}
	for key: String in ["language", "text_size", "high_contrast", "clock_speed", "difficulty",
			"max_agents", "subtitles", "music_volume", "sfx_volume", "skip_seen_intro", "tutorial_seen"]:
		out[key] = SaveSystem.get_setting(key)
	return out


func _cleanup() -> void:
	for file_name: String in ["profile.json", "profile.json.tmp", "run.json"]:
		DirAccess.remove_absolute(_dir.path_join(file_name))
	DirAccess.remove_absolute(_dir)
	SaveSystem.set_storage_dir("")
	SaveSystem.forget_profile()
	check(not DirAccess.dir_exists_absolute(_dir), "the case leaves no files behind")
