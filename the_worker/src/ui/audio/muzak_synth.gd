# muzak_synth.gd — El hilo musical corporativo (§14.9): composición, arreglos por banda, degradación y render.
# PROPIETARIO DE: nada (funciones puras; quien pide un render guarda los búferes resultantes).
# ESCUCHA: nada.
class_name MuzakSynth
extends RefCounted

## Una "pieza" se renderiza en pistas (stems) de un bucle exacto: acompañamiento + melodía en tres
## variantes (limpia, desafinada, atonal). MuzakDeck las reproduce como una cinta que se degrada.
## Todas las piezas son variaciones del mismo tema de la compañía (leitmotiv): el hilo musical en
## Fa mayor, el menú (música de espera), y los epílogos por eje dominante (§14.9); sin eje
## dominante (híbrido) suena el propio hilo musical del edificio, limpio: te has vuelto parte de él.
## Las notas, acordes y timbres son contenido artístico (como coordenadas de dibujo); los ajustes de
## juego (tempo, umbrales y parámetros de degradación) vienen de balance.json → audio.*.

const BEATS_PER_BAR := 4
const VARIANT_CLEAN := 0
const VARIANT_SOUR := 1
const VARIANT_ATONAL := 2
const VARIANT_COUNT := 3
const SWITCH_MARGIN_S := 0.006
const TONIC_PC := 5
const OCTAVE := 12
const TARGET_PEAK := 0.85
const DEFAULT_PIECE := "muzak"
const DEFAULT_ARRANGEMENT := "standard"
const NO_ARRANGEMENT := "none"

## Tema de la compañía: bossa de ascensor en Fa. [pulso, duración en pulsos, nota MIDI].
const THEME: Array = [
	[0.0, 1.5, 72], [1.5, 0.5, 69], [2.0, 0.5, 67], [2.5, 1.5, 69],
	[4.5, 0.5, 65], [5.0, 0.5, 69], [5.5, 1.5, 72], [7.0, 1.0, 74],
	[8.0, 1.0, 74], [9.0, 0.5, 72], [9.5, 0.5, 70], [10.0, 1.5, 67], [11.5, 0.5, 69],
	[12.0, 0.5, 70], [12.5, 0.5, 69], [13.0, 1.0, 67], [14.0, 0.5, 64], [14.5, 1.5, 67],
	[16.0, 1.5, 72], [17.5, 0.5, 69], [18.0, 0.5, 67], [18.5, 1.5, 69],
	[20.5, 0.5, 65], [21.0, 0.5, 69], [21.5, 1.0, 72], [22.5, 0.5, 74], [23.0, 1.0, 77],
	[24.0, 1.0, 74], [25.0, 0.5, 72], [25.5, 0.5, 70], [26.0, 1.0, 69], [27.0, 1.0, 67],
	[28.0, 0.5, 67], [28.5, 0.5, 69], [29.0, 0.5, 70], [29.5, 2.5, 72],
	[32.0, 1.5, 76], [33.5, 0.5, 74], [34.0, 0.5, 72], [34.5, 1.5, 76],
	[36.0, 1.0, 74], [37.0, 0.5, 72], [37.5, 0.5, 69], [38.0, 1.0, 66], [39.0, 1.0, 69],
	[40.0, 1.5, 70], [41.5, 0.5, 69], [42.0, 0.5, 67], [42.5, 0.5, 65], [43.0, 1.0, 67],
	[44.0, 0.5, 64], [44.5, 0.5, 67], [45.0, 0.5, 72], [45.5, 0.5, 76], [46.0, 1.0, 74],
	[47.0, 0.5, 72], [47.5, 0.5, 70],
	[48.0, 1.5, 74], [49.5, 0.5, 72], [50.0, 0.5, 70], [50.5, 1.5, 69],
	[52.5, 0.5, 67], [53.0, 0.5, 69], [53.5, 1.5, 72], [55.0, 1.0, 76],
	[56.0, 1.0, 74], [57.0, 0.5, 72], [57.5, 0.5, 70], [58.0, 1.0, 69], [59.0, 1.0, 67],
	[60.0, 3.0, 65],
]
## Un acorde por compás: [fundamental MIDI (octava grave), calidad].
const CHORDS_MAJOR: Array = [
	[41, "maj7"], [38, "m7"], [43, "m7"], [36, "7"], [41, "maj7"], [38, "m7"], [43, "m7"], [36, "7"],
	[45, "m7"], [38, "7"], [43, "m7"], [36, "7"], [46, "maj7"], [45, "m7"], [43, "m7"], [36, "7"],
]
const CHORDS_MINOR: Array = [
	[41, "m7"], [37, "maj7"], [43, "m7b5"], [36, "7"], [41, "m7"], [37, "maj7"], [43, "m7b5"], [36, "7"],
	[44, "maj7"], [37, "7"], [43, "m7b5"], [36, "7"], [46, "m7"], [44, "maj7"], [43, "m7b5"], [36, "7"],
]
const CHORD_TONES: Dictionary = {
	"maj7": [0, 4, 7, 11], "m7": [0, 3, 7, 10], "7": [0, 4, 7, 10], "m7b5": [0, 3, 6, 10],
}
## Voicings sin fundamental del piano eléctrico (3ª, 5ª/13ª, 7ª, 9ª).
const VOICINGS: Dictionary = {
	"maj7": [4, 7, 11, 14], "m7": [3, 7, 10, 14], "7": [4, 9, 10, 14], "m7b5": [3, 6, 10, 13],
}
const VOICING_FLOOR := 53
const MINOR_MAP: Dictionary = {4: 3, 9: 8, 11: 10}
## Comping de bossa en dos compases: [pulso, duración].
const COMP_PATTERN: Array = [[[0.0, 0.75], [1.5, 1.0], [3.0, 0.5]], [[0.5, 0.5], [2.0, 1.0], [3.5, 0.5]]]
## Bajo de bossa: [pulso, duración, intervalo sobre la fundamental].
const BASS_PATTERN: Array = [[0.0, 1.5, 0], [1.5, 0.5, 7], [2.0, 1.5, 7], [3.5, 0.5, 0]]
const BASS_CEILING := 47
const RIM_PATTERN: Array = [[0.0, 1.5, 3.0], [1.0, 2.5]]

const PIECES: Dictionary = {
	"muzak": {"bars": 16, "transpose": 0, "minor": false, "degradable": true, "arrangement": "standard"},
	"menu": {"bars": 16, "transpose": 0, "minor": false, "degradable": false, "arrangement": "hold"},
	"epilogue_sweat": {"bars": 8, "transpose": 0, "minor": false, "degradable": false, "arrangement": "ep_solo"},
	"epilogue_gold": {"bars": 16, "transpose": 5, "minor": false, "degradable": false, "arrangement": "brass_band"},
	"epilogue_silk": {"bars": 16, "transpose": -3, "minor": true, "degradable": false, "arrangement": "noir"},
	"epilogue_blood": {"bars": 8, "transpose": 0, "minor": true, "degradable": false, "arrangement": "dirge"},
	"epilogue_ruin": {"bars": 16, "transpose": 0, "minor": false, "degradable": true, "arrangement": "standard"},
	"epilogue_hybrid": {"bars": 16, "transpose": 0, "minor": false, "degradable": false, "arrangement": "standard"},
}

## Arreglos: más orquestal arriba, más comprimido abajo (§14.9). hp/lp = altavoz del edificio.
const ARRANGEMENTS: Dictionary = {
	"muffled": {"lead": "sax", "double": "", "lead_gain": 0.6, "comp_gain": 0.2, "bass_gain": 0.5,
		"drums": "brush", "drum_gain": 0.6, "pad_gain": 0.0, "harp_gain": 0.0,
		"hp": 45.0, "lp": 620.0, "drive": 1.0},
	"compressed": {"lead": "sax", "double": "", "lead_gain": 0.65, "comp_gain": 0.2, "bass_gain": 0.3,
		"drums": "machine", "drum_gain": 0.9, "pad_gain": 0.0, "harp_gain": 0.0,
		"hp": 380.0, "lp": 3300.0, "drive": 2.6},
	"standard": {"lead": "sax", "double": "", "lead_gain": 0.7, "comp_gain": 0.2, "bass_gain": 0.36,
		"drums": "brush", "drum_gain": 0.9, "pad_gain": 0.0, "harp_gain": 0.0,
		"hp": 90.0, "lp": 6500.0, "drive": 1.3},
	"strings": {"lead": "sax", "double": "", "lead_gain": 0.62, "comp_gain": 0.16, "bass_gain": 0.36,
		"drums": "brush_soft", "drum_gain": 0.7, "pad_gain": 0.045, "harp_gain": 0.0,
		"hp": 60.0, "lp": 8000.0, "drive": 1.1},
	"orchestral": {"lead": "sax", "double": "flute", "lead_gain": 0.6, "comp_gain": 0.12,
		"bass_gain": 0.36, "drums": "soft", "drum_gain": 0.6, "pad_gain": 0.05, "harp_gain": 0.2,
		"hp": 40.0, "lp": 9500.0, "drive": 1.0},
	"hold": {"lead": "vibes", "double": "", "lead_gain": 0.65, "comp_gain": 0.16, "bass_gain": 0.34,
		"drums": "brush", "drum_gain": 0.75, "pad_gain": 0.035, "harp_gain": 0.0,
		"hp": 35.0, "lp": 10000.0, "drive": 1.0},
	"ep_solo": {"lead": "ep_lead", "double": "", "lead_gain": 0.7, "comp_gain": 0.1, "bass_gain": 0.25,
		"drums": "none", "drum_gain": 0.0, "pad_gain": 0.045, "harp_gain": 0.0,
		"hp": 35.0, "lp": 9000.0, "drive": 1.0},
	"brass_band": {"lead": "brass", "double": "", "lead_gain": 0.65, "comp_gain": 0.18,
		"bass_gain": 0.4, "drums": "machine", "drum_gain": 0.9, "pad_gain": 0.0, "harp_gain": 0.0,
		"hp": 50.0, "lp": 9000.0, "drive": 1.4},
	"noir": {"lead": "sax_low", "double": "", "lead_gain": 0.7, "comp_gain": 0.18, "bass_gain": 0.4,
		"drums": "brush", "drum_gain": 0.8, "pad_gain": 0.0, "harp_gain": 0.0,
		"hp": 50.0, "lp": 7000.0, "drive": 1.2},
	"dirge": {"lead": "sax_low", "double": "", "lead_gain": 0.7, "comp_gain": 0.0, "bass_gain": 0.32,
		"drums": "none", "drum_gain": 0.0, "pad_gain": 0.07, "harp_gain": 0.0,
		"hp": 35.0, "lp": 6000.0, "drive": 1.0},
}

# ─── Degradación (pura, §14.9) ───────────────────────────────────

## Banda de degradación: número de umbrales superados (0-25 → 0, 26-50 → 1, 51-75 → 2, 76+ → 3).
static func degradation_band(suspicion: float, thresholds: Array) -> int:
	var band: int = 0
	for t: Variant in thresholds:
		if suspicion > float(t):
			band += 1
	return band


## Parámetros de degradación para una sospecha dada con la tabla de balance `audio.degradacion`.
static func degradation_from(suspicion: float, table: Dictionary) -> Dictionary:
	var levels: Array = table.get("niveles", [])
	if levels.is_empty():
		return {}
	var band: int = mini(degradation_band(suspicion, table.get("umbrales", [])), levels.size() - 1)
	var lv: Dictionary = levels[band]
	return {
		"band": band, "tempo": float(lv.get("tempo", 1.0)), "jitter": float(lv.get("irregular", 0.0)),
		"wow": float(lv.get("wow", 0.0)), "flutter": float(lv.get("flutter", 0.0)),
		"sour": float(lv.get("desafinadas", 0.0)), "atonal": float(lv.get("atonales", 0.0)),
		"dropouts_per_s": float(lv.get("silencios_por_s", 0.0)),
		"cuts_per_s": float(lv.get("cortes_por_s", 0.0)), "hiss": float(lv.get("siseo", 0.0)),
		"lowpass_hz": float(lv.get("filtro_hz", 0.0)), "wow_hz": float(table.get("wow_hz", 0.0)),
		"flutter_hz": float(table.get("flutter_hz", 0.0)),
		"dropout_s": _pair(table.get("silencio_s", [])), "cut_s": _pair(table.get("corte_s", [])),
		"jitter_change_s": _pair(table.get("irregular_cambio_s", [])),
		"jump_fade_s": float(table.get("salto_fundido_s", 0.0)),
		"jump_lead_s": float(table.get("salto_antes_s", 0.0)),
	}


## Parámetros de degradación leídos de balance.json.
static func degradation(suspicion: float) -> Dictionary:
	return degradation_from(suspicion, AudioTuning.dict("audio.degradacion"))


## Ajustes de render resueltos en el hilo principal (los hilos de render no leen autoloads).
static func render_config(piece_id: String) -> Dictionary:
	var table: Dictionary = AudioTuning.dict("audio.degradacion")
	return {
		"rate": AudioTuning.integer("audio.frecuencia_muestreo"),
		"bpm": AudioTuning.num("audio.piezas_bpm." + piece_id),
		"seed": AudioTuning.integer("audio.muzak.semilla"),
		"sour_cents": _pair(table.get("desafinado_centimos", [])),
		"atonal_shifts": table.get("atonal_semitonos", []),
		"atonal_cents": float(table.get("atonal_centimos", 0.0)),
	}


static func has_piece(piece_id: String) -> bool:
	return PIECES.has(piece_id)


static func has_arrangement(arrangement_id: String) -> bool:
	return ARRANGEMENTS.has(arrangement_id)


static func default_arrangement(piece_id: String) -> String:
	return str((PIECES.get(piece_id, PIECES[DEFAULT_PIECE]) as Dictionary)["arrangement"])


static func _pair(a: Variant) -> Vector2:
	if a is Array and (a as Array).size() >= 2:
		return Vector2(float(a[0]), float(a[1]))
	return Vector2.ZERO


# ─── Partitura ───────────────────────────────────────────────────

## {melody: [[pulso, dur, midi]], chords: [[raíz, calidad]], bars} de una pieza (transpuesta/menor).
static func score_for(piece_id: String) -> Dictionary:
	var piece: Dictionary = PIECES.get(piece_id, PIECES[DEFAULT_PIECE])
	var bars: int = int(piece["bars"])
	var shift: int = int(piece["transpose"])
	var minor: bool = bool(piece["minor"])
	var melody: Array = []
	for note: Array in THEME:
		if float(note[0]) >= float(bars * BEATS_PER_BAR):
			continue
		var midi: int = int(note[2])
		if minor:
			midi = _to_minor(midi)
		melody.append([float(note[0]), float(note[1]), midi + shift])
	var source: Array = CHORDS_MINOR if minor else CHORDS_MAJOR
	var chords: Array = []
	for i: int in bars:
		chords.append([int(source[i][0]) + shift, str(source[i][1])])
	return {"melody": melody, "chords": chords, "bars": bars}


static func _to_minor(midi: int) -> int:
	var interval: int = posmod(midi - TONIC_PC, OCTAVE)
	if MINOR_MAP.has(interval):
		return midi + int(MINOR_MAP[interval]) - interval
	return midi


## Voicing del piano eléctrico por encima de VOICING_FLOOR.
static func voicing(root: int, quality: String) -> Array[int]:
	var base: int = root
	var first: int = int((VOICINGS[quality] as Array)[0])
	while base + first < VOICING_FLOOR:
		base += OCTAVE
	var out: Array[int] = []
	for iv: Variant in VOICINGS[quality]:
		out.append(base + int(iv))
	return out


## Puntos (muestras) donde puede cambiar la variante de la melodía: justo antes de cada nota.
static func switch_points(score: Dictionary, spb: float, rate: int) -> PackedInt32Array:
	var out: PackedInt32Array = PackedInt32Array()
	for note: Array in score["melody"]:
		out.append(maxi(0, int(round(float(note[0]) * spb - SWITCH_MARGIN_S * rate))))
	return out


# ─── Render ──────────────────────────────────────────────────────

## Renderiza las pistas de una pieza. Puro y seguro en hilos (tras SynthDSP.warm_up()).
## `variants` = variantes de melodía a renderizar ya (-1 = todas); el resto se añade después con
## add_variants() para que el hilo musical empiece a sonar antes (render en dos fases).
## Devuelve {rate, length, spb, acc, mel: Array[PackedFloat32Array], switches, piece, arrangement,
## gain, degradable}.
static func render_piece(piece_id: String, arrangement_id: String, cfg: Dictionary,
		variants: int = -1) -> Dictionary:
	var piece: Dictionary = PIECES.get(piece_id, PIECES[DEFAULT_PIECE])
	var arr: Dictionary = ARRANGEMENTS.get(arrangement_id, ARRANGEMENTS[DEFAULT_ARRANGEMENT])
	var rate: int = int(cfg["rate"])
	var spb: float = float(rate) * 60.0 / maxf(1.0, float(cfg["bpm"]))
	var score: Dictionary = score_for(piece_id)
	var length: int = int(round(float(int(score["bars"]) * BEATS_PER_BAR) * spb))
	var acc: PackedFloat32Array = MuzakVoices.accompaniment(score, arr, rate, spb, length)
	var mel0: PackedFloat32Array = MuzakVoices.melody(score, arr, rate, spb, length, VARIANT_CLEAN, cfg)
	_speaker(acc, arr, rate)
	_speaker(mel0, arr, rate)
	var gain: float = _common_gain(acc, mel0)
	SynthDSP.scale(acc, gain)
	SynthDSP.scale(mel0, gain)
	var mel: Array[PackedFloat32Array] = [mel0]
	var stems: Dictionary = {
		"rate": rate, "length": length, "spb": spb, "acc": acc, "mel": mel, "gain": gain,
		"switches": switch_points(score, spb, rate), "piece": piece_id, "arrangement": arrangement_id,
		"degradable": bool(piece["degradable"]),
	}
	if variants < 0 or variants > 1:
		return add_variants(stems, cfg)
	return stems


## Devuelve una copia de `stems` con las variantes desafinada y atonal añadidas (si la pieza se degrada).
static func add_variants(stems: Dictionary, cfg: Dictionary) -> Dictionary:
	var out: Dictionary = stems.duplicate()
	var mel: Array[PackedFloat32Array] = []
	mel.assign(stems["mel"])
	if not bool(stems.get("degradable", false)):
		out["mel"] = mel
		return out
	var arr: Dictionary = ARRANGEMENTS.get(str(stems["arrangement"]), ARRANGEMENTS[DEFAULT_ARRANGEMENT])
	var score: Dictionary = score_for(str(stems["piece"]))
	var rate: int = int(stems["rate"])
	for v: int in range(mel.size(), VARIANT_COUNT):
		var track: PackedFloat32Array = MuzakVoices.melody(score, arr, rate, float(stems["spb"]),
				int(stems["length"]), v, cfg)
		_speaker(track, arr, rate)
		SynthDSP.scale(track, float(stems["gain"]))
		mel.append(track)
	out["mel"] = mel
	return out


## Altavoz del edificio: paso alto, paso bajo de 12 dB/oct y saturación.
static func _speaker(track: PackedFloat32Array, arr: Dictionary, rate: int) -> void:
	SynthDSP.highpass(track, rate, float(arr["hp"]))
	SynthDSP.lowpass(track, rate, float(arr["lp"]), 2)
	if float(arr["drive"]) > 1.0:
		SynthDSP.soft_clip(track, float(arr["drive"]))


## Ganancia común para que acompañamiento + melodía alcancen TARGET_PEAK.
static func _common_gain(acc: PackedFloat32Array, mel: PackedFloat32Array) -> float:
	var p: float = 0.0
	for i: int in acc.size():
		p = maxf(p, absf(acc[i] + mel[i]))
	return TARGET_PEAK / p if p > SynthDSP.DENORMAL_GUARD else 1.0


## Render sin conexión (tests, WAV de revisión): pista + cinta con la degradación de `suspicion`.
## Devuelve {samples: PackedFloat32Array mono, telemetry, rate, degradation}.
static func render_offline(stems: Dictionary, suspicion: float, seconds: float,
		with_telemetry: bool) -> Dictionary:
	var rate: int = int(stems["rate"])
	var deck: MuzakDeck = MuzakDeck.new()
	deck.setup(rate, AudioTuning.integer("audio.muzak.semilla"), 0.0, 0.0)
	deck.record_telemetry = with_telemetry
	deck.load_stems_now(stems)
	var params: Dictionary = degradation(suspicion)
	deck.set_degradation(params, true)
	var frames: PackedVector2Array = deck.process(int(seconds * rate))
	var mono: PackedFloat32Array = PackedFloat32Array()
	mono.resize(frames.size())
	for i: int in frames.size():
		mono[i] = frames[i].x
	return {"samples": mono, "telemetry": deck.get_telemetry(), "rate": rate, "degradation": params}


## Escribe `seconds` de hilo musical con la sospecha dada en un WAV PCM (revisión sin escuchar).
static func export_wav(path: String, stems: Dictionary, suspicion: float, seconds: float) -> Error:
	var result: Dictionary = render_offline(stems, suspicion, seconds, false)
	return SynthDSP.write_wav(path, result["samples"], int(result["rate"]))
