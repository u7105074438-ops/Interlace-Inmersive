# synth_dsp.gd — Primitivas de síntesis por código: osciladores, envolventes, filtros, ruido y WAV.
# PROPIETARIO DE: la tabla de ruido compartida (determinista; solo lectura tras warm_up()).
# ESCUCHA: nada.
class_name SynthDSP
extends RefCounted

## Todo el audio del juego nace aquí (§14.11: "debe sonar económico: es parte del chiste").
## Búferes mono PackedFloat32Array en [-1, 1]. Las funciones *_into SUMAN sobre un búfer existente
## (los Packed*Array se pasan por referencia). Funciones puras: seguras en hilos tras warm_up().
## Las constantes de este archivo son parámetros de diseño sonoro (como colores en _draw()),
## no ajustes de juego.

enum Wave { SINE, SQUARE, SAW, TRIANGLE }

const NOISE_SIZE := 65536
const NOISE_MASK := NOISE_SIZE - 1
const NOISE_SEED := 14091987
const CLICK_GUARD_S := 0.004
const MIDI_A4 := 69.0
const HZ_A4 := 440.0
const SEMITONES := 12.0
const CENTS_PER_OCTAVE := 1200.0
const PCM_MAX := 32767.0
const WAV_FMT_CHUNK := 16
const WAV_PCM := 1
const WAV_MONO := 1
const WAV_BITS := 16
const WAV_BYTES_PER_SAMPLE := 2
const WAV_RIFF_EXTRA := 36
const DENORMAL_GUARD := 1.0e-9
## Formantes F1/F2 (Hz) de vocales genéricas para el murmullo.
const VOWELS: Array[Vector2] = [
	Vector2(730, 1090), Vector2(270, 2290), Vector2(300, 870), Vector2(530, 1840),
	Vector2(570, 840), Vector2(440, 1020), Vector2(660, 1720),
]
const SYLLABLE_S := Vector2(0.07, 0.2)
const SYLLABLE_PAUSE_CHANCE := 0.18
const SYLLABLE_GAP_S := 0.04
const FORMANT_DAMPING := 0.28

static var _noise: PackedFloat32Array = PackedFloat32Array()


## Prepara la tabla de ruido. Llamar en el hilo principal antes de renderizar en hilos.
static func warm_up() -> void:
	if _noise.size() == NOISE_SIZE:
		return
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = NOISE_SEED
	var table: PackedFloat32Array = PackedFloat32Array()
	table.resize(NOISE_SIZE)
	for i: int in NOISE_SIZE:
		table[i] = rng.randf_range(-1.0, 1.0)
	_noise = table


static func noise_table() -> PackedFloat32Array:
	warm_up()
	return _noise


static func midi_hz(midi: float) -> float:
	return HZ_A4 * pow(2.0, (midi - MIDI_A4) / SEMITONES)


static func cents_ratio(cents: float) -> float:
	return pow(2.0, cents / CENTS_PER_OCTAVE)


static func silence(seconds: float, rate: int) -> PackedFloat32Array:
	var buf: PackedFloat32Array = PackedFloat32Array()
	buf.resize(maxi(1, int(seconds * rate)))
	return buf


## Suma un tono con barrido lineal f0→f1, ataque lineal y caída exponencial (tau 0 = sin caída).
## Osciladores ingenuos, sin antialiasing: el aliasing forma parte del sonido barato.
static func tone_into(buf: PackedFloat32Array, rate: int, start_s: float, dur_s: float,
		f0: float, f1: float, amp: float, wave: int, attack_s: float, tau_s: float) -> void:
	var start: int = int(start_s * rate)
	var n: int = mini(int(dur_s * rate), buf.size() - start)
	var k: float = exp(-1.0 / (tau_s * rate)) if tau_s > 0.0 else 1.0
	var att: float = maxf(1.0, attack_s * rate)
	var guard: float = maxf(1.0, CLICK_GUARD_S * rate)
	var env: float = amp
	var ph: float = 0.0
	var inc: float = f0 / rate
	var dinc: float = (f1 - f0) / (float(rate) * float(maxi(1, n)))
	for i: int in n:
		ph += inc
		inc += dinc
		if ph >= 1.0:
			ph -= floorf(ph)
		var v: float
		if wave == Wave.SAW:
			v = 2.0 * ph - 1.0
		elif wave == Wave.SQUARE:
			v = 1.0 if ph < 0.5 else -1.0
		elif wave == Wave.TRIANGLE:
			v = 1.0 - 4.0 * absf(ph - 0.5)
		else:
			v = sin(TAU * ph)
		buf[start + i] += v * env * minf(1.0, minf(float(i) / att, float(n - i) / guard))
		env *= k


## Suma una ráfaga de ruido filtrado (paso alto y paso bajo de un polo; 0 = sin filtro).
static func noise_into(buf: PackedFloat32Array, rate: int, start_s: float, dur_s: float, amp: float,
		attack_s: float, tau_s: float, hp_hz: float, lp_hz: float, noise_seed: int) -> void:
	var burst: PackedFloat32Array = silence(dur_s, rate)
	var table: PackedFloat32Array = noise_table()
	var offset: int = absi(noise_seed * 7919) & NOISE_MASK
	var k: float = exp(-1.0 / (tau_s * rate)) if tau_s > 0.0 else 1.0
	var att: float = maxf(1.0, attack_s * rate)
	var guard: float = maxf(1.0, CLICK_GUARD_S * rate)
	var env: float = 1.0
	var n: int = burst.size()
	for i: int in n:
		var edge: float = minf(1.0, minf(float(i) / att, float(n - i) / guard))
		burst[i] = table[(offset + i) & NOISE_MASK] * env * edge
		env *= k
	if hp_hz > 0.0:
		highpass(burst, rate, hp_hz)
	if lp_hz > 0.0:
		lowpass(burst, rate, lp_hz, 2)
	mix_into(buf, burst, int(start_s * rate), amp, false)


## Campana FM (portadora + moduladora con índice que decae): timbres, ding, vibráfono.
static func bell_into(buf: PackedFloat32Array, rate: int, start_s: float, dur_s: float, freq: float,
		amp: float, ratio: float, index: float, tau_s: float) -> void:
	var start: int = int(start_s * rate)
	var n: int = mini(int(dur_s * rate), buf.size() - start)
	var k: float = exp(-1.0 / (tau_s * rate))
	var ki: float = exp(-1.0 / (tau_s * 0.3 * rate))
	var guard: float = maxf(1.0, CLICK_GUARD_S * rate)
	var env: float = 1.0
	var idx: float = index
	var pc: float = 0.0
	var pm: float = 0.0
	for i: int in n:
		pc += freq / rate
		pm += freq * ratio / rate
		var edge: float = minf(1.0, minf(float(i) / guard, float(n - i) / guard))
		buf[start + i] += sin(TAU * pc + idx * sin(TAU * pm)) * amp * env * edge
		env *= k
		idx *= ki


## Cuerda pulsada Karplus-Strong (arpa, bajo pulsado).
static func pluck_into(buf: PackedFloat32Array, rate: int, start_s: float, dur_s: float, freq: float,
		amp: float, damping: float, noise_seed: int) -> void:
	var period: int = maxi(2, int(float(rate) / freq))
	var line: PackedFloat32Array = PackedFloat32Array()
	line.resize(period)
	var table: PackedFloat32Array = noise_table()
	var offset: int = absi(noise_seed * 104729) & NOISE_MASK
	var prev: float = 0.0
	for i: int in period:
		prev = prev + 0.5 * (table[(offset + i) & NOISE_MASK] - prev)
		line[i] = prev
	var start: int = int(start_s * rate)
	var n: int = mini(int(dur_s * rate), buf.size() - start)
	var guard: float = maxf(1.0, CLICK_GUARD_S * rate)
	for i: int in n:
		var j: int = i % period
		var nxt: float = line[(j + 1) % period]
		var out: float = line[j]
		line[j] = (out + nxt) * 0.5 * damping
		buf[start + i] += out * amp * minf(1.0, float(n - i) / guard)


## Murmullo ininteligible: sílabas con fuente glotal (sierra) y dos formantes de vocal (charla, radio).
static func babble_into(buf: PackedFloat32Array, rate: int, start_s: float, dur_s: float,
		pitch_hz: float, amp: float, noise_seed: int) -> void:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.seed = noise_seed
	var t: float = start_s
	while t < start_s + dur_s:
		var syl: float = rng.randf_range(SYLLABLE_S.x, SYLLABLE_S.y)
		if rng.randf() >= SYLLABLE_PAUSE_CHANCE:
			var vowel: Vector2 = VOWELS[rng.randi() % VOWELS.size()]
			var p0: float = pitch_hz * rng.randf_range(0.9, 1.15)
			syllable_into(buf, rate, t, syl, Vector2(p0, p0 * rng.randf_range(0.88, 1.05)), vowel, amp)
		t += syl + rng.randf_range(0.0, SYLLABLE_GAP_S)


## Una sílaba: barrido de tono (x→y) filtrado por los formantes F1/F2 de `vowel`.
static func syllable_into(buf: PackedFloat32Array, rate: int, start_s: float, dur_s: float,
		pitch: Vector2, vowel: Vector2, amp: float) -> void:
	var src: PackedFloat32Array = silence(dur_s, rate)
	tone_into(src, rate, 0.0, dur_s, pitch.x, pitch.y, 1.0, Wave.SAW, dur_s * 0.25, 0.0)
	var f1: PackedFloat32Array = src.duplicate()
	bandpass(f1, rate, vowel.x, FORMANT_DAMPING)
	bandpass(src, rate, vowel.y, FORMANT_DAMPING)
	var n: int = f1.size()
	for i: int in n:
		var fade: float = minf(1.0, float(n - i) / (float(n) * 0.35))
		f1[i] = (f1[i] + src[i] * 0.6) * fade
	mix_into(buf, f1, int(start_s * rate), amp, false)


## Coeficiente de un filtro de un polo para la frecuencia de corte dada.
static func one_pole_coef(rate: int, hz: float) -> float:
	return 1.0 - exp(-TAU * hz / float(rate))


## Paso bajo de un polo en el sitio; `passes` en cascada (2 = 12 dB/oct).
static func lowpass(buf: PackedFloat32Array, rate: int, hz: float, passes: int = 1) -> void:
	var a: float = one_pole_coef(rate, hz)
	for p: int in passes:
		var y: float = 0.0
		for i: int in buf.size():
			y += a * (buf[i] - y)
			buf[i] = y


## Paso alto de un polo en el sitio.
static func highpass(buf: PackedFloat32Array, rate: int, hz: float) -> void:
	var a: float = one_pole_coef(rate, hz)
	var low: float = 0.0
	for i: int in buf.size():
		low += a * (buf[i] - low)
		buf[i] = buf[i] - low


## Paso banda (filtro de estado variable de Chamberlin) en el sitio. q = amortiguación (0.1-2).
static func bandpass(buf: PackedFloat32Array, rate: int, hz: float, q: float) -> void:
	var f: float = 2.0 * sin(PI * minf(hz, float(rate) / 6.0) / float(rate))
	var low: float = 0.0
	var band: float = 0.0
	for i: int in buf.size():
		low += f * band
		var high: float = buf[i] - low - q * band
		band += f * high
		buf[i] = band


## Modulación de amplitud (trémolo o troceado si `square`).
static func amp_mod(buf: PackedFloat32Array, rate: int, hz: float, depth: float, square: bool) -> void:
	var ph: float = 0.0
	for i: int in buf.size():
		ph += hz / rate
		if ph >= 1.0:
			ph -= 1.0
		var m: float = (1.0 if ph < 0.5 else 0.0) if square else 0.5 + 0.5 * sin(TAU * ph)
		buf[i] *= 1.0 - depth + depth * m


## Eco con realimentación (hueco de escalera, radio).
static func echo(buf: PackedFloat32Array, rate: int, delay_s: float, feedback: float, wet: float) -> void:
	var d: int = maxi(1, int(delay_s * rate))
	var line: PackedFloat32Array = PackedFloat32Array()
	line.resize(d)
	for i: int in buf.size():
		var j: int = i % d
		var delayed: float = line[j]
		line[j] = buf[i] + delayed * feedback
		buf[i] += delayed * wet


## Saturación suave (aproximación racional de tanh). drive 1 = casi transparente.
static func soft_clip(buf: PackedFloat32Array, drive: float) -> void:
	for i: int in buf.size():
		var x: float = clampf(buf[i] * drive, -3.0, 3.0)
		buf[i] = x * (27.0 + x * x) / (27.0 + 9.0 * x * x)


static func peak(buf: PackedFloat32Array) -> float:
	var m: float = 0.0
	for i: int in buf.size():
		m = maxf(m, absf(buf[i]))
	return m


static func rms(buf: PackedFloat32Array, from: int, to: int) -> float:
	var acc: float = 0.0
	var a: int = clampi(from, 0, buf.size())
	var b: int = clampi(to, a, buf.size())
	for i: int in range(a, b):
		acc += buf[i] * buf[i]
	return sqrt(acc / maxf(1.0, float(b - a)))


static func scale(buf: PackedFloat32Array, gain: float) -> void:
	for i: int in buf.size():
		buf[i] *= gain


## Escala para que el pico valga `target`; devuelve la ganancia aplicada.
static func normalize(buf: PackedFloat32Array, target: float) -> float:
	var p: float = peak(buf)
	if p < DENORMAL_GUARD:
		return 1.0
	var g: float = target / p
	scale(buf, g)
	return g


## Suma src sobre dst desde `offset`; con `wrap_tail` la cola que sobra vuelve al principio (bucles).
static func mix_into(dst: PackedFloat32Array, src: PackedFloat32Array, offset: int, gain: float,
		wrap_tail: bool) -> void:
	var size: int = dst.size()
	if size == 0:
		return
	for i: int in src.size():
		var j: int = offset + i
		if j >= size:
			if not wrap_tail:
				return
			j %= size
		if j >= 0:
			dst[j] += src[i] * gain


## Convierte un búfer de longitud L + F en un bucle de longitud L fundiendo la cola F sobre el inicio.
static func loopify(buf: PackedFloat32Array, loop_len: int) -> PackedFloat32Array:
	var fade: int = buf.size() - loop_len
	var out: PackedFloat32Array = buf.slice(0, loop_len)
	for i: int in maxi(0, fade):
		var w: float = float(i) / float(fade)
		out[i] = out[i] * w + buf[loop_len + i] * (1.0 - w)
	return out


## Búfer flotante → PCM de 16 bits little-endian.
static func encode_pcm16(buf: PackedFloat32Array) -> PackedByteArray:
	var bytes: PackedByteArray = PackedByteArray()
	bytes.resize(buf.size() * WAV_BYTES_PER_SAMPLE)
	for i: int in buf.size():
		bytes.encode_s16(i * WAV_BYTES_PER_SAMPLE, int(clampf(buf[i], -1.0, 1.0) * PCM_MAX))
	return bytes


## AudioStreamWAV de 16 bits mono listo para un AudioStreamPlayer.
static func to_stream(buf: PackedFloat32Array, rate: int, loop: bool) -> AudioStreamWAV:
	var stream: AudioStreamWAV = AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = encode_pcm16(buf)
	if loop:
		stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
		stream.loop_begin = 0
		stream.loop_end = buf.size()
	return stream


## Escribe un WAV PCM mono de 16 bits (cabecera RIFF escrita a mano).
static func write_wav(path: String, buf: PackedFloat32Array, rate: int) -> Error:
	var pcm: PackedByteArray = encode_pcm16(buf)
	var f: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return FileAccess.get_open_error()
	f.store_buffer("RIFF".to_ascii_buffer())
	f.store_32(WAV_RIFF_EXTRA + pcm.size())
	f.store_buffer("WAVEfmt ".to_ascii_buffer())
	f.store_32(WAV_FMT_CHUNK)
	f.store_16(WAV_PCM)
	f.store_16(WAV_MONO)
	f.store_32(rate)
	f.store_32(rate * WAV_BYTES_PER_SAMPLE)
	f.store_16(WAV_BYTES_PER_SAMPLE)
	f.store_16(WAV_BITS)
	f.store_buffer("data".to_ascii_buffer())
	f.store_32(pcm.size())
	f.store_buffer(pcm)
	f.close()
	return OK
