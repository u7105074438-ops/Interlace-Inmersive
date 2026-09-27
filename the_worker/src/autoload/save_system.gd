# save_system.gd — Persistencia (§12.7, §19.13): la partida en curso (run.json, escritura atómica verificada) y el perfil (profile.json: ajustes y galería de finales).
# PROPIETARIO DE: los dos archivos de persistencia, los ajustes del perfil, los finales desbloqueados, las marcas de partida viva, cargada y terminada (§19.13) y los estados de nodos de escena leídos y aún sin reclamar.
# ESCUCHA: run_started, game_over.
class_name SaveSystemNode
extends Node

## Manual §12.7, §19.13, PASO 31; BUILD_NOTES §2, §5, §11. Emite: run_loaded.
## PARTIDA (RUN_PATH):
##  · save_run() recorre la lista de autoloads de project.godot, en su orden, y guarda el
##    save_state() de cada uno que implemente save_state y load_state, SIN conocer su contenido,
##    en un único JSON: {"version", "day", "checksum", "systems": {Autoload: estado}}.
##    Cada estado va SIN PÉRDIDA: base64 de var_to_bytes (el JSON de Godot no devuelve idénticos
##    los float de 17 cifras y convierte int↔float y las claves a texto). Así load_state() recibe
##    exactamente el Dictionary que dio save_state() (tipos, float, arrays tipados, claves int).
##    checksum = MD5 del texto exacto de "systems".
##  · Escritura atómica: se escribe RUN_PATH + ".tmp", se relee y se verifica (texto idéntico, JSON
##    válido, versión y checksum) y solo entonces se renombra sobre el destino
##    (DirAccess.rename_absolute). Si algo falla se borra el .tmp y el archivo bueno no se toca.
##    Recuperación: si el destino falta o no verifica y el .tmp sí (corte tras verificar y antes o
##    durante el renombrado), la lectura promueve el .tmp y lo usa (read_or_recover).
##  · load_run(): verifica y decodifica el archivo ANTES de tocar ningún sistema; después llama a
##    load_state() de cada autoload en el orden de project.godot y emite run_loaded(día).
##  · NODOS DE ESCENA con estado de partida (CaughtHandler, DutySystem: no son autoloads): los que
##    están en el grupo SCENE_GROUP e implementan save_state/load_state se guardan en el mismo
##    "systems" con la clave "scene:<clave>" (clave = get_save_key() o el nombre del nodo). load_run
##    se lo entrega a los que ya estén en el árbol (después de los autoloads) y guarda el resto:
##    un nodo que se crea después lo pide con claim_scene_state(clave) en su _ready. Una partida
##    nueva (run_started, reset_for_new_run) olvida lo no reclamado.
##  · Se guarda SOLO al dormir (§12.7): el mundo llama a save_run() al terminar la secuencia de
##    sueño. Nada se guarda automáticamente.
##  · Permadeath, variante A: game_over termina la partida del proceso: save_run() se niega
##    (is_run_over) hasta run_started o reset_for_new_run(). Si había una partida viva (la marcan
##    run_started, load_run() y save_run(); la quitan delete_run() y reset_for_new_run()),
##    delete_run() (run.json y su .tmp) y desbloqueo en el perfil del final que decide Tracking
##    (evaluate_ending(): Tracking ya registró la causa; el ending_id del payload solo si Tracking
##    no da uno válido; si discrepan, aviso) más "<final>@<empire|husk>" (Tracking.get_ruin_tier)
##    si tiene variantes; el perfil se guarda en disco. Un proceso que no juega (tests) no borra.
##  · run_started = partida NUEVA (game_root la emite con el mundo listo; tras load_run() emite
##    run_loaded): borra el run.json de un personaje anterior (§12.7: un único archivo), salvo que
##    esta partida venga de load_run().
## PERFIL (PROFILE_PATH): {"version", "checksum", "profile": {"settings", "unlocked_endings"}}.
##  · Ajustes (contrato de SettingsMenu): language, text_size 0-2, high_contrast, colorblind_safe,
##    clock_speed, difficulty, max_agents, subtitles, music_volume, sfx_volume, skip_seen_intro,
##    opening_seen. "skip_tutorial_seen" es alias de skip_seen_intro (SETTING_ALIASES: una sola
##    bandera). Por defecto: balance menus.ajustes_por_defecto. set_setting valida y acota
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
const SCENE_GROUP := "run_persistent_nodes"
const SCENE_KEY_PREFIX := "scene:"
const SCENE_KEY_GETTER := "get_save_key"
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
const ENDING_HAS_VARIANTS := "has_ruin_variants"
const ENDING_VARIANTS := "epilogue_variants"
const TRACKING_EVALUATOR := "evaluate_ending"
const TRACKING_TIER := "get_ruin_tier"
## Nombre del ajuste pedido → clave con la que se guarda.
const SETTING_ALIASES: Dictionary = {"skip_tutorial_seen": "skip_seen_intro"}

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
const WARN_RUN_OVER := "SaveSystem: la partida terminó (game_over); no se guarda"
const WARN_RECOVERED := "SaveSystem: '%s' recuperado sobre '%s' (escritura interrumpida)"
const WARN_ENDING_MISMATCH := "SaveSystem: game_over trae el final '%s'; Tracking decide '%s'"

var _run_path: String = RUN_PATH
var _profile_path: String = PROFILE_PATH
var _run_active: bool = false
## Tras game_over: nada se guarda hasta una partida nueva.
var _run_over: bool = false
## La partida en curso salió de load_run() (run_started no debe borrar su archivo).
var _run_loaded: bool = false
## Solo los ajustes fijados (por el jugador o leídos del perfil); el resto, por defecto.
var _settings: Dictionary = {}
var _unlocked: Array[String] = []
var _profile_loaded: bool = false
var _defaults: Dictionary = {}
## "clave de nodo" → estado leído por load_run() que ningún nodo del árbol recogió todavía.
var _pending_scene_states: Dictionary = {}


func _ready() -> void:
	EventBus.run_started.connect(_on_run_started)
	EventBus.game_over.connect(_on_game_over)


## El perfil no pertenece a la partida: sobrevive. Solo se olvida la partida viva.
func reset_for_new_run() -> void:
	_run_active = false
	_run_over = false
	_run_loaded = false
	_pending_scene_states.clear()


# ═══ Partida (§19.13) ═════════════════════════════════════════════════

## Escritura atómica: run.json.tmp → verificar → renombrar. false tras game_over (permadeath).
func save_run() -> bool:
	if _run_over:
		push_warning(WARN_RUN_OVER)
		return false
	var header: Dictionary = {K_VERSION: SAVE_VERSION, K_DAY: GameClock.get_day()}
	var text: String = compose(header, K_SYSTEMS, _collect_states())
	var ok: bool = write_atomic(_run_path, text, K_SYSTEMS)
	if ok:
		_run_active = true
	return ok


func load_run() -> bool:
	var data: Dictionary = read_or_recover(_run_path, K_SYSTEMS)
	var states: Variant = decode_systems(data.get(K_SYSTEMS)) if not data.is_empty() else null
	if not states is Dictionary:
		if FileAccess.file_exists(_run_path):
			push_warning(WARN_CORRUPT % _run_path)
		return false
	for autoload_name: String in get_persistent_autoloads():
		if (states as Dictionary).has(autoload_name):
			_autoload(autoload_name).call("load_state", states[autoload_name])
	_deliver_scene_states(states)
	_run_active = true
	_run_over = false
	_run_loaded = true
	EventBus.run_loaded.emit(int(data.get(K_DAY, 0)))
	return true


## Al perder la partida (permadeath): borra run.json y su temporal.
func delete_run() -> void:
	_discard(_run_path)
	_discard(_run_path + TMP_SUFFIX)
	_run_active = false
	_run_loaded = false


## También con solo un .tmp verificado (corte durante el renombrado): load_run() lo recupera.
func run_exists() -> bool:
	return FileAccess.file_exists(_run_path) \
			or not read_verified(_run_path + TMP_SUFFIX, K_SYSTEMS).is_empty()


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
	var data: Dictionary = read_or_recover(_profile_path, K_PROFILE)
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
	var setting: String = _canonical(key)
	if _settings.has(setting):
		return _settings[setting]
	var default: Variant = _get_defaults().get(setting)
	return int(default) if INT_SETTINGS.has(setting) and _is_number(default) else default


func set_setting(key: String, value: Variant) -> void:
	var setting: String = _canonical(key)
	var valid: Variant = _validated_setting(setting, value)
	if valid == null:
		push_warning(WARN_SETTING % [setting, str(value)])
		return
	_settings[setting] = valid


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


## true tras game_over hasta run_started, load_run() o reset_for_new_run(): save_run() se niega.
func is_run_over() -> bool:
	return _run_over


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


## Claves de los nodos de escena (grupo SCENE_GROUP) que se guardarían ahora, en orden de árbol.
func get_persistent_scene_nodes() -> Array[String]:
	var out: Array[String] = []
	for node: Node in _scene_nodes():
		out.append(scene_key_of(node))
	return out


## Estado de la partida cargada para el nodo de clave `save_key` que aún no lo recibió ({} si no
## hay). Se entrega una sola vez.
func claim_scene_state(save_key: String) -> Dictionary:
	var state: Variant = _pending_scene_states.get(save_key, {})
	_pending_scene_states.erase(save_key)
	return state if state is Dictionary else {}


## get_save_key() del nodo o, si no lo tiene, su nombre.
static func scene_key_of(node: Node) -> String:
	if node.has_method(SCENE_KEY_GETTER):
		return str(node.call(SCENE_KEY_GETTER))
	return String(node.name)


## Texto de archivo: cabecera + checksum (MD5 del cuerpo exacto) + cuerpo bajo `body_key`.
func compose(header: Dictionary, body_key: String, body: Variant) -> String:
	var body_text: String = JSON.stringify(body, "", true, true)
	var head: Dictionary = header.duplicate()
	head[K_CHECKSUM] = body_text.md5_text()
	var head_text: String = JSON.stringify(head, "", false, true)
	return head_text.trim_suffix(OBJECT_END) + FIELD_SEPARATOR + _body_marker(body_key) \
			+ body_text + OBJECT_END


## Estado de un sistema sin pérdida: base64 de var_to_bytes (sin objetos).
static func encode_state(state: Dictionary) -> String:
	return Marshalls.raw_to_base64(var_to_bytes(state))


## Inverso de encode_state; null si no es un estado válido.
static func decode_state(blob: Variant) -> Variant:
	if not blob is String or (blob as String).is_empty():
		return null
	var raw: PackedByteArray = Marshalls.base64_to_raw(blob)
	if raw.is_empty():
		return null
	var state: Variant = bytes_to_var(raw)
	return state if state is Dictionary else null


## {autoload: encode_state} → {autoload: estado}; null si alguno no decodifica.
static func decode_systems(body: Variant) -> Variant:
	if not body is Dictionary:
		return null
	var out: Dictionary = {}
	for autoload_name: Variant in body:
		var state: Variant = decode_state((body as Dictionary)[autoload_name])
		if state == null:
			return null
		out[str(autoload_name)] = state
	return out


## read_verified(path) o, si falta o no verifica, el .tmp verificado, que se promueve sobre path.
func read_or_recover(path: String, body_key: String) -> Dictionary:
	var data: Dictionary = read_verified(path, body_key)
	if not data.is_empty():
		return data
	var tmp: String = path + TMP_SUFFIX
	data = read_verified(tmp, body_key)
	if data.is_empty():
		return {}
	push_warning(WARN_RECOVERED % [tmp, path])
	if DirAccess.rename_absolute(tmp, path) != OK:
		push_warning(WARN_RENAME % [tmp, path])
	return data


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

## {autoload: encode_state(save_state())} + {"scene:<clave>": ...} de los nodos de escena.
func _collect_states() -> Dictionary:
	var systems: Dictionary = {}
	for autoload_name: String in get_persistent_autoloads():
		var state: Variant = _autoload(autoload_name).call("save_state")
		if state is Dictionary:
			systems[autoload_name] = encode_state(state)
	for node: Node in _scene_nodes():
		var node_state: Variant = node.call("save_state")
		if node_state is Dictionary:
			systems[SCENE_KEY_PREFIX + scene_key_of(node)] = encode_state(node_state)
	return systems


## Nodos del grupo SCENE_GROUP con save_state y load_state.
func _scene_nodes() -> Array[Node]:
	var out: Array[Node] = []
	if not is_inside_tree():
		return out
	for node: Node in get_tree().get_nodes_in_group(SCENE_GROUP):
		if node.has_method("save_state") and node.has_method("load_state"):
			out.append(node)
	return out


## Tras los autoloads: cada estado "scene:" va a su nodo; lo que no tiene nodo queda pendiente.
func _deliver_scene_states(states: Dictionary) -> void:
	_pending_scene_states.clear()
	var nodes: Dictionary = {}
	for node: Node in _scene_nodes():
		nodes[scene_key_of(node)] = node
	for key: Variant in states:
		var text: String = str(key)
		if not text.begins_with(SCENE_KEY_PREFIX):
			continue
		var save_key: String = text.trim_prefix(SCENE_KEY_PREFIX)
		if nodes.has(save_key):
			(nodes[save_key] as Node).call("load_state", states[key])
		else:
			_pending_scene_states[save_key] = states[key]


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
	var data: Dictionary = read_or_recover(_profile_path, K_PROFILE)
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


static func _canonical(key: String) -> String:
	return str(SETTING_ALIASES.get(key, key))


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

## Partida nueva: el run.json de un personaje anterior ya no vale (§12.7: un único archivo).
func _on_run_started(_run_seed: int) -> void:
	if not _run_loaded:
		delete_run()
		_pending_scene_states.clear()
	_run_active = true
	_run_over = false


## Permadeath (§12.7): la partida muere con el personaje; solo el perfil sobrevive.
func _on_game_over(_cause: String, ending_id: String, _tracking_snapshot: Dictionary) -> void:
	_run_over = true
	if not _run_active:
		return
	delete_run()
	var final_id: String = _final_ending(ending_id)
	if final_id.is_empty():
		return
	unlock_ending(final_id)
	if Tracking.has_method(TRACKING_TIER):
		var variant_id: String = final_id + VARIANT_SEPARATOR + str(Tracking.call(TRACKING_TIER))
		if is_valid_ending_id(variant_id):
			unlock_ending(variant_id)
	save_profile()


## El final que decide Tracking (autoload anterior: ya registró la causa del game_over); el del
## payload solo si Tracking no da uno válido.
func _final_ending(payload_id: String) -> String:
	var tracked: String = ""
	if Tracking.has_method(TRACKING_EVALUATOR):
		tracked = str(Tracking.call(TRACKING_EVALUATOR))
	if not is_valid_ending_id(tracked):
		return payload_id if is_valid_ending_id(payload_id) else ""
	if not payload_id.is_empty() and payload_id != tracked:
		push_warning(WARN_ENDING_MISMATCH % [payload_id, tracked])
	return tracked
