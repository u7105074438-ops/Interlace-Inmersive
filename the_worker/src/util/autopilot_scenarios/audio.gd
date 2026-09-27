# audio.gd (escenario) — QA del audio: WAV de revisión del hilo musical, hoja de telemetría y subtítulos en juego.
# PROPIETARIO DE: los nodos temporales del escenario (hoja de QA, director de audio, planta y figuras de muestra).
# ESCUCHA: EventBus.subtitle_posted (para el registro de subtítulos de la hoja).
extends Node

## tools/screenshot.sh /tmp/shots_audio audio [--wav-dir=/tmp]
## Escribe en --wav-dir (por defecto /tmp): muzak_<sospecha>.wav (0, 40, 65, 90; arreglo estándar),
## muzak_band_<arreglo>.wav, muzak_<pieza>.wav (menú y epílogos) (20 s, PCM 16 bits mono) y
## muzak_stats.json. Capturas: audio_qa, audio_qa_es, audio_qa_phone, audio_ingame, audio_ingame_phone.

const SUSPICIONS: Array[float] = [0.0, 40.0, 65.0, 90.0]
const WAV_SECONDS := 20.0
const DEFAULT_WAV_DIR := "/tmp"
const REFERENCE_ARRANGEMENT := "standard"
const EXTRA_PIECES: Array[String] = ["menu", "epilogue_sweat", "epilogue_gold", "epilogue_silk", "epilogue_blood",
		"epilogue_hybrid"]
const BUCKETS := 480
const SILENT_GAIN := 0.1
const PHONE_WINDOW := Vector2i(1170, 540)
const DESKTOP_WINDOW := Vector2i(1600, 900)
const SETTLE_FRAMES := 6
const INGAME_FLOOR := 3
const INGAME_ROOM := "wing_3b"
const INGAME_OCCUPATION := "order_filer"
const INGAME_TIME := Vector3i(3, 10, 42)
const INGAME_MONEY := 1240
const INGAME_SUSPICION := 62.0
const WALK_S := 2.6
const WALK_PX_PER_S := 115.0
const HIDDEN_PX_PER_S := 150.0
const RADIO_OFFSET := Vector2(260, -170)
const NPC_START_OFFSET := Vector2(-390, 30)
const HIDDEN_START_DX := 380.0
const PLAYER_SEAT_OFFSET := Vector2(0, 40)
const SHEET_LAYER := 20

var _args: Dictionary = {}
var _rows: Array[Dictionary] = []
var _bands: Array[Dictionary] = []
var _subs: Array[Dictionary] = []
var _sheet: AudioQASheet = null
var _layer: CanvasLayer = null


func run(pilot: Autopilot) -> void:
	_args = pilot.get_args()
	if Database.has_method("load_all"):
		Database.load_all()
	EventBus.subtitle_posted.connect(_on_subtitle)
	_render_audio(str(_args.get("wav-dir", DEFAULT_WAV_DIR)))
	await _sheet_shots(pilot)
	await _ingame_shot(pilot)
	EventBus.subtitle_posted.disconnect(_on_subtitle)


func _on_subtitle(key: String, position: Vector2, importance: int) -> void:
	_subs.append({"key": key, "position": position, "importance": importance})


# ─── Render de revisión (WAV + datos de la hoja) ─────────────────

func _render_audio(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir)
	var stems: Dictionary = MuzakSynth.render_piece("muzak", REFERENCE_ARRANGEMENT, MuzakSynth.render_config("muzak"))
	var stats: Dictionary = {}
	for s: float in SUSPICIONS:
		var result: Dictionary = MuzakSynth.render_offline(stems, s, WAV_SECONDS, true)
		var path: String = dir.path_join("muzak_%d.wav" % int(s))
		SynthDSP.write_wav(path, result["samples"], int(result["rate"]))
		var row: Dictionary = _row_data(result, s)
		_rows.append(row)
		stats["muzak_%d" % int(s)] = row["stats"]
		print("[muzak-qa] wrote %s %s" % [path, str(row["stats"])])
	_render_bands(dir, stats)
	_render_pieces(dir)
	var f: FileAccess = FileAccess.open(dir.path_join("muzak_stats.json"), FileAccess.WRITE)
	if f != null:
		f.store_string(JSON.stringify(stats, "  "))
		f.close()


func _render_bands(dir: String, stats: Dictionary) -> void:
	for band: Dictionary in AudioTuning.all_bands():
		var arr: String = str(band.get("muzak_arrangement", AudioTuning.NO_ARRANGEMENT))
		var entry: Dictionary = {"band": band, "arrangement": arr, "brightness": 0.0}
		if MuzakSynth.has_arrangement(arr):
			var stems: Dictionary = MuzakSynth.render_piece("muzak", arr, MuzakSynth.render_config("muzak"), 1)
			var samples: PackedFloat32Array = MuzakSynth.render_offline(stems, 0.0, WAV_SECONDS, false)["samples"]
			SynthDSP.write_wav(dir.path_join("muzak_band_%s.wav" % arr), samples, int(stems["rate"]))
			entry["brightness"] = _brightness(samples)
			stats["band_" + arr] = {"brightness": entry["brightness"]}
		_bands.append(entry)


func _render_pieces(dir: String) -> void:
	for piece: String in EXTRA_PIECES:
		var stems: Dictionary = MuzakSynth.render_piece(piece, MuzakSynth.default_arrangement(piece),
				MuzakSynth.render_config(piece))
		var samples: PackedFloat32Array = MuzakSynth.render_offline(stems, 0.0, WAV_SECONDS, false)["samples"]
		SynthDSP.write_wav(dir.path_join("muzak_%s.wav" % piece), samples, int(stems["rate"]))


## Brillo relativo: energía de la derivada frente a la de la señal (más agudos → mayor).
func _brightness(samples: PackedFloat32Array) -> float:
	var e: float = 0.0
	var d: float = 0.0
	for i: int in range(1, samples.size()):
		e += samples[i] * samples[i]
		var diff: float = samples[i] - samples[i - 1]
		d += diff * diff
	return sqrt(d / maxf(e, SynthDSP.DENORMAL_GUARD))


func _row_data(result: Dictionary, suspicion: float) -> Dictionary:
	var samples: PackedFloat32Array = result["samples"]
	var tele: Dictionary = result["telemetry"]
	var variants: PackedByteArray = tele["variant"]
	var chunk: int = maxi(1, floori(float(samples.size()) / float(BUCKETS)))
	var env: PackedFloat32Array = PackedFloat32Array()
	var peak: PackedFloat32Array = PackedFloat32Array()
	for b: int in BUCKETS:
		env.append(SynthDSP.rms(samples, b * chunk, (b + 1) * chunk))
		peak.append(SynthDSP.peak(samples.slice(b * chunk, (b + 1) * chunk)))
	var pitch_cents: PackedFloat32Array = PackedFloat32Array()
	for p: float in (tele["pitch"] as PackedFloat32Array):
		pitch_cents.append(SynthDSP.CENTS_PER_OCTAVE * log(maxf(p, 0.01)) / log(2.0))
	return {
		"suspicion": suspicion, "band": int((result["degradation"] as Dictionary)["band"]),
		"envelope": env, "peak": peak, "rate": _bucketize(tele["rate"], false),
		"pitch": _bucketize(tele["pitch"], false), "gain": _bucketize(tele["gain"], true),
		"variant": _bucketize_bytes(variants), "stats": _row_stats(tele, pitch_cents),
	}


func _row_stats(tele: Dictionary, pitch_cents: PackedFloat32Array) -> Dictionary:
	var gains: PackedFloat32Array = tele["gain"]
	var variants: PackedByteArray = tele["variant"]
	var n: float = maxf(1.0, float(gains.size()))
	var silent: int = 0
	var sour: int = 0
	var atonal: int = 0
	for i: int in gains.size():
		silent += 1 if gains[i] < SILENT_GAIN else 0
		sour += 1 if variants[i] == MuzakSynth.VARIANT_SOUR else 0
		atonal += 1 if variants[i] == MuzakSynth.VARIANT_ATONAL else 0
	var tempo: Vector2 = _mean_std(tele["rate"])
	var cents: Vector2 = _mean_std(pitch_cents)
	return {"bpm": AudioTuning.num("audio.piezas_bpm.muzak") * tempo.x, "pitch_mean_cents": cents.x,
			"pitch_wobble_cents": cents.y, "silence": float(silent) / n, "sour": float(sour) / n,
			"atonal": float(atonal) / n}


func _mean_std(values: PackedFloat32Array) -> Vector2:
	var mean: float = 0.0
	for v: float in values:
		mean += v
	mean /= maxf(1.0, float(values.size()))
	var sq: float = 0.0
	for v: float in values:
		sq += (v - mean) * (v - mean)
	return Vector2(mean, sqrt(sq / maxf(1.0, float(values.size()))))


func _bucketize(values: PackedFloat32Array, take_min: bool) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	var per: int = maxi(1, floori(float(values.size()) / float(BUCKETS)))
	for b: int in BUCKETS:
		var acc: float = 1.0e9 if take_min else 0.0
		for i: int in range(b * per, mini((b + 1) * per, values.size())):
			acc = minf(acc, values[i]) if take_min else acc + values[i]
		out.append(acc if take_min else acc / float(per))
	return out


func _bucketize_bytes(values: PackedByteArray) -> PackedByteArray:
	var out: PackedByteArray = PackedByteArray()
	var per: int = maxi(1, floori(float(values.size()) / float(BUCKETS)))
	for b: int in BUCKETS:
		var worst: int = 0
		for i: int in range(b * per, mini((b + 1) * per, values.size())):
			worst = maxi(worst, values[i])
		out.append(worst)
	return out


# ─── Hoja de QA ──────────────────────────────────────────────────

func _sheet_shots(pilot: Autopilot) -> void:
	_layer = CanvasLayer.new()
	_layer.layer = SHEET_LAYER
	add_child(_layer)
	_sheet = AudioQASheet.new()
	_sheet.setup(_rows, _bands, _subs)
	_layer.add_child(_sheet)
	await _fire_demo_events(pilot)
	_sheet.queue_redraw()
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("audio_qa")
	TranslationServer.set_locale("es")
	_sheet.queue_redraw()
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("audio_qa_es")
	TranslationServer.set_locale("en")
	get_window().size = PHONE_WINDOW
	_sheet.compact = true
	_sheet.queue_redraw()
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("audio_qa_phone")
	get_window().size = DESKTOP_WINDOW
	_layer.queue_free()
	await pilot.frames(2)


## Eventos reales por el bus con un AudioDirector real: la hoja registra los subtítulos.
func _fire_demo_events(pilot: Autopilot) -> void:
	var listener: Node2D = Node2D.new()
	listener.add_to_group("player")
	add_child(listener)
	var director: AudioDirector = AudioDirector.new()
	add_child(director)
	await pilot.frames(2)
	director.play_sfx("guard_radio", Vector2(420, -260))
	director.play_sfx("chair_creak", Vector2(-300, -120))
	EventBus.floor_changed.emit(0, INGAME_FLOOR)
	EventBus.noise_emitted.emit(Vector2(0, 30), AudioTuning.num("ruido.radio_esprint"), "player")
	EventBus.room_entered.emit("call_center", true)
	EventBus.noise_emitted.emit(Vector2(160, 20), AudioTuning.num("ruido.radio_cajon"), "drawer")
	EventBus.card_reader_logged.emit("reader_elevator_p3", "player", 1, 9)
	EventBus.suspicion_changed.emit(0.0, 62.0)
	EventBus.phone_message_received.emit("npc_amelia_cole", "MSG_TEST", false)
	EventBus.player_caught_redhanded.emit("npc_amelia_cole", "drawer_forced", 1)
	await pilot.frames(2)
	director.queue_free()
	listener.queue_free()
	await pilot.frames(2)


# ─── Captura en juego: la planta 3 con el feed de subtítulos real ─

## Partida de muestra: día 3, 10:42, archivador de pedidos (rango 2, acreditación 1), reloj en marcha
## (la seguridad vuelve a cero tras los eventos de la hoja).
func _prepare_run() -> void:
	GameClock.reset_for_new_run()
	GameClock.set_time(INGAME_TIME.x, INGAME_TIME.y, INGAME_TIME.z)
	PlayerState.reset_for_new_run()
	Security.reset_for_new_run()
	PlayerState.set_occupation(INGAME_OCCUPATION, "preview")
	PlayerState.add_money(INGAME_MONEY, "preview")
	GameClock.resume()


func _ingame_shot(pilot: Autopilot) -> void:
	_prepare_run()
	EventBus.suspicion_changed.emit(0.0, INGAME_SUSPICION)
	var streamer: FloorStreamer = FloorStreamer.new()
	add_child(streamer)
	streamer.load_floor(INGAME_FLOOR)
	var layout: Dictionary = _ingame_layout(streamer)
	var cam: Camera2D = Camera2D.new()
	add_child(cam)
	cam.make_current()
	cam.position = layout["camera"]
	var player: AudioFigure = _figure(streamer, layout["player"], 11, "player", "")
	var ui: UIRoot = UIRoot.new()
	add_child(ui)
	var director: AudioDirector = AudioDirector.new()
	add_child(director)
	await pilot.frames(SETTLE_FRAMES)
	EventBus.floor_changed.emit(0, INGAME_FLOOR)
	EventBus.suspicion_changed.emit(INGAME_SUSPICION, INGAME_SUSPICION)
	await _walk_npcs(pilot, streamer, player, layout["hidden"])
	director.play_sfx("guard_radio", player.global_position + RADIO_OFFSET)
	EventBus.phone_message_received.emit("npc_amelia_cole", "MSG_TEST", false)
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("audio_ingame")
	get_window().size = PHONE_WINDOW
	await pilot.frames(SETTLE_FRAMES)
	await pilot.shot("audio_ingame_phone")
	get_window().size = DESKTOP_WINDOW
	GameClock.pause()
	director.queue_free()
	ui.queue_free()
	streamer.queue_free()
	await pilot.frames(SETTLE_FRAMES)


## El jugador en el puesto más cercano al pasillo (para oír a quien viene por él, tras la pared);
## la cámara, un poco hacia dentro de la sala.
func _ingame_layout(streamer: FloorStreamer) -> Dictionary:
	var rect: Rect2 = streamer.get_room_rect_px(INGAME_ROOM)
	var cell: float = RoomBuilder.cell_px()
	var corridor_y: float = rect.get_center().y
	for y: float in [rect.position.y - cell * 1.5, rect.end.y + cell * 1.5]:
		var room: String = streamer.get_room_at(Vector2(rect.get_center().x, y))
		if not room.is_empty() and room != INGAME_ROOM:
			corridor_y = y
			break
	var seat_pos: Vector2 = streamer.get_spawn_point(INGAME_ROOM)
	var best: float = INF
	for seat: Dictionary in streamer.get_seats_in_room(INGAME_ROOM):
		var p: Vector2 = seat["pos"]
		if absf(p.y - corridor_y) < best:
			best = absf(p.y - corridor_y)
			seat_pos = p
	var player: Vector2 = seat_pos + PLAYER_SEAT_OFFSET
	return {"player": player, "hidden": Vector2(player.x + HIDDEN_START_DX, corridor_y),
			"camera": player.lerp(rect.get_center(), 0.35)}


## Un compañero se acerca a la vista (pasos cerca) y otro por el pasillo, tras la pared (aviso).
## Se mueven por tiempo real (no por fotograma): los pasos no dependen de la velocidad de captura.
func _walk_npcs(pilot: Autopilot, streamer: FloorStreamer, player: Node2D, hidden_at: Vector2) -> void:
	var walker: AudioFigure = _figure(streamer, player.position + NPC_START_OFFSET, 23, "npcs", "npc_walker")
	walker.anim = "walk"
	walker.facing = Vector2.RIGHT
	var hidden: AudioFigure = _figure(streamer, hidden_at, 37, "npcs", "npc_hidden")
	hidden.anim = "walk"
	hidden.facing = Vector2.LEFT
	var t: float = 0.0
	while t < WALK_S:
		var dt: float = get_process_delta_time()
		t += dt
		walker.position.x += WALK_PX_PER_S * dt
		hidden.position.x -= HIDDEN_PX_PER_S * dt
		walker.queue_redraw()
		hidden.queue_redraw()
		await pilot.frames(1)


func _figure(streamer: FloorStreamer, pos: Vector2, look_seed: int, group: String, npc_id: String) -> AudioFigure:
	var fig: AudioFigure = AudioFigure.new()
	fig.appearance = CharacterPainter.appearance_from_seed(look_seed, 1, false, "")
	fig.npc_id = npc_id
	fig.position = pos
	fig.add_to_group(group)
	streamer.get_actor_layer().add_child(fig)
	return fig


## Figura de muestra (jugador o NPC) dibujada con el pintor de personajes compartido.
class AudioFigure extends Node2D:
	var appearance: Dictionary = {}
	var npc_id: String = ""
	var anim: String = "idle"
	var facing: Vector2 = Vector2.DOWN

	func _draw() -> void:
		CharacterPainter.draw(self, appearance, 1, CharacterPainter.make_pose(anim, 0, facing))


## Hoja de QA dibujada por código: cuatro bandas de degradación, arreglos por banda y subtítulos.
class AudioQASheet extends Control:
	const BAND_COLORS: Array[String] = ["gain", "hazard", "warn", "danger"]
	const BAND_KEYS: Array[String] = ["QA_AUDIO_BAND_0", "QA_AUDIO_BAND_1", "QA_AUDIO_BAND_2", "QA_AUDIO_BAND_3"]
	const RANGE_TEXT: Array[String] = ["0–25", "26–50", "51–75", "76–100"]
	const ARC_COUNT: Dictionary = {"muffled": 1, "compressed": 2, "standard": 3, "strings": 4, "orchestral": 5}
	const IMPORTANCE_COLORS: Array[String] = ["muted", "paper", "warn"]
	const SW_LINE := 0
	const SW_FILL := 1
	const SW_HATCH := 2
	const SPEED_MIN := 0.8
	const SPEED_MAX := 1.1
	const MARGIN := 48.0
	const HEADER_H := 150.0
	const HEADER_H_COMPACT := 104.0
	const ROW_GAP := 16.0
	const LEFT_BLOCK := 360.0
	const RIGHT_SHARE := 0.34
	const MAX_SUBS := 7
	const COMPACT_SCALE := 1.45
	const PANEL_BG := Color("#1a2028")
	const HATCH_STEP := 7.0
	const WAVE_GAIN := 1.9

	var compact: bool = false
	var _rows: Array[Dictionary] = []
	var _bands: Array[Dictionary] = []
	var _subs: Array[Dictionary] = []
	var _scale: float = 1.0
	var _regular: Font
	var _semibold: Font
	var _bold: Font
	var _mono: Font

	func setup(rows: Array[Dictionary], bands: Array[Dictionary], subs: Array[Dictionary]) -> void:
		_rows = rows
		_bands = bands
		_subs = subs
		_regular = UITheme.font(UITheme.FONT_REGULAR)
		_semibold = UITheme.font(UITheme.FONT_SEMIBOLD)
		_bold = UITheme.font(UITheme.FONT_BOLD)
		_mono = UITheme.font(UITheme.FONT_MONO)
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		_scale = COMPACT_SCALE if compact else 1.0
		var r: Rect2 = Rect2(Vector2.ZERO, size)
		var header_h: float = HEADER_H_COMPACT * _scale if compact else HEADER_H
		draw_rect(r, UITheme.color("ink"))
		draw_rect(Rect2(0, 0, r.size.x, header_h), Color(1, 1, 1, 0.03))
		_draw_header(r)
		var right_w: float = 0.0 if compact else (r.size.x - 2.0 * MARGIN) * RIGHT_SHARE
		var top: float = header_h + ROW_GAP
		var rows_rect: Rect2 = Rect2(MARGIN, top, r.size.x - 2.0 * MARGIN - right_w, r.size.y - top - MARGIN * 0.6)
		_draw_rows(rows_rect)
		if not compact:
			var rx: float = rows_rect.end.x + ROW_GAP * 1.5
			_draw_right(Rect2(rx, top, r.end.x - MARGIN - rx, rows_rect.size.y))

	func _fs(px: float) -> int:
		return int(round(px * _scale))

	func _text(pos: Vector2, text: String, font: Font, px: float, col: Color, width: float = -1.0) -> void:
		draw_string(font, pos, text, HORIZONTAL_ALIGNMENT_LEFT, width, _fs(px), col)

	func _panel(rect: Rect2, bg: Color, border: Color) -> void:
		var box: StyleBoxFlat = StyleBoxFlat.new()
		box.bg_color = bg
		box.border_color = border
		box.set_border_width_all(2)
		box.set_corner_radius_all(int(12 * _scale))
		draw_style_box(box, rect)

	func _draw_header(r: Rect2) -> void:
		_text(Vector2(MARGIN, 42 * _scale), tr("QA_AUDIO_KICKER"), _semibold, 18, UITheme.color("accent"))
		_text(Vector2(MARGIN, 88 * _scale), tr("QA_AUDIO_TITLE"), _bold, 40, UITheme.color("paper"))
		if not compact:
			_text(Vector2(MARGIN, 126), tr("QA_AUDIO_SUBTITLE"), _regular, 20, UITheme.color("muted"),
					r.size.x - 2.0 * MARGIN)
		_draw_legend(Vector2(r.size.x - MARGIN, 52 * _scale))

	func _draw_legend(right_top: Vector2) -> void:
		var items: Array = [["QA_AUDIO_LEGEND_SPEED", "paper", SW_LINE], ["QA_AUDIO_LEGEND_PITCH", "rep", SW_LINE],
				["QA_AUDIO_LEGEND_CLEAN", "faint", SW_FILL], ["QA_AUDIO_LEGEND_SOUR", "warn", SW_FILL],
				["QA_AUDIO_LEGEND_ATONAL", "danger", SW_FILL], ["QA_AUDIO_LEGEND_SILENCE", "muted", SW_HATCH]]
		var x: float = right_top.x
		for item: Array in items:
			var label: String = tr(str(item[0]))
			x -= _regular.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(18)).x
			_text(Vector2(x, right_top.y), label, _regular, 18, UITheme.color("muted"))
			x -= 30 * _scale
			_swatch(Rect2(x, right_top.y - 14 * _scale, 22 * _scale, 14 * _scale), UITheme.color(str(item[1])),
					int(item[2]))
			x -= 24 * _scale

	## Muestra de leyenda: línea, bloque lleno o rayado (silencio: gris, nunca rojo como la nota atonal).
	func _swatch(sw: Rect2, c: Color, kind: int) -> void:
		match kind:
			SW_LINE:
				draw_line(Vector2(sw.position.x, sw.get_center().y), Vector2(sw.end.x, sw.get_center().y), c, 3.0)
			SW_FILL:
				draw_rect(sw, c)
			_:
				draw_rect(sw, Color(c, 0.14))
				_hatch(sw, Color(c, 0.85), HATCH_STEP * 0.6)
				draw_rect(sw, c, false, 1.5)

	## Rayado diagonal recortado al rectángulo.
	func _hatch(r: Rect2, c: Color, step: float) -> void:
		var h: float = r.size.y
		var offset: float = -h
		while offset < r.size.x:
			var px: float = r.position.x + offset
			var t0: float = maxf(0.0, r.position.x - px)
			var t1: float = minf(h, r.end.x - px)
			if t0 < t1:
				draw_line(Vector2(px + t0, r.end.y - t0), Vector2(px + t1, r.end.y - t1), c, 1.5, true)
			offset += step

	func _draw_rows(area: Rect2) -> void:
		var h: float = (area.size.y - ROW_GAP * float(_rows.size() - 1)) / float(maxi(1, _rows.size()))
		for i: int in _rows.size():
			var rect: Rect2 = Rect2(area.position.x, area.position.y + float(i) * (h + ROW_GAP), area.size.x, h)
			_draw_row(rect, _rows[i])

	func _draw_row(rect: Rect2, row: Dictionary) -> void:
		var band: int = int(row["band"])
		var tint: Color = UITheme.color(BAND_COLORS[band])
		_panel(rect, PANEL_BG, UITheme.color("line"))
		draw_rect(Rect2(rect.position + Vector2(0, 14), Vector2(6, rect.size.y - 28)), tint)
		var x: float = rect.position.x + 26
		var y: float = rect.position.y
		var left_w: float = LEFT_BLOCK * _scale
		_text(Vector2(x, y + 46 * _scale), RANGE_TEXT[band], _bold, 36, tint)
		_text(Vector2(x, y + 76 * _scale), tr(BAND_KEYS[band]), _bold, 22, UITheme.color("paper"))
		if not compact:
			draw_multiline_string(_regular, Vector2(x, y + 102), tr(BAND_KEYS[band] + "_DESC"),
					HORIZONTAL_ALIGNMENT_LEFT, left_w - 44, _fs(17), 2, UITheme.color("muted"))
		var st: Dictionary = row["stats"]
		var tempo: String = tr("QA_AUDIO_STATS_TEMPO_FMT") % [int(round(float(st["bpm"]))),
				int(round(float(st["pitch_wobble_cents"])))]
		_text(Vector2(x, rect.end.y - 44 * _scale), tempo, _mono, 18, UITheme.color("paper"))
		_draw_chips(Vector2(x, rect.end.y - 18 * _scale), [st["silence"], st["sour"], st["atonal"]])
		var graph: Rect2 = Rect2(rect.position.x + left_w, rect.position.y + 18, rect.size.x - left_w - 24,
				rect.size.y - 52 * _scale)
		_draw_graph(graph, row, tint)

	## Porcentajes de silencio / nota desafinada / nota atonal con la muestra de color de la leyenda.
	func _draw_chips(base: Vector2, values: Array) -> void:
		var kinds: Array = [["muted", SW_HATCH], ["warn", SW_FILL], ["danger", SW_FILL]]
		var x: float = base.x
		for i: int in values.size():
			var sw: Rect2 = Rect2(x, base.y - 13 * _scale, 16 * _scale, 13 * _scale)
			_swatch(sw, UITheme.color(str(kinds[i][0])), int(kinds[i][1]))
			var label: String = "%d%%" % int(round(float(values[i]) * 100.0))
			_text(Vector2(sw.end.x + 6 * _scale, base.y), label, _mono, 16, UITheme.color("muted"))
			x = sw.end.x + 6 * _scale + _mono.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(16)).x + 18 * _scale

	func _draw_graph(g: Rect2, row: Dictionary, tint: Color) -> void:
		draw_rect(g, Color(0, 0, 0, 0.25))
		_draw_silences(g, row["gain"])
		_draw_wave(g, row["peak"], row["envelope"], tint)
		_draw_speed(g, row["rate"], row["pitch"])
		_draw_variants(Rect2(g.position.x, g.end.y + 8, g.size.x, 12 * _scale), row["variant"])

	## Cada tramo de silencio continuo = un solo bloque gris rayado (sin costuras).
	func _draw_silences(g: Rect2, gains: PackedFloat32Array) -> void:
		var bw: float = g.size.x / float(maxi(1, gains.size()))
		var start: int = -1
		for i: int in gains.size() + 1:
			var silent: bool = i < gains.size() and gains[i] < SILENT_GAIN
			if silent and start < 0:
				start = i
			elif not silent and start >= 0:
				var span: Rect2 = Rect2(g.position.x + float(start) * bw, g.position.y, float(i - start) * bw, g.size.y)
				draw_rect(span, Color(UITheme.color("muted"), 0.10))
				_hatch(span, Color(UITheme.color("muted"), 0.28), HATCH_STEP)
				draw_line(span.position, Vector2(span.position.x, span.end.y), Color(UITheme.color("muted"), 0.5), 1.0)
				draw_line(Vector2(span.end.x, span.position.y), span.end, Color(UITheme.color("muted"), 0.5), 1.0)
				start = -1

	## Forma de onda continua (columnas contiguas): pico suave y RMS intenso, con borde superior.
	func _draw_wave(g: Rect2, peak: PackedFloat32Array, env: PackedFloat32Array, tint: Color) -> void:
		var n: int = peak.size()
		var bw: float = g.size.x / float(maxi(1, n))
		var mid: float = g.get_center().y
		var half: float = g.size.y * 0.46
		var outer: PackedVector2Array = PackedVector2Array()
		var inner: PackedVector2Array = PackedVector2Array()
		var edge: PackedVector2Array = PackedVector2Array()
		for i: int in n:
			var x: float = g.position.x + (float(i) + 0.5) * bw
			var hp: float = maxf(0.5, clampf(peak[i], 0.0, 1.0) * half)
			var hr: float = maxf(0.5, clampf(env[i] * WAVE_GAIN, 0.0, 1.0) * half)
			outer.append_array([Vector2(x, mid - hp), Vector2(x, mid + hp)])
			inner.append_array([Vector2(x, mid - hr), Vector2(x, mid + hr)])
			edge.append(Vector2(x, mid - hp))
		draw_multiline(outer, Color(tint, 0.32), bw + 0.6)
		draw_multiline(inner, Color(tint, 0.9), bw + 0.6)
		draw_polyline(edge, Color(tint.lightened(0.25), 0.7), 1.2, true)
		draw_line(Vector2(g.position.x, mid), Vector2(g.end.x, mid), Color(0, 0, 0, 0.35), 1.0)

	func _draw_speed(g: Rect2, rates: PackedFloat32Array, pitches: PackedFloat32Array) -> void:
		var ref_y: float = _speed_y(g, 1.0)
		draw_dashed_line(Vector2(g.position.x, ref_y), Vector2(g.end.x, ref_y), UITheme.color("faint"), 1.5, 8.0)
		_curve(g, pitches, UITheme.color("rep"), 2.0)
		_curve(g, rates, UITheme.color("paper"), 2.5)
		var tag: Rect2 = Rect2(g.end.x - 58 * _scale, ref_y - 11 * _scale, 54 * _scale, 20 * _scale)
		draw_rect(tag, Color(UITheme.color("ink"), 0.85))
		_text(Vector2(tag.position.x + 5 * _scale, tag.end.y - 5 * _scale), "1.00×", _mono, 13, UITheme.color("muted"))

	func _curve(g: Rect2, values: PackedFloat32Array, col: Color, width: float) -> void:
		var pts: PackedVector2Array = PackedVector2Array()
		for i: int in values.size():
			var x: float = g.position.x + (float(i) + 0.5) * g.size.x / float(values.size())
			pts.append(Vector2(x, _speed_y(g, values[i])))
		if pts.size() > 1:
			draw_polyline(pts, Color(0, 0, 0, 0.6), width + 2.5, true)
			draw_polyline(pts, col, width, true)

	func _speed_y(g: Rect2, rate: float) -> float:
		var t: float = clampf((rate - SPEED_MIN) / (SPEED_MAX - SPEED_MIN), 0.0, 1.0)
		return g.end.y - t * g.size.y

	func _draw_variants(strip: Rect2, variants: PackedByteArray) -> void:
		var colors: Array[Color] = [UITheme.color("faint"), UITheme.color("warn"), UITheme.color("danger")]
		var w: float = strip.size.x / float(maxi(1, variants.size()))
		for i: int in variants.size():
			var c: Color = colors[clampi(variants[i], 0, colors.size() - 1)]
			draw_rect(Rect2(strip.position.x + float(i) * w, strip.position.y, w + 0.5, strip.size.y), c)

	func _draw_right(r: Rect2) -> void:
		_text(r.position + Vector2(0, 22), tr("QA_AUDIO_ARRANGEMENTS"), _bold, 23, UITheme.color("paper"))
		var y: float = r.position.y + 40
		var entry_h: float = 72.0
		for entry: Dictionary in _bands:
			_draw_band(Rect2(r.position.x, y, r.size.x, entry_h - 8), entry)
			y += entry_h
		y += 26
		_text(Vector2(r.position.x, y), tr("QA_AUDIO_SUBTITLES"), _bold, 23, UITheme.color("paper"))
		_draw_subtitles(Rect2(r.position.x, y + 16, r.size.x, r.end.y - y - 16))

	func _draw_band(rect: Rect2, entry: Dictionary) -> void:
		var band: Dictionary = entry["band"]
		var pal: Dictionary = band.get("palette", {})
		_panel(rect, PANEL_BG, UITheme.color("line"))
		var tile: Rect2 = Rect2(rect.position + Vector2(8, 6), Vector2(rect.size.y - 12, rect.size.y - 12))
		BandVignette.draw(self, tile, pal, str(band.get("id", "")))
		var x: float = tile.end.x + 14
		var name_text: String = tr(str(band.get("name_key", "")))
		_text(Vector2(x, rect.position.y + 27), name_text, _semibold, 20, UITheme.color("paper"))
		var name_w: float = _semibold.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1, _fs(20)).x
		_text(Vector2(x + name_w + 14, rect.position.y + 27), _floors_text(band.get("floors", [])), _mono, 15,
				UITheme.color("faint"))
		var arr: String = str(entry["arrangement"])
		var suffix: String = arr if arr != AudioTuning.NO_ARRANGEMENT else "none_" + str(band.get("id", ""))
		_text(Vector2(x, rect.position.y + 52), tr("QA_AUDIO_ARR_" + suffix.to_upper()), _regular, 17,
				UITheme.color("muted"), rect.end.x - x - 70)
		_draw_speaker(Vector2(rect.end.x - 56, rect.get_center().y), int(ARC_COUNT.get(arr, 0)),
				Color(str(pal.get("accent", "#ffffff"))))

	func _draw_speaker(c: Vector2, arcs: int, col: Color) -> void:
		var s: float = 11.0
		var body: PackedVector2Array = PackedVector2Array([c + Vector2(-s * 1.6, -s * 0.55), c + Vector2(-s * 0.7, -s * 0.55),
				c + Vector2(s * 0.2, -s * 1.2), c + Vector2(s * 0.2, s * 1.2), c + Vector2(-s * 0.7, s * 0.55),
				c + Vector2(-s * 1.6, s * 0.55)])
		draw_colored_polygon(body, UITheme.color("paper"))
		draw_polyline(body + PackedVector2Array([body[0]]), UITheme.color("ink"), 2.0)
		if arcs == 0:
			draw_line(c + Vector2(s * 0.8, -s * 0.7), c + Vector2(s * 2.2, s * 0.7), UITheme.color("danger"), 3.0)
			draw_line(c + Vector2(s * 0.8, s * 0.7), c + Vector2(s * 2.2, -s * 0.7), UITheme.color("danger"), 3.0)
		for k: int in arcs:
			draw_arc(c + Vector2(s * 0.2, 0), s * (0.9 + 0.55 * float(k)), -0.9, 0.9, 12, col, 2.5, true)

	func _floors_text(floors: Array) -> String:
		if floors.is_empty():
			return ""
		var a: String = _floor_name(int(floors[0]))
		var b: String = _floor_name(int(floors[floors.size() - 1]))
		return a if a == b else "%s–%s" % [a, b]

	func _floor_name(f: int) -> String:
		if f < 0:
			return tr("QA_AUDIO_FLOOR_BASEMENT_FMT") % -f
		if f == 0:
			return tr("QA_AUDIO_FLOOR_GROUND")
		if f == AudioTuning.integer("mundo.planta_azotea"):
			return tr("QA_AUDIO_FLOOR_ROOF")
		if f >= AudioTuning.integer("mundo.planta_fabrica"):
			return ""
		return tr("QA_AUDIO_FLOOR_FMT") % f

	func _draw_subtitles(r: Rect2) -> void:
		var shown: Array[Dictionary] = []
		for s: Dictionary in _subs:
			if shown.size() < MAX_SUBS and not _has_key(shown, str(s["key"])):
				shown.append(s)
		var y: float = r.position.y
		for s: Dictionary in shown:
			var level: int = clampi(int(s["importance"]), 0, IMPORTANCE_COLORS.size() - 1)
			var col: Color = UITheme.color(IMPORTANCE_COLORS[level])
			var pill: Rect2 = Rect2(r.position.x, y, r.size.x, 34)
			_panel(pill, Color(0, 0, 0, 0.55), Color(col, 0.35))
			_draw_direction(pill.position + Vector2(20, 17), s["position"], col)
			var font: Font = _bold if level == 2 else _regular
			_text(pill.position + Vector2(40, 24), tr("HUD_SUBTITLE_FMT") % tr(str(s["key"])), font, 17, col,
					pill.size.x - 50)
			y += 40

	func _has_key(list: Array[Dictionary], key: String) -> bool:
		for s: Dictionary in list:
			if str(s["key"]) == key:
				return true
		return false

	## Flecha hacia la fuente (el oyente de la demo está en el origen) o altavoz si no hay posición.
	func _draw_direction(c: Vector2, pos: Vector2, col: Color) -> void:
		if not pos.is_finite() or pos.length() < 1.0:
			draw_colored_polygon(PackedVector2Array([c + Vector2(-8, -4), c + Vector2(-2, -4), c + Vector2(5, -9),
					c + Vector2(5, 9), c + Vector2(-2, 4), c + Vector2(-8, 4)]), col)
			return
		var d: Vector2 = pos.normalized()
		var n: Vector2 = Vector2(-d.y, d.x)
		draw_line(c - d * 9.0, c + d * 2.0, col, 3.0, true)
		draw_colored_polygon(PackedVector2Array([c + d * 10.0, c + d * 1.0 + n * 6.5, c + d * 1.0 - n * 6.5]), col)


## Viñeta plana con contorno de cada banda (paleta de art_bands.json): una oficina con su altavoz de
## techo, la nave con su cinta transportadora o la calle de noche.
class BandVignette:
	static func draw(ci: CanvasItem, t: Rect2, pal: Dictionary, band_id: String) -> void:
		var outline: Color = Color(str(pal.get("outline", "#000000")))
		match band_id:
			"factory":
				_factory(ci, t, pal, outline)
			"exterior":
				_street(ci, t, pal, outline)
			_:
				_office(ci, t, pal, outline)
		ci.draw_rect(t, outline, false, 2.5)

	static func _c(pal: Dictionary, key: String) -> Color:
		return Color(str(pal.get(key, "#808080")))

	static func _box(ci: CanvasItem, r: Rect2, fill: Color, outline: Color) -> void:
		ci.draw_rect(r, fill)
		ci.draw_rect(r, outline, false, 1.5)

	static func _office(ci: CanvasItem, t: Rect2, pal: Dictionary, outline: Color) -> void:
		var wall_h: float = t.size.y * 0.38
		ci.draw_rect(Rect2(t.position, Vector2(t.size.x, wall_h)), _c(pal, "wall"))
		ci.draw_rect(Rect2(t.position.x, t.position.y + wall_h, t.size.x, t.size.y - wall_h), _c(pal, "floor"))
		ci.draw_rect(Rect2(t.position.x + t.size.x * 0.12, t.end.y - t.size.y * 0.3, t.size.x * 0.76, t.size.y * 0.22),
				_c(pal, "carpet"))
		ci.draw_line(Vector2(t.position.x, t.position.y + wall_h), Vector2(t.end.x, t.position.y + wall_h), outline, 1.5)
		_box(ci, Rect2(t.position + Vector2(t.size.x * 0.1, t.size.y * 0.1), t.size * Vector2(0.28, 0.18)),
				_c(pal, "window"), outline)
		var spk: Vector2 = t.position + Vector2(t.size.x * 0.72, t.size.y * 0.19)
		ci.draw_circle(spk, t.size.x * 0.11, _c(pal, "light"))
		ci.draw_arc(spk, t.size.x * 0.11, 0.0, TAU, 16, outline, 1.5, true)
		for k: int in 3:
			ci.draw_circle(spk + Vector2((float(k) - 1.0) * t.size.x * 0.045, 0.0), 1.2, outline)
		for k: int in 2:
			ci.draw_arc(spk, t.size.x * (0.17 + 0.07 * float(k)), PI * 0.2, PI * 0.8, 8, _c(pal, "accent"), 1.5, true)
		var desk: Rect2 = Rect2(t.position + t.size * Vector2(0.22, 0.5), t.size * Vector2(0.56, 0.2))
		_box(ci, desk, _c(pal, "furniture"), outline)
		_box(ci, Rect2(desk.position + Vector2(desk.size.x * 0.34, -t.size.y * 0.1), t.size * Vector2(0.18, 0.12)),
				_c(pal, "shadow"), outline)
		ci.draw_rect(Rect2(t.position.x + t.size.x * 0.86, t.position.y + wall_h - t.size.y * 0.08, t.size.x * 0.08,
				t.size.y * 0.08), _c(pal, "accent"))

	static func _factory(ci: CanvasItem, t: Rect2, pal: Dictionary, outline: Color) -> void:
		ci.draw_rect(t, _c(pal, "floor"))
		ci.draw_rect(Rect2(t.position, Vector2(t.size.x, t.size.y * 0.3)), _c(pal, "wall"))
		var stripe_w: float = t.size.x / 6.0
		for k: int in 6:
			var col: Color = _c(pal, "accent") if k % 2 == 0 else outline
			ci.draw_rect(Rect2(t.position.x + float(k) * stripe_w, t.position.y + t.size.y * 0.26, stripe_w, t.size.y * 0.06), col)
		var belt: Rect2 = Rect2(t.position.x, t.position.y + t.size.y * 0.58, t.size.x, t.size.y * 0.2)
		_box(ci, belt, _c(pal, "shadow"), outline)
		for k: int in 5:
			var cx: float = belt.position.x + (float(k) + 0.5) * belt.size.x / 5.0
			ci.draw_circle(Vector2(cx, belt.end.y), t.size.y * 0.05, _c(pal, "carpet"))
			ci.draw_arc(Vector2(cx, belt.end.y), t.size.y * 0.05, 0.0, TAU, 10, outline, 1.0, true)
		_box(ci, Rect2(belt.position + Vector2(t.size.x * 0.18, -t.size.y * 0.16), t.size * Vector2(0.24, 0.16)),
				_c(pal, "furniture"), outline)
		_box(ci, Rect2(belt.position + Vector2(t.size.x * 0.6, -t.size.y * 0.13), t.size * Vector2(0.18, 0.13)),
				_c(pal, "light"), outline)

	static func _street(ci: CanvasItem, t: Rect2, pal: Dictionary, outline: Color) -> void:
		ci.draw_rect(t, _c(pal, "shadow"))
		var tower: Rect2 = Rect2(t.position + t.size * Vector2(0.14, 0.12), t.size * Vector2(0.42, 0.6))
		_box(ci, tower, _c(pal, "wall"), outline)
		for row: int in 3:
			for col: int in 2:
				var lit: bool = (row + col) % 2 == 0
				ci.draw_rect(Rect2(tower.position + tower.size * Vector2(0.18 + 0.4 * float(col), 0.12 + 0.28 * float(row)),
						tower.size * Vector2(0.24, 0.14)), _c(pal, "window") if lit else _c(pal, "carpet"))
		ci.draw_rect(Rect2(t.position.x, t.end.y - t.size.y * 0.24, t.size.x, t.size.y * 0.24), _c(pal, "floor"))
		var pole: Vector2 = t.position + t.size * Vector2(0.8, 0.76)
		ci.draw_line(pole, pole - Vector2(0.0, t.size.y * 0.4), outline, 2.0)
		ci.draw_circle(pole - Vector2(0.0, t.size.y * 0.42), t.size.x * 0.07, _c(pal, "accent"))
		ci.draw_circle(pole + Vector2(-t.size.x * 0.04, -t.size.y * 0.2), t.size.x * 0.13, Color(_c(pal, "accent"), 0.18))
		ci.draw_circle(t.position + t.size * Vector2(0.72, 0.14), t.size.x * 0.06, _c(pal, "light"))
