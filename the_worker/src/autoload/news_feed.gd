# news_feed.gd — Capa compartida de noticias y sentimiento (§7.11): cada noticia produce a la vez un efecto de mercado y un efecto social.
# PROPIETARIO DE: noticias publicadas (sentimiento, peso social, enterramientos), escándalos consolidados, cola de noticias programadas, eventos de mercado activos (§19.10, §9.12) y campañas activistas ya anunciadas.
# ESCUCHA: day_advanced, quarter_closed, body_discovered, investigation_opened, strike_started, strike_resolved, audit_triggered, insider_pattern_detected
class_name NewsFeedSystem
extends Node

## CAPA COMPARTIDA (§7.11). Cada noticia guarda DOS magnitudes que nacen del mismo evento:
##  - `sentiment`: la lee Market (get_sentiment_contribution) → cotización.
##  - `suspicion`: peso social 0-100 (vigilancia). Contrato para BeliefNet (pendiente de su lado,
##    ver informe): sumar get_suspicion_contribution() (noticias sobre el jugador y sobre la
##    compañía) a la sospecha del jugador y recalcular al oír news_published / news_buried /
##    day_advanced. NPCDirector puede leer get_suspicion_about(npc_id) (escándalo fabricado o
##    campaña activista contra un personaje) y Security get_scandal_count() para la alerta.
## La señal `news_published(id, sentiment, is_scandal)` avisa a ambos cerebros a la vez. DECISIÓN:
## su primer argumento es el id ÚNICO de la noticia ("news_12"), no la clave de titular: Company
## indexa la prensa negativa por ese id y lo retira con news_buried(id). Para mostrarla,
## get_headline_key(id) (o get_news(id).headline_id) da la clave de strings.csv.
## Enterrar (bury) anula las DOS magnitudes y emite news_buried. Un escándalo sobre la compañía o
## el jugador que llega a `dias_consolidacion` jornadas sin enterrar queda consolidado: ya no se
## puede enterrar y cuenta para siempre en get_settled_scandal_count() (Market resta múltiplo;
## Tracking suma RUINA). La prensa enterrada puede reaparecer "por vía externa"
## (prob_reaparicion_diaria durante dias_ventana_reaparicion jornadas).
## Oyentes (todo síncrono): body_discovered → escándalo; investigation_opened → prensa solo si el
## disparador es is_public_news (investigations.json) o la gravedad alcanza gravedad_minima_prensa
## (la máxima), nunca para incidentes con titular propio (body_found, insider_pattern) ni para el
## fraude (fraud_at_month_close: su cara pública es la auditoría) → un hecho, un titular;
## strike_started/resolved → noticia y evento "strike"; audit_triggered(true) → fraude (fuente
## "audit": Market aplica su factor de falsificación y no el de escándalo);
## insider_pattern_detected → escándalo bursátil del jugador. Al abrir cada jornada anuncia las
## campañas activistas nuevas de Market (escándalo sobre su objetivo).
## Eventos de mercado (§9.12): se sortean por trimestre con el RNG del sistema, se programan con
## 1-3 jornadas de antelación (visibles para R25+ vía Market.get_upcoming_news) y al publicarse
## quedan activos con sus efectos sorteados: Company los lee con get_active_market_events() /
## get_event_multiplier() / get_event_addition(); Market lee multiple_multiplier. Los eventos con
## duration_days (viralización: dos semanas) sostienen su sentimiento mientras duran. Las manos
## pueden terminarlos (resolve_market_event, ends_on/until_resolved), mitigarlos (cargo
## mitigable_by) o amplificarlos (cargo amplifiable_by).

const SUBJECT_COMPANY := "company"
const SUBJECT_PLAYER := "player"
const SUBJECT_MARKET := "market"

const SOURCE_PUBLISH := "publish"
const SOURCE_FABRICATED := "fabricated"
const SOURCE_EVENT := "market_event"
const SOURCE_SCHEDULED := "scheduled"
const SOURCE_BODY := "body_discovered"
const SOURCE_INVESTIGATION := "investigation"
const SOURCE_STRIKE := "strike"
const SOURCE_AUDIT := "audit"
const SOURCE_INSIDER := "insider"
const SOURCE_RESURFACED := "resurfaced"
const SOURCE_CAMPAIGN := "activist_campaign"

const HEADLINE_BODY_FOUND := "NEWS_BODY_FOUND"
const HEADLINE_INVESTIGATION := "NEWS_INVESTIGATION_OPENED"
const HEADLINE_FRAUD := "NEWS_FRAUD_UNCOVERED"
const HEADLINE_CAMPAIGN := "NEWS_ACTIVIST_CAMPAIGN"
const INCIDENT_FRAUD := "fraud_at_month_close"
## Incidentes con cara pública propia (body_discovered, insider_pattern_detected, la auditoría del
## fraude): su caso nunca genera un segundo titular.
const DEDICATED_INCIDENTS: Array[String] = ["body_found", "insider_pattern", INCIDENT_FRAUD]
const TRIGGERS_KEY := "incident_triggers"
const PUBLIC_NEWS_KEY := "is_public_news"
const MULTIPLIER_SUFFIX := "_multiplier"
const STRIKE_EVENT_ID := "strike"
const CRIME_FRAMING := "framing"
const ID_PREFIX := "news_"
const RNG_SALT := "news_feed"
const NEUTRAL_MULTIPLIER := 1.0

var _events_catalogue: Array[Dictionary] = []
var _insider_cfg: Dictionary = {}
var _incident_triggers: Dictionary = {}

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _today: int = 0
var _next_id: int = 1
var _news: Array[Dictionary] = []
var _scheduled: Array[Dictionary] = []
var _active_events: Array[Dictionary] = []
var _settled_scandals: int = 0
var _announced_campaigns: Array[String] = []


func _ready() -> void:
	set_process(false)
	EventBus.day_advanced.connect(_on_day_advanced)
	EventBus.quarter_closed.connect(_on_quarter_closed)
	EventBus.body_discovered.connect(_on_body_discovered)
	EventBus.investigation_opened.connect(_on_investigation_opened)
	EventBus.strike_started.connect(_on_strike_started)
	EventBus.strike_resolved.connect(_on_strike_resolved)
	EventBus.audit_triggered.connect(_on_audit_triggered)
	EventBus.insider_pattern_detected.connect(_on_insider_pattern_detected)


func reset_for_new_run() -> void:
	_load_static_data()
	_rng.seed = GameClock.get_run_seed() ^ RNG_SALT.hash()
	_today = GameClock.get_day()
	_next_id = 1
	_news.clear()
	_scheduled.clear()
	_active_events.clear()
	_settled_scandals = 0
	_announced_campaigns.clear()
	roll_quarter_events(_quarter_of(_today))


# ═══ Interfaz §19.10 ══════════════════════════════════════════════════

## Publica una noticia sobre la compañía. Devuelve su id único.
func publish(headline_id: String, sentiment_delta: float, is_scandal: bool) -> String:
	return _publish(headline_id, sentiment_delta, is_scandal, SUBJECT_COMPANY, SOURCE_PUBLISH)


## Director de Comunicación (o quien él soborne). Anula sentimiento y peso social a la vez.
## Solo noticias negativas o escándalos aún no consolidados.
func bury(news_id: String, by_whom: String) -> bool:
	var item: Dictionary = _find(news_id)
	if item.is_empty() or by_whom.is_empty() or bool(item["buried"]) or bool(item["consolidated"]):
		return false
	if not bool(item["is_scandal"]) and float(item["sentiment"]) >= 0.0:
		return false
	item["buried"] = true
	item["buried_by"] = by_whom
	EventBus.news_buried.emit(news_id, by_whom)
	return true


## target "company": pieza favorable fabricada (manipulación de sentimiento).
## Otro target (id de personaje): escándalo ajeno fabricado; emite crime_committed("framing").
func fabricate(target: String, headline_id: String) -> String:
	if target.is_empty() or headline_id.is_empty():
		return ""
	if target == SUBJECT_COMPANY:
		return _publish(headline_id, _bf("noticias.sentimiento_fabricado_favorable"), false,
				SUBJECT_COMPANY, SOURCE_FABRICATED)
	var news_id: String = _publish(headline_id, _bf("noticias.sentimiento_fabricado_ajeno"), true,
			target, SOURCE_FABRICATED)
	EventBus.crime_committed.emit(CRIME_FRAMING, "", {"target": target, "news_id": news_id})
	return news_id


## Noticias vivas (no enterradas y con efecto aún perceptible), copias.
func get_active_news() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var threshold: float = _bf("noticias.umbral_actividad")
	for item: Dictionary in _news:
		if bool(item["buried"]):
			continue
		if absf(float(item["sentiment"])) >= threshold or float(item["suspicion"]) >= threshold:
			out.append(item.duplicate())
	return out


## Suma del sentimiento de las noticias no enterradas, acotada a ±noticias.sentimiento_max.
func get_sentiment_contribution() -> float:
	var total: float = 0.0
	for item: Dictionary in _news:
		if not bool(item["buried"]):
			total += float(item["sentiment"])
	var cap: float = _bf("noticias.sentimiento_max")
	return clampf(total, -cap, cap)


## Escándalos no enterrados publicados en las últimas `days` jornadas (hoy incluido).
func get_scandal_count(days: int) -> int:
	var count: int = 0
	for item: Dictionary in _news:
		if bool(item["is_scandal"]) and not bool(item["buried"]) and _today - int(item["day"]) < days:
			count += 1
	return count


## Decaimiento diario del sentimiento y del peso social; consolidación y reaparición.
func apply_daily_decay() -> void:
	var sentiment_decay: float = _bf("noticias.decaimiento_sentimiento_diario")
	var sustained_decay: float = _bf("noticias.decaimiento_sentimiento_evento_sostenido")
	var suspicion_decay: float = _bf("noticias.decaimiento_sospecha_diario")
	for item: Dictionary in _news:
		var decay: float = sustained_decay if _is_sustained(item) else sentiment_decay
		item["sentiment"] = float(item["sentiment"]) * decay
		item["suspicion"] = float(item["suspicion"]) * suspicion_decay
		item["age"] = int(item["age"]) + 1
		_try_consolidate(item)
	_resurface_buried()
	_prune_old_news()


func save_state() -> Dictionary:
	return {
		"today": _today, "next_id": _next_id, "news": _news.duplicate(true),
		"scheduled": _scheduled.duplicate(true), "active_events": _active_events.duplicate(true),
		"settled_scandals": _settled_scandals, "announced_campaigns": _announced_campaigns.duplicate(),
		"rng_seed": str(_rng.seed), "rng_state": str(_rng.state),
	}


func load_state(data: Dictionary) -> void:
	_load_static_data()
	_today = int(data.get("today", 0))
	_next_id = int(data.get("next_id", 1))
	_settled_scandals = int(data.get("settled_scandals", 0))
	_news = _typed_list(data.get("news", []))
	_scheduled = _typed_list(data.get("scheduled", []))
	_active_events = _typed_list(data.get("active_events", []))
	for item: Dictionary in _news:
		_normalise_news_item(item)
	_announced_campaigns.clear()
	for key: Variant in data.get("announced_campaigns", []):
		_announced_campaigns.append(str(key))
	_rng.seed = str(data.get("rng_seed", "0")).to_int()
	_rng.state = str(data.get("rng_state", "0")).to_int()


# ═══ Extensiones públicas ═════════════════════════════════════════════

## Como publish() con sujeto explícito: "player" (escándalo que implica al jugador: peso social
## noticias.sospecha_escandalo_jugador), "company", "market" o un id de personaje.
func publish_about(headline_id: String, sentiment_delta: float, is_scandal: bool,
		subject: String) -> String:
	return _publish(headline_id, sentiment_delta, is_scandal, subject, SOURCE_PUBLISH)


## Copia de la noticia (vacío si no existe o ya se purgó).
func get_news(news_id: String) -> Dictionary:
	var item: Dictionary = _find(news_id)
	return item.duplicate() if not item.is_empty() else {}


## Clave de strings.csv del titular de una noticia ("" si no existe). La UI la usa con tr().
func get_headline_key(news_id: String) -> String:
	return str(_find(news_id).get("headline_id", ""))


## Todas las noticias guardadas (incluidas enterradas), copias; para la UI y depuración.
func get_all_news() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in _news:
		out.append(item.duplicate())
	return out


## Efecto social sobre el jugador: noticias sobre él y sobre la compañía (vigilancia general).
func get_suspicion_contribution() -> float:
	return get_suspicion_about(SUBJECT_PLAYER) + get_suspicion_about(SUBJECT_COMPANY)


## Peso social vivo (no enterrado) de las noticias cuyo sujeto es `subject`.
func get_suspicion_about(subject: String) -> float:
	var total: float = 0.0
	for item: Dictionary in _news:
		if not bool(item["buried"]) and str(item["subject"]) == subject:
			total += float(item["suspicion"])
	return total


## Noticias negativas vivas (para el factor de riesgo de Company, §9.2).
func get_negative_news_count() -> int:
	var count: int = 0
	for item: Dictionary in get_active_news():
		if float(item["sentiment"]) < 0.0:
			count += 1
	return count


## Escándalos consolidados sin enterrar (permanentes, §9.10).
func get_settled_scandal_count() -> int:
	return _settled_scandals


static func is_corporate_subject(subject: String) -> bool:
	return subject == SUBJECT_COMPANY or subject == SUBJECT_PLAYER or subject == SUBJECT_MARKET


func get_current_day() -> int:
	return _today


## Abre la jornada `day_number`: decaimiento, fin de eventos y publicación de lo programado.
func advance_day(day_number: int) -> void:
	if day_number <= _today:
		return
	_today = day_number
	apply_daily_decay()
	_expire_events()
	_publish_due_scheduled()
	publish_campaign_news()


## Programa una noticia futura (conocida `lead_days` jornadas antes por los rangos >= min_rank).
func schedule_news(headline_id: String, day_number: int, sentiment_delta: float,
		is_scandal: bool, lead_days: int, min_rank: int) -> void:
	_scheduled.append({"headline_id": headline_id, "day": day_number, "lead_days": lead_days,
			"sentiment": sentiment_delta, "is_scandal": is_scandal, "event_id": "",
			"min_rank": min_rank, "effects": {}})


## Noticias programadas ya conocibles: 1 ≤ día − hoy ≤ min(days_ahead, antelación propia).
func get_scheduled_news(days_ahead: int) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for item: Dictionary in _scheduled:
		var distance: int = int(item["day"]) - _today
		if distance >= 1 and distance <= mini(days_ahead, int(item["lead_days"])):
			out.append(item.duplicate(true))
	return out


func get_all_scheduled_news() -> Array[Dictionary]:
	return _scheduled.duplicate(true)


## Sorteo de eventos de mercado del trimestre (§9.12) con el RNG sembrado. Devuelve ids.
func roll_quarter_events(quarter_number: int) -> Array[String]:
	var rolled: Array[String] = []
	var dpq: int = _days_per_quarter()
	var first_day: int = maxi((quarter_number - 1) * dpq + 1, _today + 1)
	var last_day: int = quarter_number * dpq
	for ev: Dictionary in _events_catalogue:
		var hit: bool = _rng.randf() < float(ev.get("probability_per_quarter", 0.0))
		var event_id: String = str(ev.get("id", ""))
		if not hit or first_day > last_day or _is_event_pending(event_id):
			continue
		_schedule_event(ev, _rng.randi_range(first_day, last_day))
		rolled.append(event_id)
	return rolled


## Eventos activos: [{id, start_day, end_day (-1 = hasta resolverse), effects, news_id}].
func get_active_market_events() -> Array[Dictionary]:
	return _active_events.duplicate(true)


## Producto de un efecto multiplicativo (revenue_multiplier, multiple_multiplier…) activo.
func get_event_multiplier(effect_key: String) -> float:
	var product: float = NEUTRAL_MULTIPLIER
	for ev: Dictionary in _active_events:
		var effects: Dictionary = ev.get("effects", {})
		if effects.has(effect_key):
			product *= float(effects[effect_key])
	return product


## Suma de un efecto aditivo (risk_factor_add, legal_costs_per_day, brand_strength_add…) activo.
func get_event_addition(effect_key: String) -> float:
	var total: float = 0.0
	for ev: Dictionary in _active_events:
		var effects: Dictionary = ev.get("effects", {})
		if effects.has(effect_key):
			total += float(effects[effect_key])
	return total


## Programa un evento concreto del catálogo para `day_number` (depuración F1, guiones de QA); si
## ya estaba programado, lo mueve. Falla si ya está activo. Efectos sorteados con el RNG del sistema.
func schedule_market_event(event_id: String, day_number: int) -> bool:
	var ev: Dictionary = _catalogue_event(event_id)
	if ev.is_empty() or day_number <= _today or not _active_event(event_id).is_empty():
		return false
	for item: Dictionary in _scheduled.duplicate():
		if str(item.get("event_id", "")) == event_id:
			_scheduled.erase(item)
	_schedule_event(ev, day_number)
	return true


## Termina antes de tiempo un evento activo que lo admite: el que declara ends_on (la causa debe
## coincidir: "supplier_change" para el cuero) o el que dura until_resolved. Devuelve si terminó.
func resolve_market_event(event_id: String, cause: String) -> bool:
	var ev: Dictionary = _active_event(event_id)
	var spec: Dictionary = _catalogue_event(event_id)
	if ev.is_empty() or cause.is_empty():
		return false
	var ends_on: String = str(spec.get("ends_on", ""))
	if ends_on.is_empty() and not bool(spec.get("until_resolved", false)):
		return false
	if not ends_on.is_empty() and cause != ends_on:
		return false
	_active_events.erase(ev)
	return true


## El cargo que figura en mitigable_by (Jefe de Compras, Dirección Jurídica) atenúa el evento una
## vez: cada efecto se acerca a neutro en noticias.factor_mitigacion_evento.
func mitigate_market_event(event_id: String, occupation_id: String) -> bool:
	var ev: Dictionary = _active_event(event_id)
	if ev.is_empty() or bool(ev.get("mitigated", false)):
		return false
	if occupation_id.is_empty() or str(_catalogue_event(event_id).get("mitigable_by", "")) != occupation_id:
		return false
	ev["effects"] = _scale_effects(ev.get("effects", {}), _bf("noticias.factor_mitigacion_evento"))
	ev["mitigated"] = true
	return true


## El cargo que figura en amplifiable_by (Director de Comunicación) multiplica una vez el
## sentimiento vivo de la noticia del evento por noticias.factor_amplificacion_evento.
func amplify_market_event(event_id: String, occupation_id: String) -> bool:
	var ev: Dictionary = _active_event(event_id)
	if ev.is_empty() or bool(ev.get("amplified", false)):
		return false
	if occupation_id.is_empty() or str(_catalogue_event(event_id).get("amplifiable_by", "")) != occupation_id:
		return false
	var item: Dictionary = _find(str(ev.get("news_id", "")))
	if item.is_empty():
		return false
	item["sentiment"] = float(item["sentiment"]) * _bf("noticias.factor_amplificacion_evento")
	ev["amplified"] = true
	return true


## Prensa de un caso (§7.11, §32.7): nunca los incidentes con cara pública propia; si no,
## is_public_news del disparador o gravedad ≥ noticias.gravedad_minima_prensa (la máxima).
func is_press_worthy(incident_type: String, severity: int) -> bool:
	if DEDICATED_INCIDENTS.has(incident_type):
		return false
	var trigger: Dictionary = _incident_triggers.get(incident_type, {})
	return bool(trigger.get(PUBLIC_NEWS_KEY, false)) \
			or severity >= _bi("noticias.gravedad_minima_prensa")


# ═══ Privado ══════════════════════════════════════════════════════════

func _load_static_data() -> void:
	_events_catalogue = Database.get_market_events()
	var insider: Variant = Database.get_market_params().get("insider_detection", {})
	_insider_cfg = insider as Dictionary if insider is Dictionary else {}
	_incident_triggers.clear()
	var triggers: Variant = Database.get_investigation_params().get(TRIGGERS_KEY, [])
	if triggers is Array:
		for trigger: Variant in triggers:
			if trigger is Dictionary:
				_incident_triggers[str((trigger as Dictionary).get("id", ""))] = trigger


func _bf(path: String) -> float:
	return Database.get_balance_float(path)


func _bi(path: String) -> int:
	return Database.get_balance_int(path)


func _days_per_quarter() -> int:
	return maxi(_bi("tiempo.jornadas_por_trimestre"), 1)


@warning_ignore("integer_division")
func _quarter_of(day_number: int) -> int:
	return maxi(day_number - 1, 0) / _days_per_quarter() + 1


func _publish(headline_id: String, sentiment: float, is_scandal: bool, subject: String,
		source: String) -> String:
	var news_id: String = ID_PREFIX + str(_next_id)
	_next_id += 1
	_news.append({
		"id": news_id, "headline_id": headline_id, "sentiment": sentiment,
		"initial_sentiment": sentiment, "is_scandal": is_scandal, "subject": subject,
		"suspicion": _social_weight(is_scandal, subject), "day": _today, "age": 0,
		"buried": false, "buried_by": "", "consolidated": false, "resurfaced": false,
		"source": source, "event_id": "",
	})
	EventBus.news_published.emit(news_id, sentiment, is_scandal)
	return news_id


## Peso social del escándalo según a quién implica.
func _social_weight(is_scandal: bool, subject: String) -> float:
	if not is_scandal:
		return 0.0
	match subject:
		SUBJECT_PLAYER:
			return _bf("noticias.sospecha_escandalo_jugador")
		SUBJECT_COMPANY, SUBJECT_MARKET:
			return _bf("noticias.sospecha_escandalo_general")
	return _bf("noticias.sospecha_fabricado_objetivo")


## Evita dos titulares iguales el mismo día por un mismo hecho (p. ej. auditoría + su caso).
func _published_today(headline_id: String) -> bool:
	for item: Dictionary in _news:
		if str(item["headline_id"]) == headline_id and int(item["day"]) == _today:
			return true
	return false


func _find(news_id: String) -> Dictionary:
	for item: Dictionary in _news:
		if str(item["id"]) == news_id:
			return item
	return {}


func _active_event(event_id: String) -> Dictionary:
	for ev: Dictionary in _active_events:
		if str(ev.get("id", "")) == event_id:
			return ev
	return {}


## Noticia de un evento activo con duración explícita en jornadas (§9.12: "durante dos semanas").
func _is_sustained(item: Dictionary) -> bool:
	var event_id: String = str(item.get("event_id", ""))
	if event_id.is_empty() or _active_event(event_id).is_empty():
		return false
	return _catalogue_event(event_id).has("duration_days")


## Multiplicadores (*_multiplier) se acercan a 1; aditivos se escalan.
static func _scale_effects(effects: Variant, factor: float) -> Dictionary:
	var out: Dictionary = {}
	if not effects is Dictionary:
		return out
	for key: Variant in (effects as Dictionary).keys():
		var value: float = float((effects as Dictionary)[key])
		if str(key).ends_with(MULTIPLIER_SUFFIX):
			out[key] = NEUTRAL_MULTIPLIER + (value - NEUTRAL_MULTIPLIER) * factor
		else:
			out[key] = value * factor
	return out


func _try_consolidate(item: Dictionary) -> void:
	if bool(item["consolidated"]) or bool(item["buried"]):
		return
	if int(item["age"]) < _bi("noticias.dias_consolidacion"):
		return
	item["consolidated"] = true
	if bool(item["is_scandal"]) and is_corporate_subject(str(item["subject"])):
		_settled_scandals += 1


## "La prensa suprimida puede reaparecer por vía externa": durante dias_ventana_reaparicion
## jornadas tras publicarse, cada noticia enterrada puede volver como noticia nueva.
func _resurface_buried() -> void:
	var chance: float = _bf("noticias.prob_reaparicion_diaria")
	var window: int = _bi("noticias.dias_ventana_reaparicion")
	var candidates: Array[Dictionary] = []
	for item: Dictionary in _news:
		if bool(item["buried"]) and not bool(item["resurfaced"]) and int(item["age"]) <= window:
			candidates.append(item)
	for item: Dictionary in candidates:
		if _rng.randf() < chance:
			item["resurfaced"] = true
			_publish(str(item["headline_id"]), float(item["initial_sentiment"]),
					bool(item["is_scandal"]), str(item["subject"]), SOURCE_RESURFACED)


func _prune_old_news() -> void:
	var keep_days: int = _bi("noticias.dias_retencion")
	var kept: Array[Dictionary] = []
	for item: Dictionary in _news:
		if int(item["age"]) <= keep_days:
			kept.append(item)
	_news = kept


func _is_event_pending(event_id: String) -> bool:
	for item: Dictionary in _scheduled:
		if str(item.get("event_id", "")) == event_id:
			return true
	for ev: Dictionary in _active_events:
		if str(ev.get("id", "")) == event_id:
			return true
	return false


func _schedule_event(ev: Dictionary, day_number: int) -> void:
	var lead: int = _rng.randi_range(int(_insider_cfg.get("news_lead_days_min", 0)),
			int(_insider_cfg.get("news_lead_days_max", 0)))
	_scheduled.append({
		"headline_id": str(ev.get("headline_key", "")), "day": day_number, "lead_days": lead,
		"sentiment": float(ev.get("sentiment_delta", 0.0)), "is_scandal": false,
		"event_id": str(ev.get("id", "")),
		"min_rank": int(_insider_cfg.get("upcoming_news_min_rank", 0)),
		"effects": _roll_effects(ev.get("effects", {})),
	})


## Rangos [a, b] se sortean una vez; los escalares se copian.
func _roll_effects(effects: Variant) -> Dictionary:
	var out: Dictionary = {}
	if not effects is Dictionary:
		return out
	for key: Variant in (effects as Dictionary).keys():
		var value: Variant = (effects as Dictionary)[key]
		if value is Array and (value as Array).size() == 2:
			out[str(key)] = _rng.randf_range(float(value[0]), float(value[1]))
		elif value is float or value is int:
			out[str(key)] = float(value)
	return out


func _publish_due_scheduled() -> void:
	var due: Array[Dictionary] = []
	var remaining: Array[Dictionary] = []
	for item: Dictionary in _scheduled:
		if int(item["day"]) <= _today:
			due.append(item)
		else:
			remaining.append(item)
	_scheduled = remaining
	for item: Dictionary in due:
		var from_event: bool = not str(item.get("event_id", "")).is_empty()
		var news_id: String = _publish(str(item["headline_id"]), float(item["sentiment"]),
				bool(item["is_scandal"]), SUBJECT_MARKET if from_event else SUBJECT_COMPANY,
				SOURCE_EVENT if from_event else SOURCE_SCHEDULED)
		if from_event:
			_find(news_id)["event_id"] = str(item["event_id"])
			_activate_event(str(item["event_id"]), item.get("effects", {}), news_id)


func _catalogue_event(event_id: String) -> Dictionary:
	for ev: Dictionary in _events_catalogue:
		if str(ev.get("id", "")) == event_id:
			return ev
	return {}


func _activate_event(event_id: String, effects: Dictionary, news_id: String) -> void:
	var ev: Dictionary = _catalogue_event(event_id)
	var end_day: int = -1
	if not bool(ev.get("until_resolved", false)):
		var duration: int = int(ev.get("duration_quarters", 0)) * _days_per_quarter()
		if ev.has("duration_days"):
			duration = int(ev["duration_days"])
		end_day = _today + duration - 1
	_active_events.append({"id": event_id, "start_day": _today, "end_day": end_day,
			"effects": effects.duplicate(), "news_id": news_id})


func _expire_events() -> void:
	var kept: Array[Dictionary] = []
	for ev: Dictionary in _active_events:
		if int(ev["end_day"]) < 0 or _today <= int(ev["end_day"]):
			kept.append(ev)
	_active_events = kept


func _typed_list(raw: Variant) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	if raw is Array:
		for entry: Variant in raw:
			if entry is Dictionary:
				out.append((entry as Dictionary).duplicate(true))
	return out


## Tras un JSON: enteros que llegaron como float y claves ausentes.
func _normalise_news_item(item: Dictionary) -> void:
	for key: String in ["day", "age"]:
		item[key] = int(item.get(key, 0))
	for key: String in ["buried", "consolidated", "resurfaced", "is_scandal"]:
		item[key] = bool(item.get(key, false))
	for key: String in ["sentiment", "initial_sentiment", "suspicion"]:
		item[key] = float(item.get(key, 0.0))
	item["event_id"] = str(item.get("event_id", ""))


## Campaña activista nueva de Market → escándalo sobre su objetivo: jugador (sentimiento y
## vigilancia) o rival (peso social en get_suspicion_about(rival)). Una vez por campaña; se llama
## al abrir cada jornada. Devuelve los ids publicados.
func publish_campaign_news() -> Array[String]:
	var live: Array[String] = []
	var published: Array[String] = []
	for campaign: Dictionary in Market.get_activist_campaigns():
		var key: String = "%s|%s|%d" % [campaign[MarketSystem.CAMPAIGN_INVESTOR],
				campaign[MarketSystem.CAMPAIGN_TARGET], int(campaign[MarketSystem.CAMPAIGN_SINCE])]
		live.append(key)
		if _announced_campaigns.has(key):
			continue
		published.append(_publish(HEADLINE_CAMPAIGN, _bf("noticias.sentimiento_campana_activista"),
				true, str(campaign[MarketSystem.CAMPAIGN_TARGET]), SOURCE_CAMPAIGN))
	_announced_campaigns = live
	return published


# ═══ Oyentes ══════════════════════════════════════════════════════════

func _on_day_advanced(day_number: int) -> void:
	advance_day(day_number)


func _on_quarter_closed(quarter_number: int) -> void:
	roll_quarter_events(quarter_number + 1)


func _on_body_discovered(_body_id: String, _room_id: String) -> void:
	_publish(HEADLINE_BODY_FOUND, _bf("noticias.sentimiento_cuerpo_hallado"), true,
			SUBJECT_COMPANY, SOURCE_BODY)


## Un hecho, un titular: solo los casos que is_press_worthy() admite (síncrono; un segundo caso
## genérico el mismo día no repite titular).
func _on_investigation_opened(_case_id: String, incident_type: String, severity: int) -> void:
	if not is_press_worthy(incident_type, severity) or _published_today(HEADLINE_INVESTIGATION):
		return
	_publish(HEADLINE_INVESTIGATION, _bf("noticias.sentimiento_investigacion_publica"), true,
			SUBJECT_COMPANY, SOURCE_INVESTIGATION)


func _on_strike_started() -> void:
	var ev: Dictionary = _catalogue_event(STRIKE_EVENT_ID)
	var news_id: String = _publish(str(ev.get("headline_key", "")),
			float(ev.get("sentiment_delta", 0.0)), false, SUBJECT_COMPANY, SOURCE_STRIKE)
	if not _is_event_pending(STRIKE_EVENT_ID):
		_activate_event(STRIKE_EVENT_ID, _roll_effects(ev.get("effects", {})), news_id)


func _on_strike_resolved(_resolution: String) -> void:
	var kept: Array[Dictionary] = []
	for ev: Dictionary in _active_events:
		if str(ev.get("id", "")) != STRIKE_EVENT_ID:
			kept.append(ev)
	_active_events = kept


func _on_audit_triggered(discrepancy_found: bool) -> void:
	if discrepancy_found:
		_publish(HEADLINE_FRAUD, _bf("noticias.sentimiento_fraude_aflorado"), true,
				SUBJECT_COMPANY, SOURCE_AUDIT)


## Patrón insider: escándalo bursátil que implica al jugador (§9.8, §7.11).
func _on_insider_pattern_detected(_operations_count: int) -> void:
	if not bool(_insider_cfg.get("is_public_news", false)):
		return
	_publish(str(_insider_cfg.get("headline_key", "")), _bf("noticias.sentimiento_escandalo_insider"),
			true, SUBJECT_PLAYER, SOURCE_INSIDER)
