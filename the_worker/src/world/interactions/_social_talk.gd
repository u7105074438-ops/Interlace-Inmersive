# _social_talk.gd — Conversación del módulo social: réplicas según el trato por escalón (§6.4) y el registro, charla (afecto, número, pistas de rutina, secretos de Old Ray §8.3), indicaciones y agenda, regalar un mérito (George Penn §8.3).
# PROPIETARIO DE: nada (estático; marcas por jornada en PlayerState "social.*", el registro en NPCDirector).
# ESCUCHA: nada.
class_name SocialTalk
extends RefCounted

## RÉPLICAS (§6.4: el trato emerge del escalón del jugador; aquí se elige la frase, no el efecto):
##  1. escalón >= social.lineas.escalon_sin_verdad → TOP (adulación: nadie te dice la verdad; sin
##     pistas, sin secretos, sin indicaciones fiables).
##  2. afecto <= afecto_hostil → HOSTILE · temor >= temor_alto → AFRAID.
##  3. escalón_ignorado (1) ante un superior → T1 (te ignoran, te mandan a por café).
##  4. escalón 7 → T7 (adulación de frente) · 6 → T6 (silencio y temor) · 5 → T5 (trato formal) ·
##     4 → T4_PEER ante los de abajo (antiguos iguales que adulan) / T4_BOSS ante los de arriba
##     (mobiliario).
##  5. afecto >= afecto_amistoso → WARM (te llaman por tu nombre) · resto → T2 o la del arquetipo.
##  Variante estable por personaje y jornada (hash), clave "SOCIAL_LINE_<CUBO>_<n>".
## CHARLA (una por personaje y jornada, social.minutos_charla): afecto según el cubo (ignorado o
## hostil gana menos), el número de móvil si el afecto llega a movil.afecto_minimo_contacto (fuente
## "proximity"), una pista de su agenda (siguiente tramo; al cuaderno) y, con un confidente de
## social.confidentes con afecto suficiente, un secreto del edificio por jornada (al cuaderno).
## Desde charla.escalon_favores_ofrecidos, un inferior te ofrece un favor sin pedirlo (+deuda).

## Cubo de trato → variantes (claves SOCIAL_LINE_<CUBO>_<n>).
const BUCKETS: Dictionary = {
	"top": 3, "hostile": 2, "afraid": 2, "t1": 3, "t7": 2, "t6": 2, "t5": 2, "t4_peer": 2,
	"t4_boss": 2, "warm": 2, "t2": 2,
}
const LINE_FORMAT := "SOCIAL_LINE_%s_%d"
const ARCH_FORMAT := "SOCIAL_LINE_ARCH_%s"
const CHAT_KIND := "chat"
const CREDIT_KIND := "credit"
const SECRET_KIND := "secret"
const SECRET_COUNTER := "secret_index."
const CONTACT_SOURCE := "proximity"
const FAVOUR_CREDIT := "credit_given"
const REPUTATION_REASON := "credit_given"
const TOPIC_DESK := "desk"
const TOPIC_AURORA := "aurora"
const TOPIC_DAY := "day"
const TOPIC_PERSON := "person:"
const TIER_FOUR := 4
const TIER_FIVE := 5
const TIER_SIX := 6
const TIER_SEVEN := 7
const MINUTES_PER_HOUR := 60


# ─── Réplicas por escalón y registro ──────────────────────────

## Cubo de trato (ver cabecera).
static func bucket(npc: NPCRuntime) -> String:
	var tier: int = PlayerState.get_tier()
	if tier >= SocialKit.bi("lineas.escalon_sin_verdad"):
		return "top"
	if int(npc.ledger.get("affection", 0)) <= SocialKit.bi("lineas.afecto_hostil"):
		return "hostile"
	if int(npc.ledger.get("fear", 0)) >= SocialKit.bi("lineas.temor_alto"):
		return "afraid"
	if tier <= SocialKit.bi("lineas.escalon_ignorado") and npc.tier > tier:
		return "t1"
	match tier:
		TIER_SEVEN:
			return "t7"
		TIER_SIX:
			return "t6"
		TIER_FIVE:
			return "t5"
		TIER_FOUR:
			if npc.tier != tier:
				return "t4_peer" if npc.tier < tier else "t4_boss"
	if int(npc.ledger.get("affection", 0)) >= SocialKit.bi("lineas.afecto_amistoso"):
		return "warm"
	return "t2"


## Réplica de saludo: [clave, args].
static func greeting(npc: NPCRuntime) -> Array:
	var cube: String = bucket(npc)
	var variant: int = _variant(npc.id, cube, int(BUCKETS[cube]))
	if cube == "t2" and variant == 1 and not npc.archetype.is_empty():
		return [ARCH_FORMAT % npc.archetype.to_upper(), []]
	return [LINE_FORMAT % [cube.to_upper(), variant], [PlayerState.get_player_name()]]


static func is_top(npc: NPCRuntime) -> bool:
	return bucket(npc) == "top"


## Te ignoran (escalón 1 ante un superior): ni pistas ni indicaciones.
static func ignores_you(npc: NPCRuntime) -> bool:
	return bucket(npc) == "t1"


static func _variant(npc_id: String, salt: String, count: int) -> int:
	return absi(hash([npc_id, salt, GameClock.get_day(), GameClock.get_run_seed()])) % maxi(count, 1) + 1


# ─── Charla ───────────────────────────────────────────────────

static func can_chat(npc_id: String) -> String:
	return "SOCIAL_REASON_CHATTED" if SocialKit.done_today(CHAT_KIND, npc_id) else ""


static func chat(npc_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null or not can_chat(npc_id).is_empty():
		return SocialKit.refusal("SOCIAL_LINE_BUSY")
	var hello: Array = greeting(npc)
	var res: Dictionary = SocialKit.result(true, str(hello[0]), hello[1] as Array)
	SocialKit.mark(CHAT_KIND, npc_id)
	NPCDirector.add_affection(npc_id, _affection_gain(npc))
	SocialKit.spend_minutes(SocialKit.bi("minutos_charla"))
	_offer_favour(npc, res)
	_maybe_number(npc, res)
	_share_secret(npc, res)
	if not _share_routine(npc, res) and str(res.get("toast_key", "")).is_empty():
		SocialKit.add_toast(res, "SOCIAL_TOAST_CHAT", [npc.name])
	res["sfx"] = SocialKit.SFX_CHAT
	return res


static func _affection_gain(npc: NPCRuntime) -> int:
	match bucket(npc):
		"t1":
			return SocialKit.bi("charla.afecto_ignorado")
		"hostile":
			return SocialKit.bi("charla.afecto_hostil")
	return SocialKit.bi("charla.afecto")


## §6.4 escalón 6: favores ofrecidos sin solicitarlos (un inferior queda en deuda contigo).
static func _offer_favour(npc: NPCRuntime, res: Dictionary) -> void:
	if PlayerState.get_tier() < SocialKit.bi("charla.escalon_favores_ofrecidos") or npc.tier >= PlayerState.get_tier():
		return
	NPCDirector.add_debt(npc.id, SocialKit.bi("charla.deuda_ofrecida"))
	SocialKit.add_line(res, "SOCIAL_LINE_OFFERS_FAVOUR")


## Número de móvil por trato (fuente "proximity", la de los compañeros).
static func _maybe_number(npc: NPCRuntime, res: Dictionary) -> void:
	if PlayerState.has_contact(npc.id) or NPCDirector.get_affection(npc.id) < Database.get_balance_int("movil.afecto_minimo_contacto"):
		return
	if PlayerState.add_contact(npc.id, CONTACT_SOURCE):
		SocialKit.add_toast(res, "SOCIAL_TOAST_NUMBER", [npc.name], ToastStack.KIND_GOOD)


## Old Ray (§8.3): con su respeto, un secreto del edificio por jornada, en orden.
static func _share_secret(npc: NPCRuntime, res: Dictionary) -> void:
	var spec: Dictionary = SocialKit.bdict("confidentes").get(npc.id, {})
	var secrets: Array = spec.get("secretos", [])
	if secrets.is_empty() or is_top(npc) or NPCDirector.get_affection(npc.id) < int(spec.get("afecto_minimo", 0)):
		return
	if SocialKit.done_today(SECRET_KIND, npc.id):
		return
	var index: int = SocialKit.counter(SECRET_COUNTER + npc.id)
	if index >= secrets.size():
		return
	var key: String = str(secrets[index])
	SocialKit.set_counter(SECRET_COUNTER + npc.id, index + 1)
	SocialKit.mark(SECRET_KIND, npc.id)
	SocialKit.add_line(res, key)
	SocialKit.note(SocialKit.NOTE_PERSONNEL, "SOCIAL_NOTE_SECRET", [npc.name, TranslationServer.translate(key)])
	SocialKit.add_toast(res, "SOCIAL_TOAST_SECRET", [npc.name], ToastStack.KIND_GOOD)


## Pista de rutina: el siguiente tramo de su agenda (sala y hora), al cuaderno. false si no hay.
static func _share_routine(npc: NPCRuntime, res: Dictionary) -> bool:
	if is_top(npc) or ignores_you(npc):
		return false
	var next: Dictionary = next_plan_entry(npc.id)
	if next.is_empty():
		return false
	var place: String = SocialKit.place_text(str(next["room"]))
	var at: String = _clock_text(int(next["start"]))
	SocialKit.add_line(res, "SOCIAL_HINT_ROUTINE", [place, at])
	SocialKit.note(SocialKit.NOTE_PERSONNEL, "SOCIAL_NOTE_ROUTINE", [npc.name, place, at])
	SocialKit.add_toast(res, "SOCIAL_TOAST_ROUTINE", [npc.name])
	return true


## Siguiente tramo de su agenda de hoy en otra sala (después de ahora); {} si no queda ninguno.
static func next_plan_entry(npc_id: String) -> Dictionary:
	var now: int = GameClock.get_hour() * MINUTES_PER_HOUR + GameClock.get_minute()
	var here: String = NPCDirector.get_current_location(npc_id)
	var best: Dictionary = {}
	for raw: Variant in NPCDirector.get_day_plan(npc_id):
		var entry: Dictionary = raw
		var room: String = str(entry.get("room", ""))
		if int(entry.get("start", 0)) <= now or room.is_empty() or room == here:
			continue
		if best.is_empty() or int(entry["start"]) < int(best["start"]):
			best = entry
	return best


static func _clock_text(minute_of_day: int) -> String:
	return UITheme.format_hour(minute_of_day / MINUTES_PER_HOUR % 24, minute_of_day % MINUTES_PER_HOUR)


# ─── Indicaciones y agenda ────────────────────────────────────

## Temas de «¿Dónde…?»: tu mesa, la próxima Aurora, su día y tus objetivos marcados (hasta 3).
static func direction_topics(npc_id: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = [
		{"id": TOPIC_DESK, "label": TranslationServer.translate("SOCIAL_DIR_Q_DESK")},
		{"id": TOPIC_AURORA, "label": TranslationServer.translate("SOCIAL_DIR_Q_AURORA")},
		{"id": TOPIC_DAY, "label": TranslationServer.translate("SOCIAL_DIR_Q_DAY")},
	]
	for target: String in PlayerState.get_marked_targets():
		if target != npc_id and out.size() < SocialKit.bi("menu.max_temas") and NPCDirector.is_active(target):
			out.append({"id": TOPIC_PERSON + target, "label": UITheme.trf("SOCIAL_DIR_Q_PERSON", [SocialKit.npc_name(target)])})
	return out


static func directions(npc_id: String, topic: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return SocialKit.refusal("SOCIAL_LINE_BUSY")
	if is_top(npc):
		var hello: Array = greeting(npc)
		return SocialKit.result(true, str(hello[0]), hello[1] as Array, "SOCIAL_TOAST_NO_TRUTH")
	if ignores_you(npc):
		return SocialKit.refusal("SOCIAL_DIR_IGNORED")
	if topic.begins_with(TOPIC_PERSON):
		return _where_is(topic.trim_prefix(TOPIC_PERSON))
	match topic:
		TOPIC_DESK:
			var occupation: OccupationData = PlayerState.get_occupation()
			var office: String = occupation.office_room if occupation != null else ""
			return SocialKit.result(true, "SOCIAL_DIR_DESK", [SocialKit.place_text(office)])
		TOPIC_AURORA:
			return _aurora()
		TOPIC_DAY:
			var res: Dictionary = SocialKit.result(true, "")
			if not _share_routine(npc, res):
				SocialKit.add_line(res, "SOCIAL_DIR_DAY_NOTHING")
			return res
	return SocialKit.refusal("SOCIAL_LINE_BUSY")


static func _where_is(target: String) -> Dictionary:
	var room: String = NPCDirector.get_current_location(target)
	if not NPCDirector.is_active(target) or room.is_empty():
		return SocialKit.result(true, "SOCIAL_DIR_PERSON_OUT", [SocialKit.npc_name(target)])
	return SocialKit.result(true, "SOCIAL_DIR_PERSON", [SocialKit.npc_name(target), SocialKit.place_text(room)])


static func _aurora() -> Dictionary:
	var schedule: Dictionary = IdeaPool.get_meeting_schedule()
	var place: String = SocialKit.place_text(str(schedule.get("room", "")))
	if IdeaPool.is_meeting_open():
		return SocialKit.result(true, "SOCIAL_DIR_AURORA_NOW", [place])
	var day: int = IdeaPool.get_next_meeting_day(GameClock.get_day())
	var hour: String = UITheme.format_hour(int(schedule.get("hour", 0)))
	if day == GameClock.get_day() and GameClock.get_hour() >= int(schedule.get("hour", 0)):
		day = IdeaPool.get_next_meeting_day(day + 1)
	return SocialKit.result(true, "SOCIAL_DIR_AURORA", [place, day, hour])


# ─── Regalar un mérito (George Penn, §8.3) ────────────────────

static func wants_credit(npc: NPCRuntime) -> bool:
	return npc != null and SocialKit.bdict("credito").get("debilidades", []).has(npc.weakness_key)


static func can_give_credit(npc_id: String) -> String:
	var left: int = SocialKit.cooldown_left(CREDIT_KIND, npc_id, SocialKit.bi("credito.dias_entre"))
	return "SOCIAL_REASON_CREDIT_WAIT" if left > 0 else ""


## Le cedes públicamente un mérito: favor en su registro, deuda (calla un tiempo), mérito suyo y
## un poco de tu reputación.
static func give_credit(npc_id: String) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if not wants_credit(npc) or not can_give_credit(npc_id).is_empty():
		return SocialKit.refusal("SOCIAL_LINE_BUSY")
	SocialKit.mark(CREDIT_KIND, npc_id)
	NPCDirector.add_favour(npc_id, FAVOUR_CREDIT, SocialKit.bi("credito.magnitud_favor"))
	NPCDirector.add_debt(npc_id, SocialKit.bi("credito.deuda"))
	NPCDirector.add_merit(npc_id, SocialKit.bi("credito.merito_personaje"))
	PlayerState.modify_reputation(-SocialKit.bf("credito.coste_reputacion"), REPUTATION_REASON)
	SocialKit.spend_minutes(SocialKit.bi("minutos_accion"))
	return SocialKit.result(true, "SOCIAL_CREDIT_LINE", [PlayerState.get_player_name()],
			"SOCIAL_TOAST_CREDIT", [npc.name], ToastStack.KIND_GOOD)
