# character_anim.gd — Catálogo de animaciones limitadas (§14.7) y tics visuales por arquetipo (§14.6).
# PROPIETARIO DE: nada (tablas de poses clave de solo lectura y funciones puras).
# ESCUCHA: nada.
class_name CharacterAnim
extends RefCounted

## Animación limitada: 8–12 fotogramas por ciclo con poses clave, sin interpolación. Quien anima
## (Player, NPC) avanza `pose.frame` a `fps(anim)` fotogramas por segundo y CharacterPainter
## dibuja la pose clave de ese fotograma. Las poses son datos de arte (como un sprite sheet).
## Parámetros de una pose (en píxeles a escala 1):
##   step (-1..1 fase de piernas × zancada), lift_l/lift_r (pie levantado), bob (vertical, - arriba),
##   lean (inclinación hacia delante), crouch/sit (0..1), hand_l/hand_r Vector3(delante, fuera,
##   arriba) respecto a la mano colgando, head_turn (-1..1), head_tilt (+ mira abajo), hunch,
##   squash (escala vertical), shake (temblor lateral), roll (giro del cuerpo, rad), expr, fx,
##   prop_l/prop_r (objeto en la mano), uses_hands (oculta el objeto transportado del escalón).

const DEFAULT_ANIM := "idle"
const DEFAULTS: Dictionary = {
	"step": 0.0, "lift_l": 0.0, "lift_r": 0.0, "bob": 0.0, "lean": 0.0, "crouch": 0.0,
	"sit": 0.0, "hand_l": Vector3.ZERO, "hand_r": Vector3.ZERO, "head_turn": 0.0,
	"head_tilt": 0.0, "hunch": 0.0, "squash": 1.0, "shake": 0.0, "roll": 0.0, "expr": "",
	"fx": "", "prop_l": "", "prop_r": "", "uses_hands": false,
}

## frames, fps (multiplicador de animacion.fps_base), loop, loop_from (reinicio del bucle),
## hold (una vez terminada se queda en el último fotograma), contacts (fotogramas de pisada).
const CATALOGUE: Dictionary = {
	"idle": {"frames": 8, "fps": 0.6, "loop": true},
	"walk": {"frames": 8, "fps": 1.0, "loop": true, "contacts": [2, 6]},
	"sprint": {"frames": 8, "fps": 1.5, "loop": true, "contacts": [2, 6]},
	"sneak": {"frames": 10, "fps": 0.8, "loop": true, "contacts": [2, 7]},
	"crouch": {"frames": 8, "fps": 0.7, "loop": true, "contacts": [2, 6]},
	"crouch_idle": {"frames": 8, "fps": 0.6, "loop": true},
	"sit": {"frames": 8, "fps": 0.6, "loop": true},
	"sit_type": {"frames": 8, "fps": 1.0, "loop": true},
	"drawer": {"frames": 10, "fps": 1.0, "loop": true, "loop_from": 5},
	"steal": {"frames": 8, "fps": 1.3, "loop": false, "hold": true},
	"hide": {"frames": 8, "fps": 0.7, "loop": true},
	"drag": {"frames": 12, "fps": 0.6, "loop": true, "contacts": [3, 9]},
	"phone": {"frames": 8, "fps": 0.8, "loop": true},
	"bribe": {"frames": 10, "fps": 1.0, "loop": false},
	"caught": {"frames": 8, "fps": 1.2, "loop": false, "hold": true},
	"clock_in": {"frames": 10, "fps": 1.0, "loop": false},
	"check_watch": {"frames": 10, "fps": 0.8, "loop": false},
	"yawn": {"frames": 12, "fps": 0.8, "loop": false},
	"chat": {"frames": 8, "fps": 0.8, "loop": true},
	"type_intense": {"frames": 8, "fps": 1.4, "loop": true},
	"phone_sneak": {"frames": 10, "fps": 0.7, "loop": true},
	"startle": {"frames": 8, "fps": 1.4, "loop": false},
	"suspicion": {"frames": 10, "fps": 0.7, "loop": true},
	"point": {"frames": 8, "fps": 1.0, "loop": false, "hold": true},
	"walk_report": {"frames": 8, "fps": 1.15, "loop": true, "contacts": [2, 6]},
}

## Ciclos de desplazamiento generados por fase (poses clave cuantizadas a `frames`).
const LOCOMOTION: Dictionary = {
	"walk": {"stride": 5.0, "swing": 5.0, "lift": 2.2, "bob": 1.3, "lean": 0.8},
	"sprint": {"stride": 8.5, "swing": 8.0, "lift": 4.0, "bob": 2.6, "lean": 4.5,
		"arms_up": 6.0, "hunch": 1.0},
	"sneak": {"stride": 4.0, "swing": 1.2, "lift": 3.2, "bob": 0.8, "lean": 2.5, "crouch": 0.35,
		"arms_up": 7.0, "arms_fwd": 4.0, "hunch": 2.0},
	"crouch": {"stride": 3.0, "swing": 1.0, "lift": 1.5, "bob": 0.6, "lean": 1.5, "crouch": 1.0,
		"arms_up": 3.0, "arms_fwd": 5.0},
	"drag": {"stride": 3.0, "swing": 0.0, "lift": 1.5, "bob": 1.0, "lean": -3.5, "crouch": 0.25,
		"arms_up": 3.0, "arms_fwd": -9.0, "expr": "strain", "fx": "sweat", "uses_hands": true},
	"walk_report": {"stride": 6.0, "swing": 4.0, "lift": 2.4, "bob": 1.2, "lean": 2.5,
		"expr": "angry"},
}

## Poses clave: [fotogramas que se mantiene, cambios sobre DEFAULTS + BASE de la animación].
const BASES: Dictionary = {
	"crouch_idle": {"crouch": 1.0, "hand_l": Vector3(4, 1, 4), "hand_r": Vector3(4, 1, 4)},
	"sit": {"sit": 1.0, "hand_l": Vector3(6, -2, 7), "hand_r": Vector3(6, -2, 7)},
	"sit_type": {"sit": 1.0, "head_tilt": 0.25, "uses_hands": true,
		"hand_l": Vector3(8, -3, 9), "hand_r": Vector3(8, -3, 9)},
	"type_intense": {"sit": 1.0, "head_tilt": 0.3, "lean": 3.0, "expr": "focus",
		"uses_hands": true, "hand_l": Vector3(9, -3, 9), "hand_r": Vector3(9, -3, 9)},
	"drawer": {"uses_hands": true},
	"steal": {"uses_hands": true, "hunch": 3.0},
	"hide": {"crouch": 1.0, "hunch": 3.0, "head_tilt": 0.3, "expr": "worried",
		"hand_l": Vector3(6, -2, 6), "hand_r": Vector3(6, -2, 6), "uses_hands": true},
	"phone": {"head_tilt": 0.35, "expr": "focus", "prop_r": "phone", "fx": "phone_glow",
		"hand_l": Vector3(4, -4, 10), "uses_hands": true},
	"bribe": {"uses_hands": true},
	"caught": {"expr": "surprised", "uses_hands": true},
	"clock_in": {"prop_r": "card", "uses_hands": true},
	"check_watch": {"prop_l": "watch", "uses_hands": true},
	"yawn": {"uses_hands": true},
	"chat": {"uses_hands": true},
	"phone_sneak": {"prop_r": "phone", "hand_r": Vector3(4, -4, 5), "uses_hands": true},
	"startle": {"uses_hands": true},
	"suspicion": {"expr": "suspicious", "fx": "question", "hand_r": Vector3(4, -7, 17),
		"uses_hands": true},
	"point": {"uses_hands": true},
}

const KEYS: Dictionary = {
	"idle": [[2, {}], [1, {"bob": -0.5}], [2, {"bob": -1.0}], [1, {"bob": -0.5}], [1, {}],
		[1, {"expr": "blink"}]],
	"crouch_idle": [[3, {}], [2, {"bob": -0.5}], [2, {}], [1, {"expr": "blink"}]],
	"sit": [[3, {}], [2, {"bob": -0.5}], [2, {}], [1, {"expr": "blink"}]],
	"sit_type": [[1, {"hand_l": Vector3(8, -3, 11)}], [1, {}], [1, {"hand_r": Vector3(8, -3, 11)}],
		[1, {}], [1, {"hand_l": Vector3(8, -3, 11)}], [1, {"hand_r": Vector3(8, -3, 11)}],
		[1, {"expr": "blink"}], [1, {"hand_r": Vector3(8, -3, 11)}]],
	"type_intense": [[1, {"hand_l": Vector3(9, -3, 12)}], [1, {"hand_r": Vector3(9, -3, 12)}],
		[1, {"hand_l": Vector3(9, -3, 12), "bob": -0.5}], [1, {"hand_r": Vector3(9, -3, 12)}],
		[1, {"hand_l": Vector3(9, -3, 12)}], [1, {"hand_r": Vector3(9, -3, 12), "bob": -0.5}],
		[1, {"hand_l": Vector3(9, -3, 12)}], [1, {"hand_r": Vector3(9, -3, 12)}]],
	"drawer": [[1, {"lean": 2.0, "hand_r": Vector3(4, 0, 4)}],
		[1, {"lean": 4.0, "crouch": 0.2, "hand_r": Vector3(9, 0, 3)}],
		[1, {"lean": 5.0, "crouch": 0.3, "hand_r": Vector3(12, -1, 2)}],
		[1, {"lean": 3.0, "crouch": 0.3, "hand_r": Vector3(7, -1, 2)}],
		[1, {"lean": 4.0, "crouch": 0.35, "head_tilt": 0.4, "hand_r": Vector3(8, -1, 2),
			"hand_l": Vector3(8, 1, 3)}],
		[1, {"lean": 4.0, "crouch": 0.35, "head_tilt": 0.45, "hand_r": Vector3(11, -2, 3),
			"hand_l": Vector3(8, 1, 2)}],
		[1, {"lean": 4.0, "crouch": 0.35, "head_tilt": 0.45, "hand_r": Vector3(9, -1, 2),
			"hand_l": Vector3(11, 2, 3), "head_turn": 0.15}],
		[1, {"lean": 4.0, "crouch": 0.35, "head_tilt": 0.45, "hand_r": Vector3(11, -3, 2),
			"hand_l": Vector3(9, 1, 2), "prop_r": "document"}],
		[1, {"lean": 4.0, "crouch": 0.35, "head_tilt": 0.45, "hand_r": Vector3(10, -1, 3),
			"hand_l": Vector3(11, 2, 2), "head_turn": -0.15}],
		[1, {"lean": 4.0, "crouch": 0.35, "head_tilt": 0.45, "hand_r": Vector3(9, -2, 2),
			"hand_l": Vector3(9, 1, 3), "expr": "blink"}]],
	"steal": [[1, {"lean": 3.0, "hand_r": Vector3(10, 0, 4)}],
		[1, {"lean": 5.0, "hand_r": Vector3(13, 0, 3)}],
		[1, {"lean": 4.0, "hand_r": Vector3(11, 0, 4), "prop_r": "loot"}],
		[1, {"lean": 2.0, "hand_r": Vector3(3, 2, 1), "prop_r": "loot", "expr": "guilty"}],
		[1, {"lean": 1.0, "hand_r": Vector3(-1, 3, -2), "hunch": 4.0, "expr": "guilty"}],
		[1, {"hand_r": Vector3(-1, 3, -2), "hunch": 4.0, "head_turn": -0.9, "expr": "guilty"}],
		[1, {"hand_r": Vector3(-1, 3, -2), "hunch": 4.0, "head_turn": 0.9, "expr": "guilty"}],
		[1, {"hand_r": Vector3(-1, 3, -2), "hunch": 4.0, "expr": "guilty", "fx": "sweat"}]],
	"hide": [[2, {}], [1, {"shake": 0.6}], [2, {"bob": 0.5}], [1, {"shake": -0.6}], [2, {}]],
	"phone": [[2, {"hand_r": Vector3(5, -4, 12)}], [1, {"hand_r": Vector3(5, -4, 13)}],
		[2, {"hand_r": Vector3(5, -4, 12)}], [1, {"hand_r": Vector3(5, -4, 13)}],
		[1, {"hand_r": Vector3(5, -4, 12), "expr": "blink"}], [1, {"hand_r": Vector3(5, -4, 13)}]],
	"bribe": [[1, {"hand_r": Vector3(4, 0, 5), "prop_r": "envelope"}],
		[1, {"hand_r": Vector3(8, -1, 7), "prop_r": "envelope"}],
		[1, {"hand_r": Vector3(12, -2, 8), "prop_r": "envelope", "lean": 2.0}],
		[1, {"hand_r": Vector3(14, -3, 8), "prop_r": "envelope", "lean": 3.0, "fx": "money"}],
		[1, {"hand_r": Vector3(14, -3, 10), "lean": 3.0, "fx": "money", "expr": "sly"}],
		[1, {"hand_r": Vector3(14, -3, 6), "lean": 3.0, "expr": "sly"}],
		[1, {"hand_r": Vector3(14, -3, 10), "lean": 3.0, "expr": "sly"}],
		[1, {"hand_r": Vector3(14, -3, 6), "lean": 3.0, "expr": "sly"}],
		[1, {"hand_r": Vector3(10, -2, 7), "lean": 1.0, "expr": "sly"}],
		[1, {"hand_r": Vector3(4, 0, 4), "expr": "sly"}]],
	"caught": [[1, {"squash": 0.92, "bob": 1.0}],
		[1, {"bob": -5.0, "squash": 1.06, "hand_l": Vector3(3, 5, 14), "hand_r": Vector3(3, 5, 14),
			"fx": "exclaim"}],
		[1, {"bob": -3.0, "hand_l": Vector3(2, 6, 16), "hand_r": Vector3(2, 6, 16), "fx": "exclaim"}],
		[1, {"bob": -1.0, "hand_l": Vector3(2, 5, 13), "hand_r": Vector3(2, 5, 13), "fx": "exclaim",
			"shake": 0.8}],
		[1, {"bob": -1.0, "hand_l": Vector3(2, 5, 13), "hand_r": Vector3(2, 5, 13), "fx": "exclaim",
			"shake": -0.8}],
		[3, {"bob": -1.0, "hand_l": Vector3(2, 5, 13), "hand_r": Vector3(2, 5, 13), "fx": "exclaim",
			"expr": "caught"}]],
	"clock_in": [[1, {"hand_r": Vector3(3, 0, 6)}], [1, {"hand_r": Vector3(7, -1, 9)}],
		[1, {"hand_r": Vector3(11, -2, 11)}], [1, {"hand_r": Vector3(13, -2, 12)}],
		[1, {"hand_r": Vector3(13, -2, 12)}], [1, {"hand_r": Vector3(13, -2, 12), "fx": "beep"}],
		[1, {"hand_r": Vector3(13, -2, 12), "fx": "beep"}], [1, {"hand_r": Vector3(9, -1, 9)}],
		[1, {"hand_r": Vector3(5, 0, 6)}], [1, {"prop_r": ""}]],
	"check_watch": [[1, {"hand_l": Vector3(2, 0, 4)}], [1, {"hand_l": Vector3(4, -3, 9)}],
		[4, {"hand_l": Vector3(5, -5, 12), "head_tilt": 0.35}],
		[1, {"hand_l": Vector3(5, -5, 12), "head_tilt": 0.35, "expr": "blink"}],
		[1, {"hand_l": Vector3(5, -5, 12), "head_tilt": 0.35, "expr": "bored"}],
		[1, {"hand_l": Vector3(4, -3, 8)}], [1, {"prop_l": ""}]],
	"yawn": [[2, {}], [1, {"hand_l": Vector3(2, 3, 12), "hand_r": Vector3(2, 3, 12),
			"head_tilt": -0.1, "expr": "yawn"}],
		[2, {"hand_l": Vector3(0, 5, 26), "hand_r": Vector3(0, 5, 26), "head_tilt": -0.3,
			"expr": "yawn", "squash": 1.04}],
		[3, {"hand_l": Vector3(0, 5, 27), "hand_r": Vector3(0, 5, 27), "head_tilt": -0.3,
			"expr": "yawn", "squash": 1.04, "fx": "zzz"}],
		[1, {"hand_l": Vector3(2, 4, 14), "hand_r": Vector3(2, 4, 14), "expr": "bored"}],
		[3, {"expr": "bored"}]],
	"chat": [[1, {"hand_r": Vector3(6, 2, 8), "expr": "talk"}], [1, {"hand_r": Vector3(7, 3, 10)}],
		[1, {"hand_r": Vector3(6, 2, 8), "expr": "talk"}], [1, {}],
		[1, {"hand_l": Vector3(6, 2, 8), "expr": "talk"}], [1, {"hand_l": Vector3(7, 3, 11)}],
		[1, {"hand_l": Vector3(6, 2, 8), "expr": "talk"}], [1, {"bob": -0.5}]],
	"phone_sneak": [[3, {"head_tilt": 0.5}], [1, {"head_tilt": 0.5, "expr": "blink"}],
		[3, {"head_tilt": 0.5}], [1, {"head_turn": -0.6, "expr": "guilty"}],
		[1, {"head_turn": 0.6, "expr": "guilty"}], [1, {"head_tilt": 0.5}]],
	"startle": [[1, {"squash": 0.9}],
		[1, {"bob": -7.0, "hand_l": Vector3(2, 6, 16), "hand_r": Vector3(2, 6, 16),
			"fx": "exclaim", "expr": "surprised"}],
		[1, {"bob": -4.0, "hand_l": Vector3(2, 6, 15), "hand_r": Vector3(2, 6, 15),
			"fx": "exclaim", "expr": "surprised"}],
		[1, {"bob": -1.0, "lean": -3.0, "hand_l": Vector3(4, 4, 10), "hand_r": Vector3(4, 4, 10),
			"fx": "exclaim", "expr": "surprised"}],
		[2, {"lean": -2.0, "hand_l": Vector3(3, 2, 6), "hand_r": Vector3(3, 2, 6),
			"expr": "surprised"}],
		[2, {"lean": -1.0}]],
	"suspicion": [[3, {"head_turn": -0.3}], [2, {"head_turn": 0.0, "head_tilt": 0.1}],
		[3, {"head_turn": 0.3}], [2, {"head_turn": 0.0, "expr": "blink"}]],
	"point": [[1, {"hand_r": Vector3(5, 1, 8)}], [1, {"hand_r": Vector3(12, 1, 12)}],
		[1, {"hand_r": Vector3(18, 0, 13), "expr": "angry", "fx": "exclaim", "lean": 2.0}],
		[1, {"hand_r": Vector3(19, 0, 13), "expr": "angry", "fx": "exclaim", "lean": 2.0}],
		[1, {"hand_r": Vector3(19, 0, 14), "expr": "angry", "fx": "exclaim", "lean": 2.0}],
		[3, {"hand_r": Vector3(19, 0, 13), "expr": "angry", "fx": "exclaim", "lean": 2.0}]],
}

## Tics visuales (§14.6): id de archetypes.json → se aplica sobre estas animaciones base.
const TIC_ANIMS: Array[String] = ["idle", "chat", "walk", "walk_report", "sit", "crouch_idle"]
const TIC_CYCLE := 12
const HEAD_TURN_MAX := 1.2
const TICS: Array[String] = [
	"rushes_to_superiors_offices", "checks_sides_before_talking", "rubs_fingers",
	"straightens_tie", "headphones_never_turns_head", "leans_toward_interlocutor",
	"leans_on_walls", "stares_at_anomalies", "looks_around_lost", "slow_wide_gaze_sweep",
	"steps_back_half_pace", "static_frontal_stance",
]


static func has_anim(anim: String) -> bool:
	return CATALOGUE.has(anim)


static func info(anim: String) -> Dictionary:
	return CATALOGUE.get(anim, CATALOGUE[DEFAULT_ANIM])


static func frame_count(anim: String) -> int:
	return int(info(anim)["frames"])


static func loops(anim: String) -> bool:
	return bool(info(anim)["loop"])


static func is_locomotion(anim: String) -> bool:
	return LOCOMOTION.has(anim)


## Fotogramas en los que un pie toca el suelo (pisadas audibles).
static func contact_frames(anim: String) -> Array:
	return info(anim).get("contacts", [])


## Siguiente fotograma según loop / loop_from / hold. Devuelve -1 si la animación terminó.
static func next_frame(anim: String, frame: int) -> int:
	var data: Dictionary = info(anim)
	var n: int = int(data["frames"])
	if frame + 1 < n:
		return frame + 1
	if bool(data["loop"]):
		return int(data.get("loop_from", 0))
	if bool(data.get("hold", false)):
		return n - 1
	return -1


## Parámetros completos de la pose clave `frame` de `anim` para un personaje de escalón `tier`.
static func params(anim: String, frame: int, tier: int) -> Dictionary:
	var out: Dictionary = DEFAULTS.duplicate()
	if LOCOMOTION.has(anim):
		_locomotion(out, anim, frame, tier)
		return out
	var key_anim: String = anim if KEYS.has(anim) else DEFAULT_ANIM
	out.merge(BASES.get(key_anim, {}), true)
	out.merge(_key_frame(key_anim, frame), true)
	return out


static func _key_frame(anim: String, frame: int) -> Dictionary:
	var keys: Array = KEYS[anim]
	var remaining: int = posmod(frame, frame_count(anim))
	for entry: Array in keys:
		if remaining < int(entry[0]):
			return entry[1]
		remaining -= int(entry[0])
	return (keys[keys.size() - 1] as Array)[1]


static func _locomotion(out: Dictionary, anim: String, frame: int, tier: int) -> void:
	var spec: Dictionary = LOCOMOTION[anim]
	var shape: Dictionary = CharacterStyle.TIER_SHAPES[clampi(tier, 1, 8)]
	var phase: float = TAU * float(posmod(frame, frame_count(anim))) / float(frame_count(anim))
	var s: float = sin(phase)
	var c: float = cos(phase)
	var swing: float = float(spec["swing"]) * float(shape["swing"]) * s
	var up: float = float(spec.get("arms_up", 0.0))
	var fwd: float = float(spec.get("arms_fwd", 0.0))
	out["step"] = s * float(spec["stride"]) * float(shape["stride"])
	out["lift_l"] = maxf(0.0, c) * float(spec["lift"])
	out["lift_r"] = maxf(0.0, -c) * float(spec["lift"])
	out["bob"] = -(1.0 - absf(s)) * float(spec["bob"])
	out["lean"] = float(spec["lean"])
	out["crouch"] = float(spec.get("crouch", 0.0))
	out["hunch"] = float(spec.get("hunch", 0.0))
	out["hand_l"] = Vector3(fwd - swing, 0.0, up)
	out["hand_r"] = Vector3(fwd + swing, 0.0, up)
	out["expr"] = str(spec.get("expr", ""))
	out["fx"] = str(spec.get("fx", "")) if posmod(frame, 4) < 2 else ""
	out["uses_hands"] = bool(spec.get("uses_hands", false))


## Aplica el tic del arquetipo sobre los parámetros (solo en las animaciones de TIC_ANIMS).
## La mirada dirigida (stares_at_anomalies) la resuelve CharacterRig con `pose.look`.
static func apply_tic(p: Dictionary, anim: String, tic: String, tic_frame: int) -> void:
	if tic.is_empty() or not TIC_ANIMS.has(anim):
		return
	var f: int = posmod(tic_frame, TIC_CYCLE)
	var walking: bool = is_locomotion(anim)
	match tic:
		"leans_toward_interlocutor":
			p["lean"] = float(p["lean"]) + 5.0
			if not walking:
				p["hand_r"] = Vector3(3, -6, 20)
				p["expr"] = "talk" if f % 4 < 2 else "sly"
		"checks_sides_before_talking":
			p["head_turn"] = [-1.0, -1.0, 0.0, 1.0, 1.0, 0.0][f % 6]
		"headphones_never_turns_head":
			p["head_turn"] = 0.0
			p["expr"] = "bored" if p["expr"] == "" else p["expr"]
		"stares_at_anomalies":
			p["expr"] = "stare"
		_:
			_apply_body_tic(p, tic, f, walking)


static func _apply_body_tic(p: Dictionary, tic: String, f: int, walking: bool) -> void:
	match tic:
		"leans_on_walls":
			if not walking:
				p["roll"] = 0.16
				p["hand_l"] = Vector3(6, -6, 9)
				p["hand_r"] = Vector3(6, -6, 8)
				p["expr"] = "bored"
		"slow_wide_gaze_sweep":
			p["head_turn"] = sin(TAU * float(f) / float(TIC_CYCLE))
			p["hand_l"] = Vector3(-5, -2, 4)
			p["hand_r"] = Vector3(-5, -2, 4)
			p["expr"] = "stare"
		"steps_back_half_pace":
			p["lean"] = float(p["lean"]) - 3.0
			if not walking:
				p["hand_l"] = Vector3(6, 1, 10)
				p["hand_r"] = Vector3(6, 1, 10)
				p["expr"] = "worried"
		_:
			_apply_gesture_tic(p, tic, f, walking)


static func _apply_gesture_tic(p: Dictionary, tic: String, f: int, walking: bool) -> void:
	match tic:
		"rushes_to_superiors_offices":
			p["lean"] = float(p["lean"]) + 3.0
			p["head_tilt"] = -0.15
		"static_frontal_stance":
			p["bob"] = 0.0
			p["head_turn"] = 0.0
			p["hand_l"] = Vector3(0, 1, 0) if not walking else p["hand_l"]
			p["hand_r"] = Vector3(0, 1, 0) if not walking else p["hand_r"]
			p["expr"] = "firm"
		"rubs_fingers":
			if not walking:
				var rub: float = 1.0 if f % 2 == 0 else -1.0
				p["hand_l"] = Vector3(7, -6 + rub, 10)
				p["hand_r"] = Vector3(7, -6 - rub, 10)
				p["expr"] = "sly"
		"straightens_tie":
			if not walking and f < TIC_CYCLE / 2:
				p["hand_r"] = Vector3(4, -8, 19 + (f % 2))
				p["expr"] = "proud"
		"looks_around_lost":
			p["head_turn"] = [-0.8, -0.8, 0.0, 0.8, 0.8, 0.4][f % 6]
			if not walking and f >= TIC_CYCLE / 2:
				p["hand_l"] = Vector3(2, -2, 30)
				p["fx"] = "question"
