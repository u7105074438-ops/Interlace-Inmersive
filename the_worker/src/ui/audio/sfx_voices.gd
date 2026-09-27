# sfx_voices.gd — Reservas de voces de efectos (posicionales con paneo y globales) con robo por prioridad.
# PROPIETARIO DE: los AudioStreamPlayer(2D) de efectos y la prioridad/instante de lo que suena en cada uno.
# ESCUCHA: nada.
class_name SfxVoices
extends RefCounted

## Una voz nueva usa primero una voz libre; si no hay, roba la de menor prioridad (importancia del
## efecto) y, a igualdad, la más antigua, pero nunca una de prioridad mayor que la suya: los pasos
## de NPC no cortan una radio, un cristal roto ni una cerradura forzándose. Si no hay voz, el efecto
## no suena (su subtítulo sí se publica: lo decide AudioDirector).

const NO_VOICE := -1

var _pos: Array[AudioStreamPlayer2D] = []
var _glob: Array[AudioStreamPlayer] = []
var _pos_meta: Array[Vector2] = []
var _glob_meta: Array[Vector2] = []


## Crea `positional` voces 2D y `global` voces sin posición como hijas de `host`.
func build(host: Node, bus: String, positional: int, global: int, max_distance: float,
		attenuation: float) -> void:
	for i: int in global:
		var g: AudioStreamPlayer = AudioStreamPlayer.new()
		g.name = "SfxGlobal%d" % i
		g.bus = bus
		host.add_child(g)
		_glob.append(g)
		_glob_meta.append(Vector2.ZERO)
	for i: int in positional:
		var p: AudioStreamPlayer2D = AudioStreamPlayer2D.new()
		p.name = "SfxPositional%d" % i
		p.bus = bus
		p.max_distance = max_distance
		p.attenuation = attenuation
		host.add_child(p)
		_pos.append(p)
		_pos_meta.append(Vector2.ZERO)


## Reproduce `stream`; con posición finita suena en estéreo según la dirección. Devuelve si sonó.
func play(stream: AudioStream, position: Vector2, volume_db: float, pitch: float, priority: int,
		now: float) -> bool:
	if position.is_finite():
		var busy: Array[bool] = []
		for p: AudioStreamPlayer2D in _pos:
			busy.append(p.playing)
		var i: int = pick(busy, _pos_meta, priority)
		if i == NO_VOICE:
			return false
		_pos[i].stop()
		_pos[i].global_position = position
		_start(_pos[i], stream, volume_db, pitch)
		_pos_meta[i] = Vector2(priority, now)
		return true
	var busy_g: Array[bool] = []
	for g: AudioStreamPlayer in _glob:
		busy_g.append(g.playing)
	var j: int = pick(busy_g, _glob_meta, priority)
	if j == NO_VOICE:
		return false
	_glob[j].stop()
	_start(_glob[j], stream, volume_db, pitch)
	_glob_meta[j] = Vector2(priority, now)
	return true


func stop_all() -> void:
	for p: AudioStreamPlayer2D in _pos:
		p.stop()
	for g: AudioStreamPlayer in _glob:
		g.stop()


## Índice de la voz a usar (NO_VOICE si todas suenan con más prioridad). meta[i] = (prioridad, inicio).
static func pick(busy: Array[bool], meta: Array[Vector2], priority: int) -> int:
	var best: int = NO_VOICE
	for i: int in busy.size():
		if not busy[i]:
			return i
		var m: Vector2 = meta[i]
		if m.x > float(priority):
			continue
		if best == NO_VOICE or m.x < meta[best].x or (m.x == meta[best].x and m.y < meta[best].y):
			best = i
	return best


func _start(player: Node, stream: AudioStream, volume_db: float, pitch: float) -> void:
	player.set("stream", stream)
	player.set("volume_db", volume_db)
	player.set("pitch_scale", pitch)
	player.call("play")
