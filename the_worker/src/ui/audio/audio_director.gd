# audio_director.gd — Hilo musical que se degrada con la sospecha, efectos con paneo, ambientes y subtítulos.
# PROPIETARIO DE: reproductores y buses Music/SFX/Ambience, estado del hilo musical, enfriamientos de sonido y el ajuste phone_silenced.
# ESCUCHA: suspicion_changed, floor_changed, room_entered, player_caught_redhanded, noise_emitted, phone_message_received, alert_level_changed, card_reader_logged, npc_decided, rumor_spread, game_over, run_started.
class_name AudioDirector
extends Node

## Nodo que añade game_root.gd (o el menú, para su música). API pública para otros constructores:
##   play_sfx(id, position := NO_POSITION, volume_db := 0.0)   — ids de SfxBank.ids(); publica subtítulo
##   play_menu_music() · play_epilogue(axis, worn := false) · stop_music() · interrupt_muzak(seconds)
##   set_phone_silenced(bool) · is_masked() · refresh_settings() · AudioDirector.find(tree)
## Todo sonido informativo emite EventBus.subtitle_posted(clave, posición_mundo, importancia) (§13.10)
## con el contrato de SubtitleFeed: posición de mundo o Vector2.INF (sin posición: el móvil, la
## alarma, el hilo musical); importancia 0 ambiente · 1 informativo · 2 peligro.
## Un solo director activo por proceso: el último que entra al árbol manda y el anterior queda
## en reposo (sin señales, sin sonido, fuera del grupo) hasta que el nuevo sale. Así un
## MenuAudioDirector y el de la partida nunca duplican efectos ni subtítulos.
## El móvil que vibra (§14.10) es ruido real: este nodo emite noise_emitted(jugador,
## ruido.radio_movil, "phone_vibration") si el móvil no está silenciado. La interfaz del móvil NO
## debe emitirlo también.

signal mask_changed(masked: bool)
signal muzak_band_changed(band: int)

const GROUP := "audio_director"
const NO_POSITION := Vector2.INF
const BUS_MUSIC := "Music"
const BUS_SFX := "SFX"
const BUS_AMBIENCE := "Ambience"
const BUS_PARENT := "Master"
const MODE_OFF := "off"
const MODE_MUZAK := "muzak"
const MODE_MENU := "menu"
const MODE_EPILOGUE := "epilogue"
const MUZAK_PIECE := "muzak"
const MENU_PIECE := "menu"
const EPILOGUE_PREFIX := "epilogue_"
const EPILOGUE_FALLBACK := "epilogue_ruin"
const EPILOGUE_HYBRID := "hybrid"
## Ejes de estilo (el dominante elige el epílogo). RUINA no es un estilo: con ruin_tier "husk" el
## tema del epílogo suena en cinta gastada (play_epilogue(axis, true)); el eje "ruin" = cinta arruinada.
const AXES: Array[String] = ["blood", "gold", "silk", "sweat"]
const RUIN_TIER_WORN := "husk"
const MUZAK_SUBTITLES: Array[String] = ["SUB_MUZAK_NORMAL", "SUB_MUZAK_SLOW", "SUB_MUZAK_WORN", "SUB_MUZAK_ATONAL"]
const NO_MUZAK_SUBTITLES: Dictionary = {"factory": "SUB_FACTORY_RHYTHM", "exterior": "SUB_NIGHT_STREET"}
## Fuente de noise_emitted (subcadena, minúsculas) → efecto. El orden importa.
const NOISE_SOURCES: Array = [
	["sneak", "step_sneak"], ["sprint", "step_sprint"], ["run", "step_sprint"], ["walk", "step_walk"],
	["step", "step_walk"], ["drawer", "drawer_open"], ["lock", "lock_forcing"],
	["break", "break_object"], ["smash", "break_object"], ["freight", "freight_elevator"],
	["card", "card_beep"], ["reader", "card_beep"],
]
const PLAYER_SOURCE_HINT := "player"
const SILENT_SOURCES: Array[String] = ["phone", "vibrat"]
const PHONE_NOISE_SOURCE := "phone_vibration"
const ELEVATOR_HINT := "elev"
const ELEVATOR_ROOM_SOUND := "elevator_muzak"
const VARIED_PREFIXES: Array[String] = ["step", "npc_step", "drawer", "break", "lock", "chair"]
const SETTING_MUSIC := "music_volume"
const SETTING_SFX := "sfx_volume"
const SETTING_PHONE_SILENCED := "phone_silenced"
const SETTINGS_DEFAULTS := "menus.ajustes_por_defecto."
const PERCENT := 100.0
const MIN_LINEAR := 0.0001
const NO_FLOOR := -1000000
const NEVER := -1.0e9
## Grupo de FloorStreamer (por nombre: el audio no depende de que el mundo compile).
const STREAMER_GROUP := "floor_streamer"

## Directores vivos en orden de llegada; el último es el activo.
static var _stack: Array[AudioDirector] = []

var _rate: int = 0
var _cfg: Dictionary = {}
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _muzak_player: AudioStreamPlayer = null
var _alarm_player: AudioStreamPlayer = null
var _ambience: Ambience = null
var _voices: SfxVoices = SfxVoices.new()
var _deck: MuzakDeck = MuzakDeck.new()
var _mode: String = MODE_OFF
var _arrangement: String = AudioTuning.NO_ARRANGEMENT
var _art_band: String = ""
var _floor: int = NO_FLOOR
var _suspicion: float = 0.0
var _band: int = -1
var _wanted_key: String = ""
var _deck_key: String = ""
var _deck_variants: int = 0
var _gen_capacity: int = -1
var _player_room: String = ""
var _in_elevator: bool = false
var _masked: bool = false
var _elevator_until: float = NEVER
var _arrival_until: float = NEVER
var _alarm_left: float = 0.0
var _time: float = 0.0
var _sub_last: Dictionary = {}
var _sfx_last: Dictionary = {}
var _listener: NpcListener = NpcListener.new()
var _scan_timer: float = 0.0
var _settings_timer: float = 0.0
var _music_volume: float = -1.0
var _sfx_volume: float = -1.0
var _phone_silenced: bool = false
var _warned_ids: Dictionary = {}
var _dormant: bool = true
var _readied: bool = false
var _seats: PackedVector2Array = PackedVector2Array()
var _seat_floor: int = NO_FLOOR
var _view: Rect2 = Rect2()


## El AudioDirector activo (o null).
static func find(tree: SceneTree) -> AudioDirector:
	var active: AudioDirector = active_director()
	if active != null or tree == null:
		return active
	return tree.get_first_node_in_group(GROUP) as AudioDirector


static func active_director() -> AudioDirector:
	while not _stack.is_empty() and not is_instance_valid(_stack.back()):
		_stack.pop_back()
	return null if _stack.is_empty() else _stack.back()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	SynthDSP.warm_up()
	_load_config()
	_rng.seed = int(_cfg["seed"])
	MuzakLibrary.configure(int(_cfg["cache_size"]))
	_deck.setup(_rate, int(_cfg["seed"]), float(_cfg["smooth_s"]), float(_cfg["swap_fade_s"]))
	_listener.setup(_cfg, int(_cfg["seed"]))
	_listener.set_probes(_is_seated, _is_in_view)
	_ensure_buses()
	_build_players()
	SfxBank.prewarm_async(_rate)
	_readied = true
	_claim()
	refresh_settings()


func _enter_tree() -> void:
	if _readied and not _stack.has(self):
		_claim()


func _exit_tree() -> void:
	_silence_all()
	MuzakLibrary.release(get_instance_id())
	var was_active: bool = active_director() == self
	_stack.erase(self)
	_set_bus(false)
	var next: AudioDirector = active_director()
	if was_active and next != null:
		next._set_dormant(false)


func _process(delta: float) -> void:
	_time += delta
	MuzakLibrary.poll()
	SfxBank.poll_prewarm()
	_sync_deck()
	_feed_generator(delta)
	_handle_deck_events()
	_tick_alarm(delta)
	if _world_paused():
		_scan_timer = 0.0
	else:
		_scan_timer += delta
	if _scan_timer >= float(_cfg["npc_interval"]):
		_scan_npcs(_scan_timer)
		_scan_timer = 0.0
	_settings_timer += delta
	if _settings_timer >= float(_cfg["settings_interval"]):
		_settings_timer = 0.0
		refresh_settings()


# ─── API pública ─────────────────────────────────────────────────

## Reproduce un efecto de SfxBank. Con posición (mundo) suena en estéreo según la dirección;
## sin ella, en el oyente. Publica el subtítulo del efecto si lo tiene (§13.10).
func play_sfx(id: String, position: Vector2 = NO_POSITION, volume_db: float = 0.0) -> void:
	_play(id, position, volume_db, SfxBank.subtitle_key(id), SfxBank.importance(id), true)


## Sospecha 0-100 → degradación del hilo musical (§14.9).
func set_suspicion(value: float) -> void:
	_suspicion = clampf(value, 0.0, PERCENT)
	var params: Dictionary = MuzakSynth.degradation(_suspicion)
	if _mode == MODE_MUZAK:
		_deck.set_degradation(params, false)
	var band: int = int(params.get("band", 0))
	if band == _band:
		return
	var previous: int = _band
	_band = band
	muzak_band_changed.emit(band)
	if previous >= 0 and is_muzak_active() and band < MUZAK_SUBTITLES.size():
		var importance: int = SfxBank.IMPORTANCE_DANGER if band >= 2 else SfxBank.IMPORTANCE_INFO
		post_subtitle(MUZAK_SUBTITLES[band], NO_POSITION, importance)


## Planta actual: arreglo del hilo musical por banda, sin hilo en fábrica/exterior, ambiente de banda.
@warning_ignore("shadowed_global_identifier")
func set_floor(floor: int) -> void:
	_floor = floor
	var band: Dictionary = AudioTuning.band_for_floor(floor)
	_art_band = str(band.get("id", ""))
	_arrangement = str(band.get("muzak_arrangement", AudioTuning.NO_ARRANGEMENT))
	if _mode == MODE_OFF or _mode == MODE_MUZAK:
		_mode = MODE_MUZAK
		_deck.set_degradation(MuzakSynth.degradation(_suspicion), false)
		if MuzakSynth.has_arrangement(_arrangement):
			_request_stems(MUZAK_PIECE, _arrangement)
		elif NO_MUZAK_SUBTITLES.has(_art_band):
			post_subtitle(NO_MUZAK_SUBTITLES[_art_band], NO_POSITION, SfxBank.IMPORTANCE_AMBIENT)
	if _ambience != null and not band.is_empty():
		_ambience.set_ambience(str(band.get("ambient_sound", "")), float(band.get("ambient_noise_level", 0.0)))
	_arrival_chime_check()
	_update_music_level()


## Sala del jugador: ambiente de sala, máscara acústica (indicador) y refuerzo del hilo en el ascensor.
func set_player_room(room_id: String) -> void:
	_player_room = room_id
	var info: Dictionary = AudioTuning.room_info(room_id)
	if _ambience != null and not info.is_empty():
		_ambience.set_ambience(str(info.get("ambient_sound", "")), float(info.get("ambient_noise_level", 0.0)))
	_in_elevator = str(info.get("ambient_sound", "")) == ELEVATOR_ROOM_SOUND
	_arrival_room_check()
	_update_music_level()
	var masked: bool = bool(info.get("acoustic_mask", false))
	if masked == _masked:
		return
	_masked = masked
	mask_changed.emit(masked)
	var key: String = "SUB_MASK_ON" if masked else "SUB_MASK_OFF"
	post_subtitle(key, NO_POSITION, SfxBank.IMPORTANCE_INFO if masked else SfxBank.IMPORTANCE_AMBIENT)


## Silencio total del hilo musical durante `seconds` (flagrancia: 1 s, §14.10). Vacía lo ya
## encolado en el generador: el corte es inmediato ("se detiene en seco").
func interrupt_muzak(seconds: float) -> void:
	_deck.interrupt(seconds)
	if _muzak_player != null and _muzak_player.playing:
		var playback: AudioStreamGeneratorPlayback = _muzak_player.get_stream_playback() as AudioStreamGeneratorPlayback
		if playback != null:
			playback.clear_buffer()


## Música del menú principal (no diegética): el tema de la compañía como música de espera.
func play_menu_music() -> void:
	_mode = MODE_MENU
	_deck.set_degradation(MuzakSynth.degradation(0.0), true)
	_request_stems(MENU_PIECE, MuzakSynth.default_arrangement(MENU_PIECE))
	_update_music_level()


## Música de epílogo según el eje dominante (blood, gold, silk, sweat; "hybrid" = el hilo musical
## del edificio, limpio; otro = cinta arruinada). `worn` = en cinta gastada (ruina "husk").
func play_epilogue(axis: String, worn: bool = false) -> void:
	var piece: String = EPILOGUE_PREFIX + axis
	if not MuzakSynth.has_piece(piece):
		piece = EPILOGUE_FALLBACK
	_mode = MODE_EPILOGUE
	var ruined: bool = worn or piece == EPILOGUE_FALLBACK
	_deck.set_degradation(MuzakSynth.degradation(float(_cfg["ruin_suspicion"]) if ruined else 0.0), true)
	_request_stems(piece, MuzakSynth.default_arrangement(piece))
	_update_music_level()


## {axis, worn} del epílogo para una instantánea de Tracking.get_snapshot() (§14.9: varía según el
## eje dominante): híbrido o sin ningún eje → "hybrid"; ruin_tier "husk" → cinta gastada.
static func epilogue_choice(snapshot: Dictionary) -> Dictionary:
	var worn: bool = str(snapshot.get("ruin_tier", "")) == RUIN_TIER_WORN
	var axes: Dictionary = snapshot.get("axes", snapshot) if snapshot.get("axes") is Dictionary else snapshot
	var best: String = ""
	var best_value: float = 0.0
	for axis: String in AXES:
		var v: Variant = axes.get(axis, 0)
		if (v is int or v is float) and float(v) > best_value:
			best_value = float(v)
			best = axis
	if bool(snapshot.get("hybrid", false)) or best.is_empty():
		return {"axis": EPILOGUE_HYBRID, "worn": worn}
	var dominant: String = str(snapshot.get("dominant_axis", ""))
	return {"axis": dominant if AXES.has(dominant) else best, "worn": worn}


func stop_music() -> void:
	_mode = MODE_OFF
	if _muzak_player != null:
		_muzak_player.stop()


func get_mode() -> String:
	return _mode


## Pieza pedida ("muzak", "menu", "epilogue_gold"...; "" si ninguna).
func get_piece() -> String:
	return MuzakLibrary.piece_of(_wanted_key)


func get_arrangement() -> String:
	return _arrangement


func get_muzak_band() -> int:
	return maxi(_band, 0)


## True si suena (o va a sonar) el hilo musical diegético en esta planta.
func is_muzak_active() -> bool:
	return _mode == MODE_MUZAK and MuzakSynth.has_arrangement(_arrangement)


## True cuando la pieza pedida ya está renderizada y cargada en la pletina.
func is_music_ready() -> bool:
	return not _wanted_key.is_empty() and _deck_key == _wanted_key and _deck.has_stems() \
			and not _deck.has_pending()


## False mientras otro director más reciente manda (este queda en silencio).
func is_active() -> bool:
	return not _dormant


## True si escucha a los NPC (activo y con el mundo en marcha: ni árbol ni reloj en pausa).
func is_listening() -> bool:
	return not _dormant and not _world_paused()


func is_masked() -> bool:
	return _masked


func get_deck() -> MuzakDeck:
	return _deck


func get_ambience() -> Ambience:
	return _ambience


func is_phone_silenced() -> bool:
	return _phone_silenced


## El móvil silenciado no vibra (§14.10). Se guarda en el perfil (SaveSystem.save_profile()).
func set_phone_silenced(value: bool) -> void:
	_phone_silenced = value
	var save: Node = AudioTuning.autoload("SaveSystem")
	if save != null and save.has_method("set_setting"):
		save.call("set_setting", SETTING_PHONE_SILENCED, value)
		if save.has_method("save_profile"):
			save.call("save_profile")


## Publica un subtítulo respetando el enfriamiento por clave. Devuelve si se publicó.
func post_subtitle(key: String, position: Vector2, importance: int) -> bool:
	var cooldowns: Dictionary = _cfg["sub_cooldowns"]
	var cooldown: float = float(cooldowns.get(key, _cfg["sub_cooldown"]))
	if _sub_last.has(key) and _time - float(_sub_last[key]) < cooldown:
		return false
	_sub_last[key] = _time
	EventBus.subtitle_posted.emit(key, position if position.is_finite() else NO_POSITION, importance)
	return true


## Relee volúmenes (music_volume, sfx_volume: 0-1, como SettingsMenu) y el silencio del móvil.
## Buses: Music ← music_volume; SFX y Ambience ← sfx_volume (misma fórmula que SettingsMenu).
## Solo toca un bus cuando el valor leído cambia (no pelea con el deslizador de SettingsMenu).
func refresh_settings() -> void:
	var music: float = _read_volume(SETTING_MUSIC)
	var sfx: float = _read_volume(SETTING_SFX)
	var silenced: Variant = _read_setting(SETTING_PHONE_SILENCED)
	if silenced is bool:
		_phone_silenced = silenced
	if not is_equal_approx(music, _music_volume):
		_music_volume = music
		_apply_bus(BUS_MUSIC, music)
	if not is_equal_approx(sfx, _sfx_volume):
		_sfx_volume = sfx
		_apply_bus(BUS_SFX, sfx)
		_apply_bus(BUS_AMBIENCE, sfx)


## Efecto que corresponde a una fuente de noise_emitted ("" = no suena aquí).
static func classify_noise(source: String, radius: float, radii: Dictionary) -> String:
	var s: String = source.to_lower()
	for silent: String in SILENT_SOURCES:
		if s.contains(silent):
			return ""
	for pair: Array in NOISE_SOURCES:
		if s.contains(str(pair[0])):
			return str(pair[1])
	if not (s.is_empty() or s.begins_with(PLAYER_SOURCE_HINT)):
		return ""
	if radius <= float(radii.get("sneak", 0.0)):
		return "step_sneak"
	return "step_walk" if radius <= float(radii.get("walk", 0.0)) else "step_sprint"


# ─── Director activo (uno por proceso) ───────────────────────────

func _claim() -> void:
	var previous: AudioDirector = active_director()
	_stack.erase(self)
	_stack.append(self)
	if previous != null and previous != self:
		previous._set_dormant(true)
	_set_dormant(false)


func _set_dormant(value: bool) -> void:
	_dormant = value
	_set_bus(not value)
	set_process(not value)
	if value:
		remove_from_group(GROUP)
		_silence_all()
		MuzakLibrary.release(get_instance_id())
		return
	add_to_group(GROUP)
	if _ambience != null:
		_ambience.resume()
	if not _wanted_key.is_empty():
		MuzakLibrary.request(get_instance_id(), _wanted_key)
	_sync_initial_state.call_deferred()


func _silence_all() -> void:
	if _muzak_player != null:
		_muzak_player.stop()
	_stop_alarm()
	_voices.stop_all()
	if _ambience != null:
		_ambience.suspend()


func _bus_links() -> Array:
	return [
		[EventBus.suspicion_changed, _on_suspicion_changed], [EventBus.floor_changed, _on_floor_changed],
		[EventBus.room_entered, _on_room_entered], [EventBus.player_caught_redhanded, _on_caught_redhanded],
		[EventBus.noise_emitted, _on_noise_emitted], [EventBus.phone_message_received, _on_phone_message],
		[EventBus.alert_level_changed, _on_alert_level_changed],
		[EventBus.card_reader_logged, _on_card_reader_logged], [EventBus.npc_decided, _on_npc_decided],
		[EventBus.rumor_spread, _on_rumor_spread], [EventBus.game_over, _on_game_over],
		[EventBus.run_started, _on_run_started],
	]


func _set_bus(on: bool) -> void:
	for link: Array in _bus_links():
		var sig: Signal = link[0]
		var callback: Callable = link[1]
		if on and not sig.is_connected(callback):
			sig.connect(callback)
		elif not on and sig.is_connected(callback):
			sig.disconnect(callback)


# ─── Configuración y nodos ───────────────────────────────────────

func _load_config() -> void:
	_rate = AudioTuning.integer("audio.frecuencia_muestreo")
	var px: float = AudioTuning.px_per_metre()
	_cfg = {
		"seed": AudioTuning.integer("audio.muzak.semilla"),
		"muzak_db": AudioTuning.num("audio.muzak.nivel_db"),
		"elevator_db": AudioTuning.num("audio.muzak.refuerzo_ascensor_db"),
		"buffer_s": AudioTuning.num("audio.muzak.buffer_s"),
		"lead_s": AudioTuning.num("audio.muzak.adelanto_s"),
		"max_frames": AudioTuning.integer("audio.muzak.max_frames_por_tick"),
		"smooth_s": AudioTuning.num("audio.muzak.suavizado_parametros_s"),
		"swap_fade_s": AudioTuning.num("audio.muzak.fundido_cambio_s"),
		"cache_size": AudioTuning.integer("audio.muzak.cache_piezas"),
		"ruin_suspicion": AudioTuning.num("audio.muzak.epilogo_ruina_sospecha"),
		"flagrant_cut_s": AudioTuning.num("audio.corte_flagrancia_s"),
		"default_volume": AudioTuning.num("audio.volumen_defecto"),
		"settings_interval": AudioTuning.num("audio.ajustes_intervalo_s"),
		"elevator_window_s": AudioTuning.num("audio.ascensor_ventana_s"),
		"arrival_window_s": AudioTuning.num("audio.llegada_ventana_s"),
		"mask_factor": AudioTuning.num("ruido.reduccion_por_mascara"),
		"phone_radius": AudioTuning.num("ruido.radio_movil"),
		"alarm_level": AudioTuning.integer("audio.alarma.nivel_minimo"),
		"alarm_s": AudioTuning.num("audio.alarma.duracion_s"),
		"sub_cooldown": AudioTuning.num("audio.subtitulos.enfriamiento_s"),
		"sub_cooldowns": AudioTuning.dict("audio.subtitulos.enfriamiento_por_clave"),
	}
	_load_sfx_config(px)
	_load_npc_config(px)


func _load_sfx_config(px: float) -> void:
	_cfg.merge({
		"pos_voices": AudioTuning.integer("audio.sfx.voces_posicionales"),
		"glob_voices": AudioTuning.integer("audio.sfx.voces_globales"),
		"max_distance_px": AudioTuning.num("audio.sfx.distancia_max_m") * px,
		"attenuation": AudioTuning.num("audio.sfx.atenuacion"),
		"pitch_variation": AudioTuning.num("audio.sfx.variacion_tono"),
		"min_interval": AudioTuning.num("audio.sfx.intervalo_min_s"),
		"intervals": AudioTuning.dict("audio.sfx.intervalo_por_id"),
		"volume_min": AudioTuning.num("audio.sfx.volumen_min"),
		"volume_max": AudioTuning.num("audio.sfx.volumen_max"),
		"radii": {
			"sneak": AudioTuning.num("ruido.radio_sigiloso"),
			"walk": AudioTuning.num("ruido.radio_normal"),
		},
	}, true)


func _load_npc_config(px: float) -> void:
	_cfg.merge({
		"npc_interval": AudioTuning.num("audio.npcs.intervalo_s"),
		"hear_px": AudioTuning.num("audio.npcs.distancia_escucha_m") * px,
		"npc_min_speed": AudioTuning.num("audio.npcs.velocidad_min_px_s"),
		"npc_step_s": AudioTuning.num("audio.npcs.paso_intervalo_s"),
		"seated_s": AudioTuning.num("audio.npcs.sentado_s"),
		"seat_px": AudioTuning.num("audio.npcs.asiento_radio_m") * px,
		"approach_px": AudioTuning.num("audio.npcs.acercamiento_min_px"),
		"radio_interval": AudioTuning.range_of("audio.npcs.radio_intervalo_s"),
		"max_steps": AudioTuning.integer("audio.npcs.max_pasos_por_barrido"),
		"chat_actions": AudioTuning.list("audio.npcs.charla_acciones"),
		"radio_occupations": AudioTuning.list("audio.npcs.radio_ocupaciones"),
	}, true)


func _ensure_buses() -> void:
	for bus_name: String in [BUS_MUSIC, BUS_SFX, BUS_AMBIENCE]:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx: int = AudioServer.bus_count - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, BUS_PARENT)


func _build_players() -> void:
	var generator: AudioStreamGenerator = AudioStreamGenerator.new()
	generator.mix_rate_mode = AudioStreamGenerator.MIX_RATE_CUSTOM
	generator.mix_rate = float(_rate)
	generator.buffer_length = float(_cfg["buffer_s"])
	_muzak_player = _make_player("MuzakPlayer", BUS_MUSIC)
	_muzak_player.stream = generator
	_alarm_player = _make_player("AlarmPlayer", BUS_SFX)
	_voices.build(self, BUS_SFX, int(_cfg["pos_voices"]), int(_cfg["glob_voices"]),
			float(_cfg["max_distance_px"]), float(_cfg["attenuation"]))
	_ambience = Ambience.new()
	_ambience.name = "Ambience"
	add_child(_ambience)
	_ambience.setup(_rate, BUS_AMBIENCE)


func _make_player(node_name: String, bus: String) -> AudioStreamPlayer:
	var p: AudioStreamPlayer = AudioStreamPlayer.new()
	p.name = node_name
	p.bus = bus
	add_child(p)
	return p


func _sync_initial_state() -> void:
	if _dormant:
		return
	var state: Node = AudioTuning.autoload("PlayerState")
	if state != null and state.has_method("get_suspicion"):
		set_suspicion(float(state.call("get_suspicion")))
	else:
		set_suspicion(_suspicion)
	if _mode == MODE_OFF and _floor == NO_FLOOR and state != null and state.has_method("get_floor"):
		set_floor(int(state.call("get_floor")))


## Reloj o árbol en pausa: el mundo está congelado (no se escucha a los NPC ni corre su "quieto").
func _world_paused() -> bool:
	var tree: SceneTree = get_tree()
	if tree != null and tree.paused:
		return true
	var clock: Node = AudioTuning.autoload("GameClock")
	if clock == null or not clock.has_method("is_paused") or not clock.has_method("get_day"):
		return false
	return int(clock.call("get_day")) > 0 and bool(clock.call("is_paused"))


# ─── Reacciones a EventBus ───────────────────────────────────────

func _on_suspicion_changed(_old_value: float, new_value: float) -> void:
	set_suspicion(new_value)


func _on_floor_changed(_old_floor: int, new_floor: int) -> void:
	set_floor(new_floor)


func _on_rumor_spread(from_npc: String, _to_npc: String, _belief_id: String) -> void:
	_npc_chatter(from_npc)


func _on_room_entered(room_id: String, by_player: bool) -> void:
	if by_player:
		set_player_room(room_id)


## Flagrancia: golpe seco + el hilo musical se interrumpe (§14.10).
func _on_caught_redhanded(_npc_id: String, _crime_type: String, _witnesses: int) -> void:
	play_sfx("caught_thud")
	interrupt_muzak(float(_cfg["flagrant_cut_s"]))


## Ruidos del jugador (player.gd: una pisada = un evento, radio nominal): el volumen sigue al
## radio y, dentro de una máscara acústica, se reduce como el radio efectivo (§14.10).
func _on_noise_emitted(position: Vector2, radius: float, source: String) -> void:
	var id: String = classify_noise(source, radius, _cfg["radii"])
	if id.is_empty():
		return
	var ref_path: String = SfxBank.reference_radius_path(id)
	var ref: float = AudioTuning.num(ref_path) if not ref_path.is_empty() else 0.0
	var effective: float = radius * (float(_cfg["mask_factor"]) if _masked else 1.0)
	var gain: float = 1.0
	if ref > 0.0:
		gain = clampf(effective / ref, float(_cfg["volume_min"]), float(_cfg["volume_max"]))
	play_sfx(id, position, linear_to_db(gain))


## El móvil vibra (§14.10) y se oye: ruido real en la posición del jugador para los NPC.
func _on_phone_message(_from_id: String, _text_key: String, _is_chat: bool) -> void:
	if _phone_silenced:
		return
	play_sfx("phone_vibrate")
	var player: Node = get_tree().get_first_node_in_group("player")
	if player is Node2D:
		EventBus.noise_emitted.emit((player as Node2D).global_position, float(_cfg["phone_radius"]),
				PHONE_NOISE_SOURCE)


## Sube la alerta: la radio del vigilante más cercano; sin vigilante en la planta, la megafonía.
func _on_alert_level_changed(old_level: int, new_level: int) -> void:
	var threshold: int = int(_cfg["alarm_level"])
	if new_level > old_level:
		var guard: Vector2 = _listener.nearest_guard(_listener_position())
		play_sfx("guard_radio" if guard.is_finite() else "pa_chime", guard)
	if new_level >= threshold and old_level < threshold:
		_start_alarm()
	elif new_level < threshold and old_level >= threshold:
		_stop_alarm()


func _on_card_reader_logged(reader_id: String, _card_owner: String, _day: int, _hour: int) -> void:
	play_sfx("card_beep")
	if reader_id.to_lower().contains(ELEVATOR_HINT):
		_elevator_until = _time + float(_cfg["elevator_window_s"])


func _on_npc_decided(npc_id: String, action: String, _context: Dictionary) -> void:
	var a: String = action.to_lower()
	for hint: Variant in _cfg["chat_actions"]:
		if a.contains(str(hint)):
			_npc_chatter(npc_id)
			return


func _on_game_over(_cause: String, _ending_id: String, tracking_snapshot: Dictionary) -> void:
	_stop_alarm()
	var snapshot: Dictionary = tracking_snapshot
	if snapshot.is_empty():
		var tracking: Node = AudioTuning.autoload("Tracking")
		if tracking != null and tracking.has_method("get_snapshot"):
			snapshot = tracking.call("get_snapshot")
	var choice: Dictionary = epilogue_choice(snapshot)
	play_epilogue(str(choice["axis"]), bool(choice["worn"]))


func _on_run_started(run_seed: int) -> void:
	_rng.seed = run_seed + int(_cfg["seed"])
	_stop_alarm()
	_elevator_until = NEVER
	_arrival_until = NEVER
	_listener.reset(run_seed + int(_cfg["seed"]))
	_sub_last.clear()
	_band = -1
	if _mode != MODE_MUZAK:
		_mode = MODE_OFF
	set_suspicion(0.0)


# ─── Ascensor: la campanilla suena al llegar en ascensor, no por las escaleras ─

## Al cambiar de planta: en la cabina (o tras pasar la tarjeta del ascensor hace poco) suena ya;
## si no, la primera sala del jugador en la planta nueva decide (orden de señales indistinto).
func _arrival_chime_check() -> void:
	if _in_elevator or _time <= _elevator_until:
		_arrival_until = NEVER
		play_sfx("elevator_chime")
	else:
		_arrival_until = _time + float(_cfg["arrival_window_s"])
	_elevator_until = NEVER


func _arrival_room_check() -> void:
	if _in_elevator and _time <= _arrival_until:
		play_sfx("elevator_chime")
	_arrival_until = NEVER
	if not _in_elevator:
		_elevator_until = NEVER


# ─── Hilo musical: pistas compartidas (MuzakLibrary) y alimentación del generador ─

func _request_stems(piece: String, arrangement: String) -> void:
	_wanted_key = MuzakLibrary.key_for(piece, arrangement)
	MuzakLibrary.request(get_instance_id(), _wanted_key)
	_sync_deck()


## Carga en la pletina la mejor versión disponible de la pieza pedida (fase 1 → fase 2).
func _sync_deck() -> void:
	if _wanted_key.is_empty():
		return
	var stems: Dictionary = MuzakLibrary.get_stems(_wanted_key)
	if stems.is_empty():
		return
	var variants: int = (stems.get("mel", []) as Array).size()
	if _deck_key != _wanted_key:
		var same_piece: bool = MuzakLibrary.piece_of(_deck_key) == MuzakLibrary.piece_of(_wanted_key)
		_deck.load_stems(stems, same_piece)
		_deck_key = _wanted_key
		_deck_variants = variants
	elif variants > _deck_variants:
		_deck.upgrade_stems(stems)
		_deck_variants = variants


func _music_audible() -> bool:
	if _mode == MODE_OFF or not _deck.has_stems():
		return false
	return _mode != MODE_MUZAK or MuzakSynth.has_arrangement(_arrangement)


## Empuja al generador solo lo necesario para tener `adelanto_s` encolado (latencia de los cambios
## y del corte de flagrancia) y nunca más de lo que admite (sin esperas activas).
func _feed_generator(delta: float) -> void:
	if not _music_audible():
		if _muzak_player.playing:
			_muzak_player.stop()
		if _mode == MODE_MUZAK:
			_deck.skip(delta)
		return
	if not _muzak_player.playing:
		_muzak_player.play()
		_gen_capacity = -1
	var playback: AudioStreamGeneratorPlayback = _muzak_player.get_stream_playback() as AudioStreamGeneratorPlayback
	if playback == null:
		return
	var available: int = playback.get_frames_available()
	if _gen_capacity < 0:
		_gen_capacity = available
	var queued: int = maxi(0, _gen_capacity - available)
	var wanted: int = int(float(_cfg["lead_s"]) * float(_rate)) - queued
	var frames: int = mini(mini(available, wanted), int(_cfg["max_frames"]))
	if frames > 0:
		playback.push_buffer(_deck.process(frames))


func _update_music_level() -> void:
	if _muzak_player == null:
		return
	var db: float = 0.0
	if _mode == MODE_MUZAK:
		db = float(_cfg["muzak_db"]) + (float(_cfg["elevator_db"]) if _in_elevator else 0.0)
	_muzak_player.volume_db = db


## Cortes y silencios de la cinta también tienen subtítulo (el edificio avisa, §14.9).
func _handle_deck_events() -> void:
	for event: String in _deck.consume_events():
		if not is_muzak_active():
			continue
		if event == MuzakDeck.EVENT_CUT:
			post_subtitle("SUB_MUZAK_CUT", NO_POSITION, SfxBank.IMPORTANCE_INFO)
		elif event == MuzakDeck.EVENT_DROPOUT:
			post_subtitle("SUB_MUZAK_DROPOUT", NO_POSITION, SfxBank.IMPORTANCE_AMBIENT)


# ─── Efectos ─────────────────────────────────────────────────────

## `throttle` aplica el intervalo mínimo por id (los pasos de NPC llevan su propia cadencia).
func _play(id: String, position: Vector2, volume_db: float, subtitle: String, importance: int,
		throttle: bool) -> void:
	if not SfxBank.has_sfx(id):
		if not _warned_ids.has(id):
			_warned_ids[id] = true
			push_warning("AudioDirector: unknown sfx id '%s'" % id)
		return
	var interval: float = float((_cfg["intervals"] as Dictionary).get(id, _cfg["min_interval"]))
	if throttle and _sfx_last.has(id) and _time - float(_sfx_last[id]) < interval:
		return
	_sfx_last[id] = _time
	var pitch: float = 1.0
	for prefix: String in VARIED_PREFIXES:
		if id.begins_with(prefix):
			var spread: float = float(_cfg["pitch_variation"])
			pitch = 1.0 + _rng.randf_range(-spread, spread)
	_voices.play(SfxBank.get_stream(id, _rate), position, volume_db, pitch, SfxBank.importance(id), _time)
	if not subtitle.is_empty():
		post_subtitle(subtitle, position, importance)


func _start_alarm() -> void:
	var id: String = SfxBank.alarm_for_band(_art_band)
	_alarm_player.stream = SfxBank.get_stream(id, _rate)
	_alarm_player.play()
	_alarm_left = float(_cfg["alarm_s"])
	post_subtitle(SfxBank.subtitle_key(id), NO_POSITION, SfxBank.importance(id))


func _stop_alarm() -> void:
	_alarm_left = 0.0
	if _alarm_player != null:
		_alarm_player.stop()


func _tick_alarm(delta: float) -> void:
	if _alarm_left <= 0.0:
		return
	_alarm_left -= delta
	if _alarm_left <= 0.0:
		_alarm_player.stop()


# ─── Personajes: pasos con paneo, silla, radio, charla (§14.10 categoría 2) ─

func _scan_npcs(dt: float) -> void:
	var nodes: Array[Node] = get_tree().get_nodes_in_group("npcs")
	if not nodes.is_empty():
		_refresh_seats()
		_view = _camera_view()
	for event: Dictionary in _listener.scan(nodes, _listener_position(), dt):
		var id: String = str(event["sfx"])
		var subtitle: String = str(event["subtitle"])
		if subtitle.is_empty():
			subtitle = SfxBank.subtitle_key(id)
		elif subtitle == NpcListener.NO_SUBTITLE:
			subtitle = ""
		_play(id, event["position"], 0.0, subtitle, int(event["importance"]), false)


## Sonda de NpcListener: ¿estaba sentado? Primero el propio NPC (npc.gd: is_seated()); si no lo
## implementa, si está sobre una silla/puesto de la planta (FloorStreamer: asientos).
func _is_seated(node: Node2D) -> bool:
	if node.has_method("is_seated"):
		return bool(node.call("is_seated"))
	var radius: float = float(_cfg["seat_px"])
	for seat: Vector2 in _seats:
		if seat.distance_to(node.global_position) <= radius:
			return true
	return false


## Sonda de NpcListener: ¿se ve esa posición? Dentro de la cámara y en la sala del jugador.
func _is_in_view(pos: Vector2) -> bool:
	if not _view.has_area() or not _view.has_point(pos):
		return false
	var streamer: Node2D = _streamer()
	if streamer == null or _player_room.is_empty() or not streamer.has_method("get_room_at"):
		return true
	return str(streamer.call("get_room_at", streamer.to_local(pos))) == _player_room


## Asientos de la planta cargada (FloorStreamer.get_seats_in_room de cada sala), en coordenadas globales.
func _refresh_seats() -> void:
	var streamer: Node2D = _streamer()
	if streamer == null or not streamer.has_method("get_seats_in_room"):
		_seats = PackedVector2Array()
		_seat_floor = NO_FLOOR
		return
	var current: int = int(streamer.call("get_current_floor"))
	if current == _seat_floor and not _seats.is_empty():
		return
	_seat_floor = current
	_seats = PackedVector2Array()
	var plan: Dictionary = streamer.call("get_plan")
	for room_id: Variant in (plan.get("rooms", {}) as Dictionary).keys():
		for seat: Variant in streamer.call("get_seats_in_room", str(room_id)):
			_seats.append(streamer.to_global((seat as Dictionary)["pos"]))


func _streamer() -> Node2D:
	return get_tree().get_first_node_in_group(STREAMER_GROUP) as Node2D


## Rectángulo del mundo que se ve en pantalla (vacío si no hay vista).
func _camera_view() -> Rect2:
	var vp: Viewport = get_viewport()
	if vp == null:
		return Rect2()
	return vp.get_canvas_transform().affine_inverse() * vp.get_visible_rect()


## Charla audible: a través del tabique si el NPC no está en la sala del jugador.
func _npc_chatter(npc_id: String) -> void:
	var node: Node2D = _npc_node(npc_id)
	if node == null or node.global_position.distance_to(_listener_position()) > float(_cfg["hear_px"]):
		return
	var room: String = ""
	var director: Node = AudioTuning.autoload("NPCDirector")
	if director != null and director.has_method("get_npc"):
		var npc: Object = director.call("get_npc", npc_id)
		if npc is NPCRuntime:
			room = (npc as NPCRuntime).current_room
	var key: String = "SUB_CONVERSATION" if not room.is_empty() and room == _player_room else "SUB_CHATTER"
	_play("chatter", node.global_position, 0.0, key, SfxBank.importance("chatter"), true)


func _npc_node(npc_id: String) -> Node2D:
	var tracked: Node2D = _listener.node_for(npc_id)
	if tracked != null:
		return tracked
	for n: Node in get_tree().get_nodes_in_group("npcs"):
		if n is Node2D and NpcListener.npc_key(n) == npc_id:
			return n as Node2D
	return null


## Posición del oyente: el jugador, si no la cámara, si no el origen.
func _listener_position() -> Vector2:
	var tree: SceneTree = get_tree()
	if tree == null:
		return Vector2.ZERO
	var player: Node = tree.get_first_node_in_group("player")
	if player is Node2D:
		return (player as Node2D).global_position
	var camera: Camera2D = get_viewport().get_camera_2d() if get_viewport() != null else null
	return camera.get_screen_center_position() if camera != null else Vector2.ZERO


# ─── Ajustes ─────────────────────────────────────────────────────

func _read_setting(key: String) -> Variant:
	var save: Node = AudioTuning.autoload("SaveSystem")
	if save == null or not save.has_method("get_setting"):
		return null
	return save.call("get_setting", key)


## Perfil (SaveSystem) → valor por defecto de SettingsMenu (menus.ajustes_por_defecto) → audio.volumen_defecto.
func _read_volume(key: String) -> float:
	var v: Variant = _read_setting(key)
	if not (v is float or v is int):
		v = AudioTuning.value(SETTINGS_DEFAULTS + key)
	if not (v is float or v is int):
		return float(_cfg["default_volume"])
	var f: float = float(v)
	return clampf(f / PERCENT if f > 1.0 else f, 0.0, 1.0)


func _apply_bus(bus_name: String, volume: float) -> void:
	var idx: int = AudioServer.get_bus_index(bus_name)
	if idx < 0:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(maxf(volume, MIN_LINEAR)))
	AudioServer.set_bus_mute(idx, volume <= 0.0)
