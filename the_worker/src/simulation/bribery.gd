# bribery.gd — Sobornos (§8.2): precio justo, probabilidad de aceptación, rechazo y canales.
# PROPIETARIO DE: nada (librería sin estado: dinero de PlayerState, creencias de BeliefNet, material de chantaje en NPCRuntime vía Blackmail).
# ESCUCHA: nada.
class_name Bribery
extends RefCounted

## Uso principal: Bribery.offer(npc, cantidad, favor, canal, ctx) → Dictionary de resultado.
## Emite bribe_offered, crime_committed("bribe"), bribe_result y, si hay denuncia, game_over.
## ctx (todo opcional; lo que falta se lee de los autoloads):
##   wallet: Object con can_afford(int) -> bool y spend_money(int, String) -> bool (PlayerState)
##   reputation, suspicion (0–100) · affection, debt (registro del personaje)
##   rank_relation: RANK_PLAYER_SUPERIOR (+1), RANK_NPC_SUPERIOR (−1) o RANK_NONE (0)
##   daily_wage, price_modifier (registro), difficulty_modifier (preset) · asked_price
##   (contraoferta pendiente: ofrecer ≥ asked_price se acepta) · room_id, day, hour
##   listeners (llamada: ids en radio de escucha) · witnesses / cameras (en persona: ids)
##   crime_type (flagrancia) · roll / counter_roll (0–1: tiradas fijas, p. ej. en pruebas)
## Sin ctx["roll"], la tirada es determinista: semilla de partida + personaje + oferta + hora.

const PLAYER_ID := "player"
const FAVOUR_SILENCE := "silence_witnessed"
const CHANNEL_MOBILE_CHAT := "mobile_chat"
const CHANNEL_PHONE_CALL := "phone_call"
const CHANNEL_IN_PERSON := "in_person"
const CHANNEL_IMMEDIATE := "immediate"

const OUTCOME_ACCEPTED := "accepted"
const OUTCOME_DENOUNCED := "denounced"
const OUTCOME_SILENCE := "silence_with_memory"
const OUTCOME_COUNTEROFFER := "counteroffer"
const OUTCOME_NEUTRAL := "neutral_refusal"
const OUTCOME_NO_FUNDS := "insufficient_funds"
const OUTCOME_INVALID := "invalid"
const OUTCOME_TEXT_KEYS: Dictionary = {
	OUTCOME_ACCEPTED: "BRIBE_OUTCOME_ACCEPTED", OUTCOME_DENOUNCED: "BRIBE_OUTCOME_DENOUNCED",
	OUTCOME_SILENCE: "BRIBE_OUTCOME_SILENCE", OUTCOME_COUNTEROFFER: "BRIBE_OUTCOME_COUNTEROFFER",
	OUTCOME_NEUTRAL: "BRIBE_OUTCOME_NEUTRAL", OUTCOME_NO_FUNDS: "BRIBE_OUTCOME_INSUFFICIENT_FUNDS",
	OUTCOME_INVALID: "BRIBE_OUTCOME_INVALID",
}

const EFFECT_PAID := "paid"
const EFFECT_DIGITAL_RECORD := "digital_record"
const EFFECT_OVERHEARD := "overheard"
const EFFECT_WITNESSED := "witnessed"
const EFFECT_CAMERA := "camera"
const EFFECT_INSULTED := "insulted"
const EFFECT_BLACKMAIL := "blackmail_material"

const RANK_PLAYER_SUPERIOR := 1
const RANK_NPC_SUPERIOR := -1
const RANK_NONE := 0

const CAUSE_DENOUNCED := "bribe_denounced"
const CRIME_BRIBE := "bribe"
const MONEY_REASON := "bribe"
const DIFFICULTY_KEY := "precio_soborno"
const DIRECTOR_PRICE_METHOD := "get_bribe_price_modifier"
const TRACKING_CAUSE_METHOD := "evaluate_ending_for_cause"
## Hechos con la convención de BeliefNet "<tipo>:<detalle>" (peso en creencias.peso_tipo).
const FACT_REFUSED := "bribe_attempt:refused"
const FACT_INSULTED := "bribe_attempt:insulting"
const FACT_REMEMBERED := "bribe_attempt:remembered"
const FACT_OVERHEARD := "bribe_attempt:overheard"
const FACT_WITNESSED := "bribe_attempt:witnessed"
const RECORD_CHAT := "chat_log"
const SOURCE_DIRECT := "direct"
const PERCENT := 100.0


# ─── Datos ─────────────────────────────────────────────────────

static func tunable(path: String) -> float:
	return Database.get_balance_float(path)


static func tunable_int(path: String) -> int:
	return Database.get_balance_int(path)


static func favour_multiplier(favour_id: String) -> float:
	return float(Database.get_bribe_favour(favour_id).get("multiplier", 0.0))


## Salario diario: ocupación → puesto del nominado (daily_wage propio) → rol generado →
## media de su escalón.
static func npc_daily_wage(npc: NPCRuntime) -> int:
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id)
	if occupation != null:
		return occupation.daily_wage
	var named: NPCData = Database.get_named_npc(npc.id)
	if named != null and int(named.extra.get("daily_wage", 0)) > 0:
		return int(named.extra["daily_wage"])
	var role: Variant = npc.get("role")
	if role is String and not (role as String).is_empty():
		var role_wage: int = int(Database.get_role(role).get("daily_wage", 0))
		if role_wage > 0:
			return role_wage
	return tier_daily_wage(npc.tier)


static func tier_daily_wage(tier: int) -> int:
	var occupations: Array[OccupationData] = Database.get_occupations_by_tier(tier)
	if occupations.is_empty():
		return 0
	var total: int = 0
	for occupation: OccupationData in occupations:
		total += occupation.daily_wage
	return roundi(float(total) / occupations.size())


# ─── Precio ────────────────────────────────────────────────────

## §8.2 paso primero, sin modificadores: salario diario × multiplicador del favor.
static func base_price(daily_wage: int, favour_id: String) -> int:
	return roundi(daily_wage * favour_multiplier(favour_id))


## Precio justo aplicado: base × preset de dificultad (precio_soborno) × registro de relaciones.
static func fair_price(npc: NPCRuntime, favour_id: String, ctx: Dictionary = {}) -> int:
	var wage: int = int(ctx["daily_wage"]) if ctx.has("daily_wage") else npc_daily_wage(npc)
	var difficulty: float = float(ctx["difficulty_modifier"]) if ctx.has("difficulty_modifier") \
			else Database.get_difficulty_modifier(DIFFICULTY_KEY)
	var ledger: float = float(ctx["price_modifier"]) if ctx.has("price_modifier") \
			else ledger_price_modifier(npc)
	return roundi(wage * favour_multiplier(favour_id) * difficulty * ledger)


## Precio estimado del expediente N5 (§13.4): el precio justo del favor.
static func estimated_price(npc: NPCRuntime, favour_id: String) -> int:
	return fair_price(npc, favour_id)


## Agravios encarecen y favores abaratan (§7.9). Manda NPCDirector si ofrece
## get_bribe_price_modifier(npc_id) y conoce al personaje; si no, se calcula del registro.
static func ledger_price_modifier(npc: NPCRuntime) -> float:
	if NPCDirector.has_method(DIRECTOR_PRICE_METHOD) and NPCDirector.get_npc(npc.id) != null:
		return float(NPCDirector.call(DIRECTOR_PRICE_METHOD, npc.id))
	return ledger_modifier_from(npc.ledger)


static func ledger_modifier_from(ledger: Dictionary) -> float:
	var modifier: float = 1.0
	for grievance: Variant in ledger.get("grievances", []):
		if grievance is Dictionary:
			modifier += float(grievance.get("severity", 0)) \
					* tunable("sobornos.mod_precio_por_gravedad_agravio")
	for favour: Variant in ledger.get("favours", []):
		if favour is Dictionary:
			modifier -= float(favour.get("magnitude", 0)) \
					* tunable("sobornos.mod_precio_por_magnitud_favor")
	return clampf(modifier, tunable("sobornos.mod_precio_registro_min"),
			tunable("sobornos.mod_precio_registro_max"))


# ─── Probabilidad ──────────────────────────────────────────────

## Regla de excepción absoluta: codicia < 20 y lealtad > 80 → P = 0.
static func is_unbribable(traits: Dictionary) -> bool:
	return int(traits.get("greed", 0)) < tunable_int("sobornos.insobornable_codicia_max") \
			and int(traits.get("loyalty", 0)) > tunable_int("sobornos.insobornable_lealtad_min")


## ratio_oferta = mín(oferta ÷ precio_justo, 2,0) ÷ 2,0
static func offer_ratio(offer: int, fair: int) -> float:
	var cap: float = tunable("sobornos.ratio_oferta_tope")
	if fair <= 0:
		return 1.0
	return minf(float(offer) / float(fair), cap) / cap


static func is_insulting(offer: int, fair: int) -> bool:
	return float(offer) < tunable("sobornos.umbral_oferta_insultante") * float(fair)


static func rank_term(rank_relation: int) -> float:
	if rank_relation == RANK_PLAYER_SUPERIOR:
		return tunable("sobornos.mod_rango_superior")
	if rank_relation == RANK_NPC_SUPERIOR:
		return tunable("sobornos.mod_rango_inferior")
	return 0.0


## §8.2 paso segundo, con todos sus términos. inputs: reputation, suspicion, affection, debt,
## rank_relation. Acotada a [0, probabilidad_maxima]; oferta insultante → × 1/3.
static func probability_from(traits: Dictionary, offer: int, fair: int, inputs: Dictionary) -> float:
	if is_unbribable(traits):
		return 0.0
	var p: float = tunable("sobornos.base")
	p += tunable("sobornos.peso_codicia") * float(traits.get("greed", 0)) / PERCENT
	p += tunable("sobornos.peso_ratio_oferta") * offer_ratio(offer, fair)
	p += tunable("sobornos.peso_afecto_deuda") \
			* (float(inputs.get("affection", 0)) + float(inputs.get("debt", 0))) / PERCENT
	p += tunable("sobornos.peso_reputacion") * float(inputs.get("reputation", 0.0)) / PERCENT
	p += tunable("sobornos.peso_sospecha") * float(inputs.get("suspicion", 0.0)) / PERCENT
	p += tunable("sobornos.peso_valentia") * float(traits.get("courage", 0)) / PERCENT
	p += tunable("sobornos.peso_lealtad") * float(traits.get("loyalty", 0)) / PERCENT
	p += rank_term(int(inputs.get("rank_relation", RANK_NONE)))
	p = clampf(p, 0.0, tunable("sobornos.probabilidad_maxima"))
	if is_insulting(offer, fair):
		p *= tunable("sobornos.penalizacion_oferta_insultante")
	return p


static func acceptance_probability(npc: NPCRuntime, offer: int, favour_id: String,
		ctx: Dictionary = {}) -> float:
	return probability_from(npc.traits, offer, fair_price(npc, favour_id, ctx),
			gather_inputs(npc, ctx))


## Variables del jugador y del registro; ctx manda sobre lo leído de los autoloads.
static func gather_inputs(npc: NPCRuntime, ctx: Dictionary) -> Dictionary:
	var inputs: Dictionary = {
		"affection": int(npc.ledger.get("affection", 0)), "debt": int(npc.ledger.get("debt", 0)),
	}
	inputs["reputation"] = ctx["reputation"] if ctx.has("reputation") \
			else PlayerState.get_reputation()
	inputs["suspicion"] = ctx["suspicion"] if ctx.has("suspicion") else PlayerState.get_suspicion()
	inputs["rank_relation"] = ctx["rank_relation"] if ctx.has("rank_relation") \
			else rank_relation(npc)
	for key: String in ["affection", "debt"]:
		if ctx.has(key):
			inputs[key] = ctx[key]
	return inputs


# ─── Rango ─────────────────────────────────────────────────────

static func rank_relation(npc: NPCRuntime) -> int:
	return rank_relation_between(PlayerState.get_occupation(),
			Database.get_occupation(npc.occupation_id))


## +1 si el jugador es superior jerárquico directo del personaje, −1 si el personaje lo es del
## jugador, 0 en otro caso. Superior directo: puesto con subordinados (has_subordinates) de
## escalón mayor que comparte sala de trabajo, o del mismo departamento y un escalón por encima.
static func rank_relation_between(player_occ: OccupationData, npc_occ: OccupationData) -> int:
	if player_occ == null or npc_occ == null:
		return RANK_NONE
	if is_direct_superior(player_occ, npc_occ):
		return RANK_PLAYER_SUPERIOR
	if is_direct_superior(npc_occ, player_occ):
		return RANK_NPC_SUPERIOR
	return RANK_NONE


static func is_direct_superior(boss: OccupationData, subordinate: OccupationData) -> bool:
	if not bool(boss.extra.get("has_subordinates", false)) or boss.tier <= subordinate.tier:
		return false
	if not boss.office_room.is_empty() and boss.office_room == subordinate.office_room:
		return true
	return str(boss.extra.get("department", "")) == str(subordinate.extra.get("department", "")) \
			and boss.tier == subordinate.tier + 1


# ─── Rechazo ───────────────────────────────────────────────────

## §8.2 paso tercero, en orden: denuncia → silencio con memoria → contraoferta → rechazo neutro.
static func rejection_outcome(traits: Dictionary, offer: int, fair: int) -> String:
	var courage: int = int(traits.get("courage", 0))
	var loyalty: int = int(traits.get("loyalty", 0))
	if courage > tunable_int("sobornos.umbral_denuncia_valentia") \
			or loyalty > tunable_int("sobornos.umbral_denuncia_lealtad"):
		return OUTCOME_DENOUNCED
	if courage < tunable_int("sobornos.umbral_silencio_valentia"):
		return OUTCOME_SILENCE
	if int(traits.get("greed", 0)) > tunable_int("sobornos.umbral_contraoferta_codicia") \
			and float(offer) >= tunable("sobornos.umbral_contraoferta_oferta") * float(fair):
		return OUTCOME_COUNTEROFFER
	return OUTCOME_NEUTRAL


## Entre 1,3 y 1,8 veces el precio justo (roll 0 → mínimo, roll 1 → máximo).
static func counteroffer_price(fair: int, roll: float) -> int:
	return roundi(fair * lerpf(tunable("sobornos.factor_contraoferta_min"),
			tunable("sobornos.factor_contraoferta_max"), clampf(roll, 0.0, 1.0)))


## Tirada determinista en [0, 1) a partir de la semilla de partida, el momento y `parts`.
static func roll_for(parts: Array) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var key: Array = [GameClock.get_run_seed(), GameClock.get_day(), GameClock.get_hour(),
			GameClock.get_minute()]
	key.append_array(parts)
	rng.seed = hash(key)
	return rng.randf()


## Decisión pura (sin efectos): {fair_price, probability, roll, accepted, outcome, insulting,
## asked_price (solo contraoferta)}.
static func evaluate(npc: NPCRuntime, amount: int, favour_id: String, ctx: Dictionary) -> Dictionary:
	var fair: int = fair_price(npc, favour_id, ctx)
	var result: Dictionary = {"npc_id": npc.id, "amount": amount, "favour": favour_id,
			"fair_price": fair, "insulting": is_insulting(amount, fair), "asked_price": 0}
	var asked: int = int(ctx.get("asked_price", 0))
	if asked > 0 and amount >= asked:
		result.merge({"probability": 1.0, "roll": 0.0, "accepted": true,
				"outcome": OUTCOME_ACCEPTED, "insulting": false}, true)
		return result
	var p: float = probability_from(npc.traits, amount, fair, gather_inputs(npc, ctx))
	var roll: float = float(ctx["roll"]) if ctx.has("roll") \
			else roll_for([npc.id, amount, favour_id, OUTCOME_ACCEPTED])
	var accepted: bool = roll < p
	result.merge({"probability": p, "roll": roll, "accepted": accepted}, true)
	result["outcome"] = OUTCOME_ACCEPTED if accepted else rejection_outcome(npc.traits, amount, fair)
	if result["outcome"] == OUTCOME_COUNTEROFFER:
		var counter_roll: float = float(ctx["counter_roll"]) if ctx.has("counter_roll") \
				else roll_for([npc.id, amount, favour_id, OUTCOME_COUNTEROFFER])
		result["asked_price"] = counteroffer_price(fair, counter_roll)
	return result


# ─── Oferta completa ───────────────────────────────────────────

## Ofrece `amount` al personaje por `favour_id` a través de `channel_id` y aplica todas las
## consecuencias. El canal "immediate" fuerza el favor silence_witnessed (×20).
## Devuelve evaluate() + {ok, channel, room_id, effects, beliefs, record_id, footage_id,
## paid, text_key}. ok = false (sin señales ni efectos) si la oferta no es válida o no hay fondos.
static func offer(npc: NPCRuntime, amount: int, favour_id: String, channel_id: String,
		ctx: Dictionary = {}) -> Dictionary:
	var channel: Dictionary = Database.get_bribe_channel(channel_id)
	var favour: String = str(channel.get("forced_favour", favour_id))
	var problem: String = _check_offer(npc, amount, favour, channel, ctx)
	if not problem.is_empty():
		return {"ok": false, "outcome": problem, "amount": amount, "favour": favour,
				"channel": channel_id, "text_key": OUTCOME_TEXT_KEYS[problem]}
	EventBus.bribe_offered.emit(npc.id, amount, favour)
	var result: Dictionary = evaluate(npc, amount, favour, ctx)
	result.merge({"ok": true, "channel": channel_id, "room_id": _room(npc, ctx), "effects": [],
			"beliefs": [], "record_id": "", "footage_id": "", "paid": 0}, true)
	_apply_channel(npc, channel, ctx, result)
	_apply_outcome(npc, ctx, result)
	result["text_key"] = OUTCOME_TEXT_KEYS[result["outcome"]]
	EventBus.crime_committed.emit(CRIME_BRIBE, str(result["room_id"]), _crime_details(result))
	EventBus.bribe_result.emit(npc.id, bool(result["accepted"]), str(result["outcome"]))
	if result["outcome"] == OUTCOME_DENOUNCED:
		declare_game_over(CAUSE_DENOUNCED)
	return result


static func offer_to(npc_id: String, amount: int, favour_id: String, channel_id: String,
		ctx: Dictionary = {}) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return {"ok": false, "outcome": OUTCOME_INVALID, "text_key": OUTCOME_TEXT_KEYS[OUTCOME_INVALID]}
	return offer(npc, amount, favour_id, channel_id, ctx)


## Expulsión inmediata: game_over con la causa de endings.json y el final que le corresponde.
static func declare_game_over(cause: String) -> void:
	EventBus.game_over.emit(cause, ending_for_cause(cause), Tracking.get_snapshot())


## Primer final de evaluation_order cuya condición `cause` incluye la causa (Tracking manda si
## ofrece evaluate_ending_for_cause(cause)).
static func ending_for_cause(cause: String) -> String:
	if Tracking.has_method(TRACKING_CAUSE_METHOD):
		return str(Tracking.call(TRACKING_CAUSE_METHOD, cause))
	var rules: Dictionary = Database.get_raw("endings")
	for ending_id: Variant in rules.get("evaluation_order", []):
		var conditions: Dictionary = Database.get_ending(str(ending_id)).get("conditions", {})
		var causes: Variant = conditions.get("cause", [])
		if causes is Array and (causes as Array).has(cause):
			return str(ending_id)
	return str(rules.get("fallback_ending", ""))


static func _check_offer(npc: NPCRuntime, amount: int, favour: String, channel: Dictionary,
		ctx: Dictionary) -> String:
	if npc == null or not npc.alive or amount <= 0 or channel.is_empty():
		return OUTCOME_INVALID
	if Database.get_bribe_favour(favour).is_empty():
		return OUTCOME_INVALID
	if not bool(_wallet(ctx).call("can_afford", amount)):
		return OUTCOME_NO_FUNDS
	return ""


static func _apply_channel(npc: NPCRuntime, channel: Dictionary, ctx: Dictionary,
		result: Dictionary) -> void:
	var room: String = str(result["room_id"])
	if bool(channel.get("leaves_digital_record", false)):
		result["record_id"] = BeliefNet.create_record(RECORD_CHAT, PLAYER_ID,
				tunable("sobornos.peso_registro_chat"), room)
		result["effects"].append(EFFECT_DIGITAL_RECORD)
	if bool(channel.get("requires_privacy", false)):
		if _add_beliefs(result, npc.id, ctx.get("listeners", []), FACT_OVERHEARD,
				tunable("sobornos.certeza_escucha_llamada")) > 0:
			result["effects"].append(EFFECT_OVERHEARD)
	if bool(channel.get("witness_risk", false)):
		if _add_beliefs(result, npc.id, ctx.get("witnesses", []), FACT_WITNESSED,
				tunable("sobornos.certeza_testigo_en_persona")) > 0:
			result["effects"].append(EFFECT_WITNESSED)
		var cameras: Variant = ctx.get("cameras", [])
		if cameras is Array and not (cameras as Array).is_empty():
			result["footage_id"] = Security.register_camera_footage(room, _day(ctx),
					int(ctx.get("hour", GameClock.get_hour())))
			result["effects"].append(EFFECT_CAMERA)


static func _apply_outcome(npc: NPCRuntime, ctx: Dictionary, result: Dictionary) -> void:
	var room: String = str(result["room_id"])
	var crime_type: String = str(ctx.get("crime_type", CRIME_BRIBE))
	match str(result["outcome"]):
		OUTCOME_ACCEPTED:
			var amount: int = int(result["amount"])
			if bool(_wallet(ctx).call("spend_money", amount, MONEY_REASON)):
				result["paid"] = amount
				result["effects"].append(EFFECT_PAID)
			if result["favour"] == FAVOUR_SILENCE:
				Blackmail.add_material(npc, Blackmail.KIND_BRIBED_SILENCE, crime_type, _day(ctx))
				result["effects"].append(EFFECT_BLACKMAIL)
		OUTCOME_SILENCE:
			_add_belief(result, npc.id, FACT_REMEMBERED, tunable("sobornos.certeza_silencio_memoria"),
					room)
			Blackmail.add_material(npc, Blackmail.KIND_SILENCE_MEMORY, crime_type, _day(ctx))
			result["effects"].append(EFFECT_BLACKMAIL)
		OUTCOME_NEUTRAL:
			_add_belief(result, npc.id, FACT_REFUSED, tunable("sobornos.certeza_rechazo_neutro"), room)
	if bool(result["insulting"]) and result["outcome"] != OUTCOME_DENOUNCED:
		_add_belief(result, npc.id, FACT_INSULTED, tunable("sobornos.certeza_oferta_insultante"), room)
		result["effects"].append(EFFECT_INSULTED)


static func _add_beliefs(result: Dictionary, npc_id: String, holders: Variant, fact: String,
		certainty: float) -> int:
	var count: int = 0
	if not holders is Array:
		return count
	for holder: Variant in holders:
		if str(holder) != npc_id and not str(holder).is_empty():
			_add_belief(result, str(holder), fact, certainty, str(result["room_id"]))
			count += 1
	return count


static func _add_belief(result: Dictionary, holder: String, fact: String, certainty: float,
		room: String) -> void:
	var belief_id: String = BeliefNet.create_belief(holder, PLAYER_ID, fact, certainty,
			SOURCE_DIRECT, room)
	result["beliefs"].append({"id": belief_id, "holder": holder, "fact": fact,
			"certainty": certainty})


static func _crime_details(result: Dictionary) -> Dictionary:
	return {"npc_id": result["npc_id"], "amount": result["amount"], "paid": result["paid"],
			"favour": result["favour"], "channel": result["channel"],
			"accepted": result["accepted"], "outcome": result["outcome"]}


static func _wallet(ctx: Dictionary) -> Object:
	var wallet: Variant = ctx.get("wallet")
	return wallet as Object if wallet is Object else PlayerState


static func _room(npc: NPCRuntime, ctx: Dictionary) -> String:
	if ctx.has("room_id"):
		return str(ctx["room_id"])
	var location: String = NPCDirector.get_current_location(npc.id)
	return location if not location.is_empty() else npc.current_room


static func _day(ctx: Dictionary) -> int:
	return int(ctx.get("day", GameClock.get_day()))
