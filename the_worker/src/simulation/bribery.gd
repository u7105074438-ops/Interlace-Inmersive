# bribery.gd — Sobornos (§8.2): precio justo, probabilidad de aceptación, rechazo, contraoferta y canales.
# PROPIETARIO DE: nada (librería sin estado; dinero, creencias, registro y material de chantaje pertenecen a sus dueños).
# ESCUCHA: nada.
class_name Bribery
extends RefCounted

## Uso principal: Bribery.offer(npc, cantidad, favor, canal, ctx) → Dictionary de resultado.
## Emite bribe_offered, crime_committed("bribe"), bribe_result y, si hay denuncia, game_over.
## ctx (todo opcional; lo que falta se lee de los autoloads):
##   wallet: Bribery.Wallet (por defecto, el dinero de PlayerState)
##   reputation, suspicion (0–100) · affection, debt (registro del personaje)
##   rank_relation: RANK_PLAYER_SUPERIOR (+1), RANK_NPC_SUPERIOR (−1) o RANK_NONE (0)
##   daily_wage, price_modifier (registro), difficulty_modifier (preset) · room_id, day, hour
##   counteroffer: la ficha que devolvió una contraoferta previa (ver abajo)
##   listeners (llamada: ids en radio de escucha) · witnesses (en persona e inmediato: ids)
##   cameras (en persona: ids) · crime_type (flagrancia) · roll / counter_roll (tiradas fijas)
## DECISIONES (contrato para el resto de sistemas):
##  · Precio justo = salario diario × multiplicador del favor × registro (§7.9) × preset de
##    dificultad (precio_soborno, §15.7) × (1 + sobornos.mod_precio_por_sospecha × sospecha/100)
##    (§7.10: la sospecha encarece). NPCDirector.get_fair_bribe_price() y
##    get_bribe_price_modifier() delegan aquí (una sola fórmula, claves registro.precio_*).
##    Salario: NPCDirector.get_daily_wage() para la plantilla (ocupación o puesto no jugable);
##    fuera de ella, ocupación → daily_wage/role del nominado → media del escalón.
##  · P = 0 si codicia < 20 y lealtad > 80 (§8.2) o si el arquetipo está en
##    sobornos.arquetipos_insobornables (§8.1: el incorruptible es nulo «por definición», aunque la
##    variación ±15 lo saque de la regla de rasgos). Nada lo salta: tampoco una contraoferta.
##  · Una tirada por personaje, favor y jornada (semilla de partida): cambiar la cantidad o esperar
##    no vuelve a tirar; ofrecer más solo sube P.
##  · Contraoferta: resultado["counteroffer"] = ficha {npc_id, favour, asked_price, day, rounds}.
##    Devuelta en ctx["counteroffer"] (mismo personaje, mismo favor, misma jornada ±
##    sobornos.jornadas_validez_contraoferta, precio ≥ 1,3 × el justo actual): oferta ≥ precio
##    pedido → aceptada sin tirada; menor → repite su precio (otra ronda) y, pasadas
##    sobornos.max_contraofertas rondas, rechazo neutro. Cada contraoferta cuesta: creencia
##    "bribe_attempt:countered" del personaje (se refuerza en cada ronda).
##  · Canales: chat → registro chat_log (peso creencias.peso_tipo.chat_log); llamada → cada
##    oyente de ctx.listeners recibe "bribe_attempt:overheard"; en persona → testigos
##    ("bribe_attempt:witnessed") y cámaras (Security.register_camera_footage); inmediato → favor
##    silence_witnessed forzado y los testigos de la flagrancia también lo ven.

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
const TEXT_INSULTED := "BRIBE_OUTCOME_INSULTED"

const EFFECT_PAID := "paid"
const EFFECT_DIGITAL_RECORD := "digital_record"
const EFFECT_OVERHEARD := "overheard"
const EFFECT_WITNESSED := "witnessed"
const EFFECT_CAMERA := "camera"
const EFFECT_INSULTED := "insulted"
const EFFECT_COUNTERED := "countered"
const EFFECT_BLACKMAIL := "blackmail_material"

const RANK_PLAYER_SUPERIOR := 1
const RANK_NPC_SUPERIOR := -1
const RANK_NONE := 0

const CAUSE_DENOUNCED := "bribe_denounced"
const CRIME_BRIBE := "bribe"
const MONEY_REASON := "bribe"
const DIFFICULTY_KEY := "precio_soborno"
## Hechos con la convención de BeliefNet "<tipo>:<detalle>" (peso en creencias.peso_tipo).
const FACT_REFUSED := "bribe_attempt:refused"
const FACT_INSULTED := "bribe_attempt:insulting"
const FACT_REMEMBERED := "bribe_attempt:remembered"
const FACT_OVERHEARD := "bribe_attempt:overheard"
const FACT_WITNESSED := "bribe_attempt:witnessed"
const FACT_COUNTERED := "bribe_attempt:countered"
const RECORD_CHAT := "chat_log"
const SOURCE_DIRECT := "direct"
const PERCENT := 100.0

## Ficha de contraoferta (ctx["counteroffer"] / resultado["counteroffer"]).
const CTX_COUNTEROFFER := "counteroffer"
const TOKEN_NPC := "npc_id"
const TOKEN_FAVOUR := "favour"
const TOKEN_ASKED := "asked_price"
const TOKEN_DAY := "day"
const TOKEN_ROUNDS := "rounds"

## Jerarquía de generación (npcs_generation.json): superior de cada sala de trabajo.
const GENERATION_FILE := "npcs_generation"
const HIERARCHY_PATH: Array[String] = ["link_generation", "hierarchy", "superior_by_room"]
const OCCUPATION_PREFIX := "occ:"
const KEY_UNBRIBABLE_ARCHETYPES := "sobornos.arquetipos_insobornables"
const KEY_GENERAL_SUPERIORS := "sobornos.departamentos_superiores_generales"


## Monedero del soborno: por defecto el de PlayerState. Herramientas y pruebas lo sustituyen
## extendiendo esta clase (Bribery.Wallet).
class Wallet:
	extends RefCounted

	func can_afford(amount: int) -> bool:
		return PlayerState.can_afford(amount)

	func spend_money(amount: int, reason: String) -> bool:
		return PlayerState.spend_money(amount, reason)


# ─── Datos ─────────────────────────────────────────────────────

static func tunable(path: String) -> float:
	return Database.get_balance_float(path)


static func tunable_int(path: String) -> int:
	return Database.get_balance_int(path)


static func tunable_strings(path: String) -> Array[String]:
	var out: Array[String] = []
	var raw: Variant = Database.get_balance(path)
	if raw is Array:
		for value: Variant in raw:
			out.append(str(value))
	return out


static func favour_multiplier(favour_id: String) -> float:
	return float(Database.get_bribe_favour(favour_id).get("multiplier", 0.0))


## Salario diario: el del perfil de NPCDirector (ocupación o puesto no jugable) para la plantilla;
## fuera de ella, ocupación → daily_wage / role del nominado → media de su escalón.
static func npc_daily_wage(npc: NPCRuntime) -> int:
	if is_managed(npc):
		var managed: int = NPCDirector.get_daily_wage(npc.id)
		if managed > 0:
			return managed
	var occupation: OccupationData = Database.get_occupation(npc.occupation_id)
	if occupation != null:
		return occupation.daily_wage
	var named: NPCData = Database.get_named_npc(npc.id)
	if named != null:
		if int(named.extra.get("daily_wage", 0)) > 0:
			return int(named.extra["daily_wage"])
		var role_wage: int = int(Database.get_role(str(named.extra.get("role", ""))).get(
				"daily_wage", 0))
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


## true si el personaje pertenece a la población de NPCDirector (su registro y su ubicación
## se consultan allí); los personajes sueltos (herramientas, pruebas) solo usan sus datos.
static func is_managed(npc: NPCRuntime) -> bool:
	return npc != null and NPCDirector.get_npc(npc.id) != null


static func npc_location(npc: NPCRuntime) -> String:
	var location: String = NPCDirector.get_current_location(npc.id) if is_managed(npc) else ""
	return location if not location.is_empty() else npc.current_room


# ─── Precio ────────────────────────────────────────────────────

## §8.2 paso primero, sin modificadores: salario diario × multiplicador del favor.
static func base_price(daily_wage: int, favour_id: String) -> int:
	return roundi(daily_wage * favour_multiplier(favour_id))


## Precio justo aplicado (ver DECISIONES). Mismo orden de producto que NPCDirector.
static func fair_price(npc: NPCRuntime, favour_id: String, ctx: Dictionary = {}) -> int:
	var wage: int = int(ctx["daily_wage"]) if ctx.has("daily_wage") else npc_daily_wage(npc)
	var ledger: float = float(ctx["price_modifier"]) if ctx.has("price_modifier") \
			else ledger_price_modifier(npc)
	var difficulty: float = float(ctx["difficulty_modifier"]) if ctx.has("difficulty_modifier") \
			else Database.get_difficulty_modifier(DIFFICULTY_KEY)
	var suspicion: float = float(ctx["suspicion"]) if ctx.has("suspicion") \
			else PlayerState.get_suspicion()
	return roundi(float(wage) * favour_multiplier(favour_id) * ledger * difficulty
			* suspicion_price_factor(suspicion))


## §7.10: la sospecha encarece el soborno. 1 + mod × sospecha/100.
static func suspicion_price_factor(suspicion: float) -> float:
	return 1.0 + tunable("sobornos.mod_precio_por_sospecha") * maxf(suspicion, 0.0) / PERCENT


## Precio estimado del expediente N5 (§13.4): el precio justo del favor.
static func estimated_price(npc: NPCRuntime, favour_id: String) -> int:
	return fair_price(npc, favour_id)


## Agravios encarecen y favores abaratan (§7.9): NPCDirector para la plantilla; fuera de ella, la
## misma fórmula (registro.precio_*) sobre el registro propio del personaje.
static func ledger_price_modifier(npc: NPCRuntime) -> float:
	if is_managed(npc):
		return NPCDirector.get_bribe_price_modifier(npc.id)
	return ledger_modifier_from(npc.ledger)


static func ledger_modifier_from(ledger: Dictionary) -> float:
	var modifier: float = 1.0
	for grievance: Variant in ledger.get("grievances", []):
		if grievance is Dictionary:
			modifier += float(grievance.get("severity", 0)) \
					* tunable("registro.precio_por_gravedad_agravio")
	for favour: Variant in ledger.get("favours", []):
		if favour is Dictionary:
			modifier -= float(favour.get("magnitude", 0)) \
					* tunable("registro.precio_por_magnitud_favor")
	return clampf(modifier, tunable("registro.precio_modificador_min"),
			tunable("registro.precio_modificador_max"))


# ─── Probabilidad ──────────────────────────────────────────────

## Regla de excepción absoluta: codicia < 20 y lealtad > 80 → P = 0.
static func is_unbribable(traits: Dictionary) -> bool:
	return int(traits.get("greed", 0)) < tunable_int("sobornos.insobornable_codicia_max") \
			and int(traits.get("loyalty", 0)) > tunable_int("sobornos.insobornable_lealtad_min")


## §8.1: arquetipos de probabilidad nula por definición (sobornos.arquetipos_insobornables).
static func is_unbribable_archetype(archetype_id: String) -> bool:
	return not archetype_id.is_empty() \
			and tunable_strings(KEY_UNBRIBABLE_ARCHETYPES).has(archetype_id)


static func is_npc_unbribable(npc: NPCRuntime) -> bool:
	return is_unbribable_archetype(npc.archetype) or is_unbribable(npc.traits)


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
static func probability_from(traits: Dictionary, offer: int, fair: int,
		inputs: Dictionary) -> float:
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
	if is_npc_unbribable(npc):
		return 0.0
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


## §8.2 modificador_de_rango: +1 si el jugador es superior jerárquico DIRECTO del personaje;
## −1 si el personaje es superior del jugador (directo o más arriba en su línea); 0 si no.
## Sin puesto jugable (roles) no hay relación.
static func rank_relation_between(player_occ: OccupationData, npc_occ: OccupationData) -> int:
	if player_occ == null or npc_occ == null:
		return RANK_NONE
	if is_direct_superior(player_occ, npc_occ):
		return RANK_PLAYER_SUPERIOR
	if is_superior(npc_occ, player_occ):
		return RANK_NPC_SUPERIOR
	return RANK_NONE


## Superior directo: puesto con subordinados y escalón mayor que comparte sala de trabajo, que
## es el superior de la sala del subordinado en la jerarquía de generación (superior_by_room), o
## del mismo departamento y exactamente un escalón por encima.
static func is_direct_superior(boss: OccupationData, subordinate: OccupationData) -> bool:
	if not bool(boss.extra.get("has_subordinates", false)) or boss.tier <= subordinate.tier:
		return false
	if not boss.office_room.is_empty() and boss.office_room == subordinate.office_room:
		return true
	if room_superior_occupation(subordinate.office_room) == boss.id:
		return true
	return _department(boss) == _department(subordinate) and boss.tier == subordinate.tier + 1


## Superior (en su línea, no necesariamente directo): superior directo, o puesto con subordinados
## de escalón mayor del mismo departamento o de la dirección general
## (sobornos.departamentos_superiores_generales).
static func is_superior(boss: OccupationData, subordinate: OccupationData) -> bool:
	if is_direct_superior(boss, subordinate):
		return true
	if not bool(boss.extra.get("has_subordinates", false)) or boss.tier <= subordinate.tier:
		return false
	return _department(boss) == _department(subordinate) \
			or tunable_strings(KEY_GENERAL_SUPERIORS).has(_department(boss))


## Ocupación del superior de una sala (npcs_generation.json superior_by_room: "occ:<id>" o un
## nominado, cuya ocupación se toma); "" si la sala no tiene o es un puesto no jugable.
static func room_superior_occupation(room_id: String) -> String:
	var node: Variant = Database.get_raw(GENERATION_FILE)
	for key: String in HIERARCHY_PATH:
		node = (node as Dictionary).get(key, {}) if node is Dictionary else {}
	var value: String = str((node as Dictionary).get(room_id, "")) if node is Dictionary else ""
	if value.begins_with(OCCUPATION_PREFIX):
		return value.trim_prefix(OCCUPATION_PREFIX)
	var named: NPCData = Database.get_named_npc(value) if not value.is_empty() else null
	return named.occupation if named != null else ""


static func _department(occupation: OccupationData) -> String:
	return str(occupation.extra.get("department", ""))


# ─── Rechazo y contraoferta ────────────────────────────────────

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


## Tirada determinista en [0, 1) a partir de la semilla de partida, la jornada y `parts`
## (la hora no entra: esperar no vuelve a tirar).
static func roll_for(parts: Array) -> float:
	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	var key: Array = [GameClock.get_run_seed(), GameClock.get_day()]
	key.append_array(parts)
	rng.seed = hash(key)
	return rng.randf()


static func make_counteroffer(npc_id: String, favour_id: String, asked: int, rounds: int,
		day: int) -> Dictionary:
	return {TOKEN_NPC: npc_id, TOKEN_FAVOUR: favour_id, TOKEN_ASKED: asked,
			TOKEN_DAY: day, TOKEN_ROUNDS: rounds}


## La ficha de ctx["counteroffer"] si sigue en pie para este personaje, favor, jornada y precio
## justo actual; {} si no hay o no vale.
static func standing_counteroffer(npc: NPCRuntime, favour_id: String, fair: int,
		ctx: Dictionary) -> Dictionary:
	var raw: Variant = ctx.get(CTX_COUNTEROFFER, {})
	if not raw is Dictionary or (raw as Dictionary).is_empty():
		return {}
	var token: Dictionary = raw
	if str(token.get(TOKEN_NPC, "")) != npc.id or str(token.get(TOKEN_FAVOUR, "")) != favour_id:
		return {}
	var age: int = _day(ctx) - int(token.get(TOKEN_DAY, -1))
	if age < 0 or age > tunable_int("sobornos.jornadas_validez_contraoferta"):
		return {}
	if int(token.get(TOKEN_ASKED, 0)) < counteroffer_price(fair, 0.0):
		return {}
	return token


## Decisión pura (sin efectos): {npc_id, amount, favour, fair_price, insulting, unbribable,
## probability, roll, accepted, outcome, asked_price, counteroffer}.
static func evaluate(npc: NPCRuntime, amount: int, favour_id: String,
		ctx: Dictionary) -> Dictionary:
	var fair: int = fair_price(npc, favour_id, ctx)
	var result: Dictionary = {"npc_id": npc.id, "amount": amount, "favour": favour_id,
			"fair_price": fair, "insulting": is_insulting(amount, fair), "asked_price": 0,
			"counteroffer": {}, "unbribable": is_npc_unbribable(npc)}
	var standing: Dictionary = {} if bool(result["unbribable"]) \
			else standing_counteroffer(npc, favour_id, fair, ctx)
	if standing.is_empty():
		_evaluate_formula(npc, ctx, result)
	else:
		_evaluate_standing(result, standing, _day(ctx))
	return result


static func _evaluate_formula(npc: NPCRuntime, ctx: Dictionary, result: Dictionary) -> void:
	var amount: int = int(result["amount"])
	var fair: int = int(result["fair_price"])
	var favour: String = str(result["favour"])
	var p: float = 0.0 if bool(result["unbribable"]) \
			else probability_from(npc.traits, amount, fair, gather_inputs(npc, ctx))
	var roll: float = float(ctx["roll"]) if ctx.has("roll") \
			else roll_for([npc.id, favour, OUTCOME_ACCEPTED])
	var accepted: bool = roll < p
	result.merge({"probability": p, "roll": roll, "accepted": accepted}, true)
	result["outcome"] = OUTCOME_ACCEPTED if accepted \
			else rejection_outcome(npc.traits, amount, fair)
	if result["outcome"] != OUTCOME_COUNTEROFFER:
		return
	if bool(result["unbribable"]):
		result["outcome"] = OUTCOME_NEUTRAL
		return
	var counter_roll: float = float(ctx["counter_roll"]) if ctx.has("counter_roll") \
			else roll_for([npc.id, favour, OUTCOME_COUNTEROFFER])
	result["asked_price"] = counteroffer_price(fair, counter_roll)
	result["counteroffer"] = make_counteroffer(npc.id, favour, int(result["asked_price"]), 1,
			_day(ctx))


## Con una contraoferta en pie: se paga su precio (aceptado) o repite su precio hasta agotar
## sobornos.max_contraofertas rondas (rechazo neutro). No hay nueva tirada.
static func _evaluate_standing(result: Dictionary, standing: Dictionary, day: int) -> void:
	var asked: int = int(standing[TOKEN_ASKED])
	result["asked_price"] = asked
	if int(result["amount"]) >= asked:
		result.merge({"probability": 1.0, "roll": 0.0, "accepted": true,
				"outcome": OUTCOME_ACCEPTED, "insulting": false}, true)
		return
	var rounds: int = int(standing.get(TOKEN_ROUNDS, 1)) + 1
	result.merge({"probability": 0.0, "roll": 0.0, "accepted": false}, true)
	if rounds > tunable_int("sobornos.max_contraofertas"):
		result["outcome"] = OUTCOME_NEUTRAL
		return
	result["outcome"] = OUTCOME_COUNTEROFFER
	result["counteroffer"] = make_counteroffer(str(result["npc_id"]), str(result["favour"]),
			asked, rounds, day)


# ─── Oferta completa ───────────────────────────────────────────

## Ofrece `amount` al personaje por `favour_id` a través de `channel_id` y aplica todas las
## consecuencias. El canal "immediate" fuerza el favor silence_witnessed (×20).
## Devuelve evaluate() + {ok, channel, room_id, effects, beliefs, record_id, footage_id,
## paid, text_key, insult_text_key}. ok = false (sin señales ni efectos) si la oferta no es
## válida o no hay fondos.
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
	_apply_channel(npc, channel_id, channel, ctx, result)
	_apply_outcome(npc, ctx, result)
	_set_text_keys(result)
	EventBus.crime_committed.emit(CRIME_BRIBE, str(result["room_id"]), _crime_details(result))
	EventBus.bribe_result.emit(npc.id, bool(result["accepted"]), str(result["outcome"]))
	if result["outcome"] == OUTCOME_DENOUNCED:
		declare_game_over(CAUSE_DENOUNCED)
	return result


static func offer_to(npc_id: String, amount: int, favour_id: String, channel_id: String,
		ctx: Dictionary = {}) -> Dictionary:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	if npc == null:
		return {"ok": false, "outcome": OUTCOME_INVALID,
				"text_key": OUTCOME_TEXT_KEYS[OUTCOME_INVALID]}
	return offer(npc, amount, favour_id, channel_id, ctx)


## Expulsión inmediata: game_over con la causa de endings.json y el final que le corresponde.
static func declare_game_over(cause: String) -> void:
	EventBus.game_over.emit(cause, ending_for_cause(cause), Tracking.get_snapshot())


## El final de endings.json para una causa terminal (lo decide Tracking con todas sus condiciones).
static func ending_for_cause(cause: String) -> String:
	return Tracking.evaluate_ending_for_cause(cause)


## El monedero de ctx["wallet"] (Bribery.Wallet) o el de PlayerState.
static func wallet_from(ctx: Dictionary) -> Wallet:
	var wallet: Variant = ctx.get("wallet")
	return wallet as Wallet if wallet is Wallet else Wallet.new()


static func _check_offer(npc: NPCRuntime, amount: int, favour: String, channel: Dictionary,
		ctx: Dictionary) -> String:
	if npc == null or not npc.alive or amount <= 0 or channel.is_empty():
		return OUTCOME_INVALID
	if Database.get_bribe_favour(favour).is_empty():
		return OUTCOME_INVALID
	if not wallet_from(ctx).can_afford(amount):
		return OUTCOME_NO_FUNDS
	return ""


static func _apply_channel(npc: NPCRuntime, channel_id: String, channel: Dictionary,
		ctx: Dictionary, result: Dictionary) -> void:
	var room: String = str(result["room_id"])
	if bool(channel.get("leaves_digital_record", false)):
		result["record_id"] = BeliefNet.create_record(RECORD_CHAT, PLAYER_ID, 0.0, room)
		result["effects"].append(EFFECT_DIGITAL_RECORD)
	if bool(channel.get("requires_privacy", false)):
		if _add_beliefs(result, npc.id, ctx.get("listeners", []), FACT_OVERHEARD,
				tunable("sobornos.certeza_escucha_llamada")) > 0:
			result["effects"].append(EFFECT_OVERHEARD)
	var in_person: bool = bool(channel.get("witness_risk", false))
	if in_person or channel_id == CHANNEL_IMMEDIATE:
		if _add_beliefs(result, npc.id, ctx.get("witnesses", []), FACT_WITNESSED,
				tunable("sobornos.certeza_testigo_en_persona")) > 0:
			result["effects"].append(EFFECT_WITNESSED)
	var cameras: Variant = ctx.get("cameras", [])
	if in_person and cameras is Array and not (cameras as Array).is_empty():
		result["footage_id"] = Security.register_camera_footage(room, _day(ctx),
				int(ctx.get("hour", GameClock.get_hour())))
		result["effects"].append(EFFECT_CAMERA)


static func _apply_outcome(npc: NPCRuntime, ctx: Dictionary, result: Dictionary) -> void:
	var room: String = str(result["room_id"])
	var crime_type: String = str(ctx.get("crime_type", CRIME_BRIBE))
	match str(result["outcome"]):
		OUTCOME_ACCEPTED:
			var amount: int = int(result["amount"])
			if wallet_from(ctx).spend_money(amount, MONEY_REASON):
				result["paid"] = amount
				result["effects"].append(EFFECT_PAID)
			if result["favour"] == FAVOUR_SILENCE:
				Blackmail.add_material(npc, Blackmail.KIND_BRIBED_SILENCE, crime_type, _day(ctx))
				result["effects"].append(EFFECT_BLACKMAIL)
		OUTCOME_SILENCE:
			_add_belief(result, npc.id, FACT_REMEMBERED,
					tunable("sobornos.certeza_silencio_memoria"), room)
			Blackmail.add_material(npc, Blackmail.KIND_SILENCE_MEMORY, crime_type, _day(ctx))
			result["effects"].append(EFFECT_BLACKMAIL)
		OUTCOME_NEUTRAL:
			_add_belief(result, npc.id, FACT_REFUSED, tunable("sobornos.certeza_rechazo_neutro"),
					room)
		OUTCOME_COUNTEROFFER:
			_add_belief(result, npc.id, FACT_COUNTERED, tunable("sobornos.certeza_contraoferta"),
					room)
			result["effects"].append(EFFECT_COUNTERED)
	if bool(result["insulting"]) and result["outcome"] != OUTCOME_DENOUNCED:
		_add_belief(result, npc.id, FACT_INSULTED, tunable("sobornos.certeza_oferta_insultante"),
				room)
		result["effects"].append(EFFECT_INSULTED)


## text_key del resultado; una oferta insultante rechazada sin más muestra la ofensa.
static func _set_text_keys(result: Dictionary) -> void:
	var insulted: bool = bool(result["insulting"])
	result["insult_text_key"] = TEXT_INSULTED if insulted else ""
	result["text_key"] = TEXT_INSULTED if insulted and result["outcome"] == OUTCOME_NEUTRAL \
			else OUTCOME_TEXT_KEYS[result["outcome"]]


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


static func _room(npc: NPCRuntime, ctx: Dictionary) -> String:
	return str(ctx["room_id"]) if ctx.has("room_id") else npc_location(npc)


static func _day(ctx: Dictionary) -> int:
	return int(ctx.get("day", GameClock.get_day()))
