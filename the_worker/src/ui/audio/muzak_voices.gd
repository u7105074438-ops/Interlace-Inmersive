# muzak_voices.gd — Instrumentos del hilo musical: saxo sintético, piano eléctrico, bajo, escobillas, cuerdas, arpa.
# PROPIETARIO DE: nada (funciones puras de render, seguras en hilos tras SynthDSP.warm_up()).
# ESCUCHA: nada.
class_name MuzakVoices
extends RefCounted

## Instrumentación "barata" a propósito (§14.11): osciladores ingenuos, FM de dos operadores,
## Karplus-Strong. Constantes = diseño sonoro (timbres), no ajustes de juego.

const BEATS_PER_BAR := 4
const ARTICULATION := 0.86
const BASS_ARTICULATION := 0.9
const VARIANT_SEED_STEP := 1009
const CENTS_PER_SEMITONE := 100.0
const DOUBLE_GAIN := 0.35
const DOUBLE_OCTAVE := 12.0
const HARP_OCTAVES: Array[int] = [24, 36]
const HARP_NOTES := 8
const HARP_STEP_BEATS := 0.5
const HARP_DUR_S := 1.3
const HARP_DAMPING := 0.996
const EP_RELEASE_S := 0.08
const BASS_RELEASE_S := 0.05
const PAD_RELEASE_S := 0.45
const PAD_ATTACK_S := 0.35
const PAD_DETUNE_CENTS := 7.0
const PAD_LP_HZ := 1700.0
const LEAD_RELEASE_S := 0.07
const SCOOP_TAU_S := 0.045
const VIBRATO_FADE_S := 0.2
const CENT_LINEAR := 0.000577623
const SUSTAIN := 0.82
const DECAY_S := 0.12
const BREATH_FLOOR := 0.35
const FILTER_CEILING_DIV := 7.0
## Voces de lengüeta/metal. Índices en R_*.
const REEDS: Dictionary = {
	"sax": [0.22, 850.0, 2300.0, 0.85, 0.11, 18.0, 5.3, 0.16, 60.0, 0.025, 0.03, 0.0, 0.55],
	"sax_low": [0.18, 520.0, 1500.0, 0.8, 0.16, 16.0, 4.8, 0.2, 45.0, 0.035, 0.05, -12.0, 0.6],
	"brass": [0.0, 600.0, 3000.0, 1.1, 0.03, 7.0, 5.8, 0.25, 30.0, 0.04, 0.04, 0.0, 0.5],
}
const R_SQUARE := 0
const R_CUT := 1
const R_ENV_CUT := 2
const R_DAMP := 3
const R_BREATH := 4
const R_VIB_CENTS := 5
const R_VIB_HZ := 6
const R_VIB_DELAY := 7
const R_SCOOP := 8
const R_ATTACK := 9
const R_RELEASE := 10
const R_OCTAVE := 11
const R_AMP := 12


# ─── Acompañamiento ──────────────────────────────────────────────

static func accompaniment(score: Dictionary, arr: Dictionary, rate: int, spb: float,
		length: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(length)
	var cache: Dictionary = {}
	var chords: Array = score["chords"]
	for bar: int in chords.size():
		var root: int = int(chords[bar][0])
		var quality: String = str(chords[bar][1])
		var at: float = float(bar * BEATS_PER_BAR)
		_comp_bar(buf, rate, spb, bar, at, root, quality, float(arr["comp_gain"]), cache)
		_bass_bar(buf, rate, spb, at, root, float(arr["bass_gain"]), cache)
		_drum_bar(buf, rate, spb, bar, at, str(arr["drums"]), float(arr["drum_gain"]), cache)
		_pad_bar(buf, rate, spb, at, root, quality, float(arr["pad_gain"]), cache)
		_harp_bar(buf, rate, spb, at, root, quality, float(arr["harp_gain"]), cache)
	return buf


static func _comp_bar(buf: PackedFloat32Array, rate: int, spb: float, bar: int, at: float, root: int,
		quality: String, gain: float, cache: Dictionary) -> void:
	if gain <= 0.0:
		return
	var notes: Array[int] = MuzakSynth.voicing(root, quality)
	for hit: Array in MuzakSynth.COMP_PATTERN[bar % 2]:
		var gate_s: float = float(hit[1]) * spb / float(rate)
		var key: String = "ep:%d:%s:%d" % [root, quality, int(gate_s * 1000.0)]
		if not cache.has(key):
			cache[key] = ep_chord(notes, gate_s, rate)
		var start: int = int(round((at + float(hit[0])) * spb))
		SynthDSP.mix_into(buf, cache[key], start, gain, true)


static func _bass_bar(buf: PackedFloat32Array, rate: int, spb: float, at: float, root: int,
		gain: float, cache: Dictionary) -> void:
	if gain <= 0.0:
		return
	for step: Array in MuzakSynth.BASS_PATTERN:
		var midi: int = root + int(step[2])
		if midi > MuzakSynth.BASS_CEILING:
			midi -= MuzakSynth.OCTAVE
		var gate_s: float = float(step[1]) * spb / float(rate) * BASS_ARTICULATION
		var key: String = "bass:%d:%d" % [midi, int(gate_s * 1000.0)]
		if not cache.has(key):
			cache[key] = bass(SynthDSP.midi_hz(midi), gate_s, rate)
		SynthDSP.mix_into(buf, cache[key], int(round((at + float(step[0])) * spb)), gain, true)


static func _drum_bar(buf: PackedFloat32Array, rate: int, spb: float, bar: int, at: float,
		style: String, gain: float, cache: Dictionary) -> void:
	if gain <= 0.0:
		return
	for hit: Array in drum_hits(style, bar):
		var kind: String = str(hit[1])
		if not cache.has(kind):
			cache[kind] = drum(kind, rate)
		var start: int = int(round((at + float(hit[0])) * spb))
		SynthDSP.mix_into(buf, cache[kind], start, gain * float(hit[2]), true)


static func _pad_bar(buf: PackedFloat32Array, rate: int, spb: float, at: float, root: int,
		quality: String, gain: float, cache: Dictionary) -> void:
	if gain <= 0.0:
		return
	var key: String = "pad:%d:%s" % [root, quality]
	if not cache.has(key):
		var notes: Array[int] = []
		for iv: Variant in MuzakSynth.CHORD_TONES[quality]:
			notes.append(root + MuzakSynth.OCTAVE + int(iv))
		cache[key] = pad_chord(notes, float(BEATS_PER_BAR) * spb / float(rate), rate)
	SynthDSP.mix_into(buf, cache[key], int(round(at * spb)), gain, true)


static func _harp_bar(buf: PackedFloat32Array, rate: int, spb: float, at: float, root: int,
		quality: String, gain: float, cache: Dictionary) -> void:
	if gain <= 0.0:
		return
	var seq: Array[int] = []
	for octave: int in HARP_OCTAVES:
		for iv: Variant in MuzakSynth.CHORD_TONES[quality]:
			seq.append(root + octave + int(iv))
	for k: int in mini(HARP_NOTES, seq.size()):
		var key: String = "harp:%d" % seq[k]
		if not cache.has(key):
			var note: PackedFloat32Array = SynthDSP.silence(HARP_DUR_S, rate)
			SynthDSP.pluck_into(note, rate, 0.0, HARP_DUR_S, SynthDSP.midi_hz(seq[k]), 1.0,
					HARP_DAMPING, seq[k])
			cache[key] = note
		var start: int = int(round((at + float(k) * HARP_STEP_BEATS) * spb))
		SynthDSP.mix_into(buf, cache[key], start, gain, true)


## Golpes de batería de un compás por estilo: [pulso, tipo, nivel].
static func drum_hits(style: String, bar: int) -> Array:
	var hits: Array = []
	var rims: Array = MuzakSynth.RIM_PATTERN[bar % 2]
	match style:
		"brush", "brush_soft":
			var soft: float = 0.7 if style == "brush_soft" else 1.0
			hits.append_array([[0.0, "swish", soft], [2.0, "swish", 0.9 * soft],
					[1.0, "tap", 0.8 * soft], [3.0, "tap", 0.8 * soft]])
			if style == "brush":
				hits.append_array([[0.0, "kick", 0.45], [2.0, "kick", 0.35]])
			for b: Variant in rims:
				hits.append([float(b), "rim", 0.6 * soft])
		"machine":
			hits.append_array([[0.0, "kick", 0.8], [2.0, "kick", 0.7]])
			for b: Variant in rims:
				hits.append([float(b), "rim", 0.7])
			for e: int in BEATS_PER_BAR * 2:
				hits.append([float(e) * 0.5, "hat", 0.9 if e % 2 == 1 else 0.5])
		"soft":
			hits.append_array([[0.0, "swish", 0.8], [2.0, "swish", 0.7], [1.0, "tap", 0.5],
					[3.0, "tap", 0.5]])
	return hits


static func drum(kind: String, rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(0.4, rate)
	match kind:
		"kick":
			SynthDSP.tone_into(buf, rate, 0.0, 0.3, 110.0, 42.0, 0.9, SynthDSP.Wave.SINE, 0.002, 0.11)
		"rim":
			SynthDSP.tone_into(buf, rate, 0.0, 0.05, 1700.0, 1650.0, 0.35, SynthDSP.Wave.SINE, 0.0, 0.01)
			SynthDSP.tone_into(buf, rate, 0.0, 0.05, 520.0, 500.0, 0.25, SynthDSP.Wave.SINE, 0.0, 0.015)
			SynthDSP.noise_into(buf, rate, 0.0, 0.015, 0.3, 0.0, 0.003, 2500.0, 0.0, 11)
		"swish":
			SynthDSP.noise_into(buf, rate, 0.0, 0.34, 0.3, 0.06, 0.1, 2200.0, 7000.0, 23)
		"tap":
			SynthDSP.noise_into(buf, rate, 0.0, 0.1, 0.45, 0.002, 0.03, 1500.0, 6000.0, 37)
		"hat":
			SynthDSP.noise_into(buf, rate, 0.0, 0.06, 0.3, 0.001, 0.012, 6500.0, 0.0, 53)
	return buf


# ─── Timbres ─────────────────────────────────────────────────────

## Acorde de piano eléctrico FM (el "Rhodes" de preset barato).
static func ep_chord(notes: Array[int], gate_s: float, rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = SynthDSP.silence(gate_s + EP_RELEASE_S, rate)
	var dur: float = gate_s + EP_RELEASE_S
	for midi: int in notes:
		var f: float = SynthDSP.midi_hz(midi)
		SynthDSP.bell_into(buf, rate, 0.0, dur, f, 0.22, 1.0, 1.7, 0.9)
		SynthDSP.bell_into(buf, rate, 0.0, minf(dur, 0.2), f * 4.0, 0.03, 1.0, 0.4, 0.05)
	release(buf, rate, gate_s, EP_RELEASE_S)
	return buf


static func bass(freq: float, gate_s: float, rate: int) -> PackedFloat32Array:
	var dur: float = gate_s + BASS_RELEASE_S
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	SynthDSP.tone_into(buf, rate, 0.0, dur, freq * 1.03, freq, 0.7, SynthDSP.Wave.SINE, 0.004, 0.5)
	SynthDSP.tone_into(buf, rate, 0.0, dur, freq * 2.0, freq * 2.0, 0.2, SynthDSP.Wave.SINE, 0.004, 0.18)
	SynthDSP.tone_into(buf, rate, 0.0, dur, freq, freq, 0.16, SynthDSP.Wave.TRIANGLE, 0.004, 0.3)
	release(buf, rate, gate_s, BASS_RELEASE_S)
	return buf


## Colchón de cuerdas: dos sierras desafinadas por nota, ataque lento, paso bajo.
static func pad_chord(notes: Array[int], gate_s: float, rate: int) -> PackedFloat32Array:
	var dur: float = gate_s + PAD_RELEASE_S
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	for midi: int in notes:
		var f: float = SynthDSP.midi_hz(midi)
		for c: float in [-PAD_DETUNE_CENTS, PAD_DETUNE_CENTS]:
			var fc: float = f * SynthDSP.cents_ratio(c)
			SynthDSP.tone_into(buf, rate, 0.0, dur, fc, fc, 0.2, SynthDSP.Wave.SAW, PAD_ATTACK_S, 0.0)
	release(buf, rate, gate_s, PAD_RELEASE_S)
	SynthDSP.lowpass(buf, rate, PAD_LP_HZ, 2)
	return buf


## Relajación lineal desde `gate_s` durante `rel_s`.
static func release(buf: PackedFloat32Array, rate: int, gate_s: float, rel_s: float) -> void:
	var gate: int = int(gate_s * rate)
	var rel: float = maxf(1.0, rel_s * rate)
	for i: int in range(gate, buf.size()):
		buf[i] *= maxf(0.0, 1.0 - float(i - gate) / rel)


# ─── Melodía ─────────────────────────────────────────────────────

## Pista de melodía para una variante (limpia, desafinada, atonal). Determinista por semilla.
static func melody(score: Dictionary, arr: Dictionary, rate: int, spb: float, length: int,
		variant: int, cfg: Dictionary) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(length)
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = int(cfg["seed"]) + variant * VARIANT_SEED_STEP
	var notes: Array = score["melody"]
	var double: String = str(arr["double"])
	for i: int in notes.size():
		var note: Array = notes[i]
		var midi: float = float(note[2]) + variant_offset(variant, rng, cfg)
		var gate_s: float = float(note[1]) * spb / float(rate) * ARTICULATION
		var start: int = int(round(float(note[0]) * spb))
		var voice: PackedFloat32Array = lead_note(str(arr["lead"]), midi, gate_s, rate, i)
		SynthDSP.mix_into(buf, voice, start, float(arr["lead_gain"]), true)
		if not double.is_empty():
			var dbl: PackedFloat32Array = lead_note(double, midi + DOUBLE_OCTAVE, gate_s, rate, i)
			SynthDSP.mix_into(buf, dbl, start, float(arr["lead_gain"]) * DOUBLE_GAIN, true)
	return buf


## Desplazamiento en semitonos de una nota según la variante (0 en la limpia).
static func variant_offset(variant: int, rng: RandomNumberGenerator, cfg: Dictionary) -> float:
	if variant == MuzakSynth.VARIANT_SOUR:
		var sour: Vector2 = cfg["sour_cents"]
		var sign: float = 1.0 if rng.randf() < 0.5 else -1.0
		return sign * rng.randf_range(sour.x, sour.y) / CENTS_PER_SEMITONE
	if variant == MuzakSynth.VARIANT_ATONAL:
		var shifts: Array = cfg["atonal_shifts"]
		var cents: float = float(cfg["atonal_cents"])
		var semis: float = float(shifts[rng.randi() % shifts.size()]) if not shifts.is_empty() else 0.0
		return semis + rng.randf_range(-cents, cents) / CENTS_PER_SEMITONE
	return 0.0


static func lead_note(kind: String, midi: float, gate_s: float, rate: int, seed: int) -> PackedFloat32Array:
	if REEDS.has(kind):
		return reed(REEDS[kind], midi, gate_s, rate, seed)
	var dur: float = gate_s + LEAD_RELEASE_S
	var buf: PackedFloat32Array = SynthDSP.silence(dur, rate)
	var f: float = SynthDSP.midi_hz(midi)
	match kind:
		"flute":
			return flute(midi, gate_s, rate, seed)
		"vibes":
			SynthDSP.bell_into(buf, rate, 0.0, dur, f, 0.45, 4.0, 1.1, 0.7)
			SynthDSP.bell_into(buf, rate, 0.0, dur, f, 0.3, 1.0, 0.3, 1.2)
			SynthDSP.amp_mod(buf, rate, 5.5, 0.25, false)
		_:
			SynthDSP.bell_into(buf, rate, 0.0, dur, f, 0.5, 1.0, 1.8, 1.0)
			SynthDSP.bell_into(buf, rate, 0.0, minf(dur, 0.2), f * 4.0, 0.06, 1.0, 0.4, 0.05)
	release(buf, rate, gate_s, LEAD_RELEASE_S)
	return buf


## "Saxofón" sintético: sierra + cuadrada, scoop de afinación, vibrato retardado, aliento, filtro SVF.
static func reed(p: Array, midi: float, gate_s: float, rate: int, seed: int) -> PackedFloat32Array:
	var freq: float = SynthDSP.midi_hz(midi + float(p[R_OCTAVE]))
	var rel: float = float(p[R_RELEASE])
	var buf: PackedFloat32Array = SynthDSP.silence(gate_s + rel, rate)
	var noise: PackedFloat32Array = SynthDSP.noise_table()
	var off: int = absi(seed * 7349) & SynthDSP.NOISE_MASK
	var v: PackedFloat32Array = PackedFloat32Array(p)
	var inc: float = freq / float(rate)
	var dec_k: float = exp(-1.0 / (DECAY_S * rate))
	var scoop_k: float = exp(-1.0 / (SCOOP_TAU_S * rate))
	var vib_w: float = TAU * v[R_VIB_HZ]
	var f_scale: float = TAU / float(rate)
	var max_fc: float = float(rate) / FILTER_CEILING_DIV
	var dec: float = 1.0
	var scoop: float = v[R_SCOOP]
	var ph: float = 0.0
	var low: float = 0.0
	var band: float = 0.0
	for i: int in buf.size():
		var t: float = float(i) / rate
		var env: float = minf(1.0, t / v[R_ATTACK]) * (SUSTAIN + (1.0 - SUSTAIN) * dec) \
				* clampf(1.0 - (t - gate_s) / rel, 0.0, 1.0)
		var depth: float = v[R_VIB_CENTS] * clampf((t - v[R_VIB_DELAY]) / VIBRATO_FADE_S, 0.0, 1.0)
		ph += inc * (1.0 + (depth * sin(vib_w * t) - scoop) * CENT_LINEAR)
		if ph >= 1.0:
			ph -= 1.0
		dec *= dec_k
		scoop *= scoop_k
		var x: float = (2.0 * ph - 1.0) * (1.0 - v[R_SQUARE]) + (v[R_SQUARE] if ph < 0.5 else -v[R_SQUARE])
		x += noise[(off + i) & SynthDSP.NOISE_MASK] * v[R_BREATH] * (BREATH_FLOOR + env)
		var f: float = f_scale * minf(v[R_CUT] + v[R_ENV_CUT] * env, max_fc)
		low += f * band
		band += f * (x - low - v[R_DAMP] * band)
		buf[i] = low * env * v[R_AMP]
	return buf


## Flauta: seno + armónico + aliento, vibrato suave (doblaje orquestal de las plantas altas).
static func flute(midi: float, gate_s: float, rate: int, seed: int) -> PackedFloat32Array:
	var freq: float = SynthDSP.midi_hz(midi)
	var buf: PackedFloat32Array = SynthDSP.silence(gate_s + LEAD_RELEASE_S, rate)
	var noise: PackedFloat32Array = SynthDSP.noise_table()
	var off: int = absi(seed * 3571) & SynthDSP.NOISE_MASK
	var ph: float = 0.0
	for i: int in buf.size():
		var t: float = float(i) / rate
		var env: float = minf(1.0, t / 0.06) * clampf(1.0 - (t - gate_s) / LEAD_RELEASE_S, 0.0, 1.0)
		var vib: float = 12.0 * clampf((t - 0.15) / VIBRATO_FADE_S, 0.0, 1.0) * sin(TAU * 5.0 * t)
		ph += freq * (1.0 + vib * CENT_LINEAR) / rate
		if ph >= 1.0:
			ph -= 1.0
		var s: float = sin(TAU * ph) + 0.12 * sin(2.0 * TAU * ph)
		buf[i] = (s + noise[(off + i) & SynthDSP.NOISE_MASK] * 0.05) * env * 0.4
	return buf
