# save_system.gd — Persistencia (§12.7, §19.13): la partida en curso (run.json, escritura atómica verificada) y el perfil (profile.json: ajustes y galería de finales).
# PROPIETARIO DE: los dos archivos de persistencia, los ajustes del perfil, los finales desbloqueados y la marca de partida viva (§19.13).
# ESCUCHA: run_started, game_over.
class_name SaveSystemNode
extends Node

## Manual §12.7, §19.13, PASO 31; BUILD_NOTES §2, §5, §11. Emite: run_loaded.
## PARTIDA (RUN_PATH):
##  · save_run() recorre la lista de autoloads de project.godot, en su orden, y guarda el
##    save_state() de cada uno que implemente save_state y load_state, SIN conocer su contenido,
##    en un único JSON: {"version", "day", "checksum", "systems": {Autoload: estado}}.
##    checksum = MD5 del texto exacto de "systems", serializado con precisión completa (los float
##    vuelven idénticos al cargar).
##  · Escritura atómica: se escribe RUN_PATH + ".tmp", se relee y se verifica (texto idéntico, JSON
##    válido, versión y checksum) y solo entonces se renombra sobre el destino
##    (DirAccess.rename_absolute). Si algo falla se borra el .tmp y el archivo bueno no se toca.
##  · load_run(): verifica el archivo ANTES de tocar ningún sistema; después llama a load_state()
##    de cada autoload en el orden de project.godot y emite run_loaded(día).
##  · Se guarda SOLO al dormir (§12.7): el mundo llama a save_run() al terminar la secuencia de
##    sueño. Nada se guarda automáticamente.
##  · Permadeath, variante A: game_over → delete_run() (run.json y su .tmp) y desbloqueo del final
##    en el perfil (más "<final>@<empire|husk>" si tiene variantes de ruina) guardado en disco,
##    siempre que haya una partida viva: la marcan run_started, load_run() y save_run(); la
##    quitan delete_run() y reset_for_new_run(). Un proceso que no juega (tests) no borra nada.
## PERFIL (PROFILE_PATH): {"version", "checksum", "profile": {"settings", "unlocked_endings"}}.
##  · Ajustes (contrato de SettingsMenu): language, text_size 0-2, high_contrast, colorblind_safe,
##    clock_speed, difficulty, max_agents, subtitles, music_volume, sfx_volume, skip_seen_intro,
##    opening_seen. Por defecto: balance menus.ajustes_por_defecto. set_setting valida y acota
##    (tipo del valor por defecto, text_size y max_agents siempre int; rangos menus.escala_texto, menus.velocidad_reloj,
##    menus.agentes.min..lod.max_agentes_total, volumen 0..1; idiomas cargados; presets de
##    dificultad). Un valor inválido se ignora. Claves desconocidas: se guardan tal cual si son
##    escalares (banderas del perfil). get_setting → guardado, si no por defecto, si no null.
##  · Hasta load_profile() (arranque: SettingsMenu.load_and_apply) todo vive en memoria y los
##    tests leen los valores por defecto. save_profile() sin load_profile() previo fusiona antes
##    el perfil del disco (manda lo cambiado en esta sesión): nunca pisa el perfil del jugador.
##  · Aplicar un ajuste (idioma, volumen, velocidad...) es de quien lo cambia (SettingsMenu) o de su
##    sistema lector. SaveSystem solo lo almacena.
##  · set_storage_dir(dir): extra para tests y herramientas; redirige ambos archivos.

const RUN_PATH := "user://run.json"
const PROFILE_PATH := "user://profile.json"
const SAVE_VERSION := 1
const DEFAULT_DIR := "user://"
const TMP_SUFFIX := ".tmp"
const AUTOLOAD_PREFIX := "autoload/"
const K_VERSION := "version"
const K_DAY := "day"
const K_CHECKSUM := "checksum"
const K_SYSTEMS := "systems"
const K_PROFILE := "profile"
const K_SETTINGS := "settings"
const K_ENDINGS := "unlocked_endings"
const KEY_VALUE_SEPARATOR := ":"
const FIELD_SEPARATOR := ","
const OBJECT_END := "}"
const VARIANT_SEPARATOR := "@"
const SNAPSHOT_RUIN_TIER := "ruin_tier"
const ENDING_HAS_VARIANTS := "has_ruin_variants"
const ENDING_VARIANTS := "epilogue_variants"

# Ajustes con validación propia (el resto: tipo del valor por defecto).
const SET_LANGUAGE := "language"
const SET_DIFFICULTY := "difficulty"
const SET_TEXT_SIZE := "text_size"
const SET_CLOCK_SPEED := "clock_speed"
const SET_MAX_AGENTS := "max_agents"
## Enteros del contrato (el JSON de balance los entrega como float).
const INT_SETTINGS: Array[String] = [SET_TEXT_SIZE, SET_MAX_AGENTS]
const VOLUME_SETTINGS: Array[String] = ["music_volume", "sfx_volume"]
const VOLUME_MIN := 0.0
const VOLUME_MAX := 1.0
const B_DEFAULTS := "menus.ajustes_por_defecto"
const B_TEXT_SCALES := "menus.escala_texto"
const B_CLOCK_MIN := "menus.velocidad_reloj.min"
const B_CLOCK_MAX := "menus.velocidad_reloj.max"
const B_AGENTS_MIN := "menus.agentes.min"
const B_AGENTS_MAX := "lod.max_agentes_total"

const WARN_WRITE := "SaveSystem: no se pudo escribir '%s'"
const WARN_VERIFY := "SaveSystem: verificación fallida de '%s'; el destino no se toca"
const WARN_RENAME := "SaveSystem: no se pudo renombrar '%s' sobre '%s'"
const WARN_CORRUPT := "SaveSystem: '%s' no es válido (JSON, versión o checksum)"
const WARN_SETTING := "SaveSystem: ajuste '%s' con valor no válido (%s)"
const WARN_ENDING := "SaveSystem: final desconocido '%s'"

var _run_path: String = RUN_PATH
var _profile_path: String = PROFILE_PATH
var _run_active: bool = false
## Solo los ajustes fijados (por el jugador o leídos del perfil); el resto, por defecto.
var _settings: Dictionary = {}
var _unlocked: Array[String] = []
var _profile_loaded: bool = false
var _defaults: Dictionary = {}


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.game_over.connect(_on_game_over)


## El perfil no pertenece a la partida: sobrevive. Solo se olvida la partida viva.
func reset_for_new_run() -> void:
	_run_active = false


# ═══ Partida (§19.13) ═════════════════════════════════════════════════

## Escritura atómica: run.json.tmp → verificar → renombrar.
func save_run() -> bool:
	var header: Dictionary = {K_VERSION: SAVE_VERSION, K_DAY: GameClock.get_day()}
	var text: String = compose(header, K_SYSTEMS, _collect_states())
	var ok: bool = write_atomic(_run_path, text, K_SYSTEMS)
	if ok:
		_run_active = true
	return ok


func load_run() -> bool:
	var data: Dictionary = read_verified(_run_path, K_SYSTEMS)
	if data.is_empty():
		if FileAccess.file_exists(_run_path):
			push_warning(WARN_CORRUPT % _run_path)
		return false
	var systems: Dictionary = data[K_SYSTEMS]
	for autoload_name: String in get_persistent_autoloads():
		var state: Variant = systems.get(autoload_name)
		if state is Dictionary:
			_autoload(autoload_name).call("load_state", state)
	_run_active = true
	EventBus.run_loaded.emit(int(data.get(K_DAY, 0)))
	return true


## Al perder la partida (permadeath): borra run.json y su temporal.
func delete_run() -> void:
	_discard(_run_path)
	_discard(_run_path + TMP_SUFFIX)
	_run_active = false


func run_exists() -> bool:
	return FileAccess.file_exists(_run_path)


# ═══ Perfil (§19.13) ══════════════════════════════════════════════════

func save_profile() -> bool:
	if not _profile_loaded:
		_merge_disk_profile()
	var body: Dictionary = {K_SETTINGS: _settings.duplicate(true), K_ENDINGS: _unlocked.duplicate()}
	return write_atomic(_profile_path, compose({K_VERSION: SAVE_VERSION}, K_PROFILE, body),
			K_PROFILE)


## true si se leyó un perfil válido; si falta o está dañado quedan los valores por defecto.
func load_profile() -> bool:
	_profile_loaded = true
	_settings.clear()
	_unlocked.clear()
	var data: Dictionary = read_verified(_profile_path, K_PROFILE)
	if data.is_empty():
		if FileAccess.file_exists(_profile_path):
			push_warning(WARN_CORRUPT % _profile_path)
		return false
	_absorb_profile(data[K_PROFILE])
	return true


## "<ending_id>" o "<ending_id>@<empire|husk>" (variante de ruina vista). Solo memoria: guarda
## quien llama con save_profile() (game_over lo hace solo).
func unlock_ending(ending_id: String) -> void:
	if not is_valid_ending_id(ending_id):
		push_warning(WARN_ENDING % ending_id)
		return
	if not _unlocked.has(ending_id):
		_unlocked.append(ending_id)


func get_unlocked_endings() -> Array[String]:
	return _unlocked.duplicate()


func get_setting(key: String) -> Variant:
	if _settings.has(key):
		return _settings[key]
	var default: Variant = _get_defaults().get(key)
	return int(default) if INT_SETTINGS.has(key) and _is_number(default) else default


func set_setting(key: String, value: Variant) -> void:
	var valid: Variant = _validated_setting(key, value)
	if valid == null:
		push_warning(WARN_SETTING % [key, str(value)])
		return
	_settings[key] = valid


# ═══ Extensiones públicas ═════════════════════════════════════════════

## Tests y herramientas: guarda run.json y profile.json en `dir` (por defecto "user://").
func set_storage_dir(dir: String) -> void:
	var base: String = dir if not dir.is_empty() else DEFAULT_DIR
	DirAccess.make_dir_recursive_absolute(base)
	_run_path = base.path_join(RUN_PATH.get_file())
	_profile_path = base.path_join(PROFILE_PATH.get_file())


func get_run_path() -> String:
	return _run_path


func get_profile_path() -> String:
	return _profile_path


## Olvida el perfil en memoria (vuelven los valores por defecto) sin tocar el disco; el próximo
## save_profile() fusionará antes el del disco, como en un proceso recién arrancado.
func forget_profile() -> void:
	_settings.clear()
	_unlocked.clear()
	_profile_loaded = false


## true tras run_started, load_run() o save_run(); false tras delete_run() o un reset.
func is_run_active() -> bool:
	return _run_active


## Autoloads (orden de project.godot) que implementan save_state y load_state.
func get_persistent_autoloads() -> Array[String]:
	var out: Array[String] = []
	for property: Dictionary in ProjectSettings.get_property_list():
		var property_name: String = str(property.get("name", ""))
		if not property_name.begins_with(AUTOLOAD_PREFIX):
			continue
		var autoload_name: String = property_name.trim_prefix(AUTOLOAD_PREFIX)
		var node: Node = _autoload(autoload_name)
		if node != null and node != self and node.has_method("save_state") \
				and node.has_method("load_state"):
			out.append(autoload_name)
	return out


## Texto de archivo: cabecera + checksum (MD5 del cuerpo exacto) + cuerpo bajo `body_key`.
func compose(header: Dictionary, body_key: String, body: Variant) -> String:
	var body_text: String = JSON.stringify(body, "", true, true)
	var head: Dictionary = header.duplicate()
	head[K_CHECKSUM] = body_text.md5_text()
	var head_text: String = JSON.stringify(head, "", false, true)
	return head_text.trim_suffix(OBJECT_END) + FIELD_SEPARATOR + _body_marker(body_key) \
			+ body_text + OBJECT_END


## Diccionario del archivo si es íntegro (JSON, versión, checksum, cuerpo); si no, {}.
func read_verified(path: String, body_key: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	return parse_verified(FileAccess.get_file_as_string(path), body_key)


func parse_verified(text: String, body_key: String) -> Dictionary:
	var marker: String = _body_marker(body_key)
	var at: int = text.find(marker)
	if at < 0 or not text.ends_with(OBJECT_END):
		return {}
	var start: int = at + marker.length()
	var body_text: String = text.substr(start, text.length() - start - OBJECT_END.length())
	var json: JSON = JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary:
		return {}
	var data: Dictionary = json.data
	if int(data.get(K_VERSION, -1)) != SAVE_VERSION or not data.get(body_key) is Dictionary:
		return {}
	if str(data.get(K_CHECKSUM, "")) != body_text.md5_text():
		return {}
	return data


## Escritura atómica de `text` en `target`: temporal → relectura y verificación → renombrado.
## Si la verificación falla el temporal se borra y `target` queda intacto.
func write_atomic(target: String, text: String, body_key: String) -> bool:
	var tmp: String = target + TMP_SUFFIX
	DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if not _write_text(tmp, text):
		push_warning(WARN_WRITE % tmp)
		_discard(tmp)
		return false
	var written: String = FileAccess.get_file_as_string(tmp)
	if written != text or parse_verified(written, body_key).is_empty():
		push_warning(WARN_VERIFY % tmp)
		_discard(tmp)
		return false
	if DirAccess.rename_absolute(tmp, target) != OK:
		push_warning(WARN_RENAME % [tmp, target])
		_discard(tmp)
		return false
	return true


## "<final>" o "<final>@<variante>" con variante de ruina existente en endings.json.
func is_valid_ending_id(ending_id: String) -> bool:
	var parts: PackedStringArray = ending_id.split(VARIANT_SEPARATOR)
	var ending: Dictionary = Database.get_ending(parts[0])
	if ending.is_empty() or parts.size() > 2:
		return false
	if parts.size() == 1:
		return true
	var variants: Variant = ending.get(ENDING_VARIANTS, {})
	return bool(ending.get(ENDING_HAS_VARIANTS, false)) and variants is Dictionary \
			and (variants as Dictionary).has(parts[1])


# ═══ Internos: partida ════════════════════════════════════════════════

func _collect_states() -> Dictionary:
	var systems: Dictionary = {}
	for autoload_name: String in get_persistent_autoloads():
		var state: Variant = _autoload(autoload_name).call("save_state")
		if state is Dictionary:
			systems[autoload_name] = state
	return systems


func _autoload(autoload_name: String) -> Node:
	if not is_inside_tree():
		return null
	return get_tree().root.get_node_or_null(NodePath(autoload_name))


static func _body_marker(body_key: String) -> String:
	return JSON.stringify(body_key) + KEY_VALUE_SEPARATOR


static func _write_text(path: String, text: String) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var ok: bool = file.store_string(text)
	file.flush()
	var error: Error = file.get_error()
	file.close()
	return ok and error == OK


static func _discard(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


# ═══ Internos: perfil ═════════════════════════════════════════════════

## Primer guardado sin load_profile(): adopta lo del disco que no se haya cambiado en la sesión.
func _merge_disk_profile() -> void:
	_profile_loaded = true
	var data: Dictionary = read_verified(_profile_path, K_PROFILE)
	if not data.is_empty():
		_absorb_profile(data[K_PROFILE])


## Incorpora un perfil leído sin pisar los ajustes ya fijados en memoria.
func _absorb_profile(profile: Dictionary) -> void:
	var settings: Variant = profile.get(K_SETTINGS, {})
	if settings is Dictionary:
		for key: Variant in settings:
			var valid: Variant = _validated_setting(str(key), settings[key])
			if valid != null and not _settings.has(str(key)):
				_settings[str(key)] = valid
	var endings: Variant = profile.get(K_ENDINGS, [])
	if endings is Array:
		for ending_id: Variant in endings:
			if is_valid_ending_id(str(ending_id)) and not _unlocked.has(str(ending_id)):
				_unlocked.append(str(ending_id))


func _get_defaults() -> Dictionary:
	if _defaults.is_empty() and Database.has_balance(B_DEFAULTS):
		var raw: Variant = Database.get_balance(B_DEFAULTS)
		_defaults = raw if raw is Dictionary else {}
	return _defaults


## Valor normalizado (tipo del valor por defecto, acotado) o null si no es válido.
func _validated_setting(key: String, value: Variant) -> Variant:
	var default: Variant = _get_defaults().get(key)
	match key:
		SET_LANGUAGE:
			return _validated_language(value)
		SET_DIFFICULTY:
			var ok: bool = value is String and Database.get_difficulty_presets().has(value)
			return value if ok else null
	if default == null:
		return value if (value is bool or _is_number(value) or value is String) else null
	if default is bool:
		return value if value is bool else null
	if default is int or default is float:
		if not _is_number(value):
			return null
		var bounded: float = clampf(float(value), _setting_min(key), _setting_max(key))
		return roundi(bounded) if (default is int or INT_SETTINGS.has(key)) else bounded
	return value if typeof(value) == typeof(default) else null


func _validated_language(value: Variant) -> Variant:
	if not value is String or (value as String).is_empty():
		return null
	var locales: PackedStringArray = TranslationServer.get_loaded_locales()
	return value if locales.is_empty() or locales.has(value) else null


func _setting_min(key: String) -> float:
	match key:
		SET_TEXT_SIZE:
			return 0.0
		SET_CLOCK_SPEED:
			return Database.get_balance_float(B_CLOCK_MIN)
		SET_MAX_AGENTS:
			return Database.get_balance_float(B_AGENTS_MIN)
	return VOLUME_MIN if VOLUME_SETTINGS.has(key) else -INF


func _setting_max(key: String) -> float:
	match key:
		SET_TEXT_SIZE:
			return float((Database.get_balance(B_TEXT_SCALES) as Array).size() - 1)
		SET_CLOCK_SPEED:
			return Database.get_balance_float(B_CLOCK_MAX)
		SET_MAX_AGENTS:
			return Database.get_balance_float(B_AGENTS_MAX)
	return VOLUME_MAX if VOLUME_SETTINGS.has(key) else INF


static func _is_number(value: Variant) -> bool:
	return value is int or value is float


# ═══ Oyentes ══════════════════════════════════════════════════════════

func _on_run_started(_run_seed: int) -> void:
	_run_active = true


## Permadeath (§12.7): la partida muere con el personaje; solo el perfil sobrevive.
func _on_game_over(_cause: String, ending_id: String, tracking_snapshot: Dictionary) -> void:
	if not _run_active:
		return
	delete_run()
	if not is_valid_ending_id(ending_id):
		return
	unlock_ending(ending_id)
	var tier: String = str(tracking_snapshot.get(SNAPSHOT_RUIN_TIER, ""))
	if tier.is_empty() and Tracking.has_method("get_ruin_tier"):
		tier = Tracking.get_ruin_tier()
	var variant_id: String = ending_id + VARIANT_SEPARATOR + tier
	if is_valid_ending_id(variant_id):
		unlock_ending(variant_id)
	save_profile()
