# _office_info.gd — Información temprana y cotilleo para el módulo de oficina: borradores de prensa, orden del día de Aurora, memorandos de investigación, vacantes, visitas y creencias ajenas.
# PROPIETARIO DE: nada (solo lecturas de NewsFeed, IdeaPool, Security, Company, Market, NPCDirector y BeliefNet).
# ESCUCHA: nada.
class_name OfficeInfo
extends RefCounted

## «Información temprana de coste nulo» (§23 copy_operator, §22.6 fotocopiadora central, §22.10
## auditoría interna). Cada fuente devuelve líneas YA traducidas; early_lines() las mezcla con el
## azar reproducible de la jornada y se queda con `limit`. Todo lo leído se apunta en el cuaderno.

const B_DAYS_AHEAD := "oficina.copiadora.dias_adelanto"
const INCIDENT_FORMAT := "INCIDENT_%s"
const HOUR_FORMAT := "%02d:00"
const NOTE_CATEGORY := "files"
const PLAYER_ID := "player"
const PERCENT := 100.0
## Denominador mínimo de la variación porcentual (evita dividir por cero).
const MIN_PRICE := 0.01


## Líneas de información temprana (mezcladas por jornada), como mucho `limit`.
static func early_lines(limit: int, salt: String) -> Array[String]:
	var pool: Array[String] = []
	pool.append_array(news_lines())
	pool.append_array(case_lines())
	pool.append_array(vacancy_lines())
	pool.append_array(buyer_lines())
	var meeting: String = meeting_line()
	if not meeting.is_empty():
		pool.append(meeting)
	var r: RandomNumberGenerator = OfficeKit.rng(salt)
	for i: int in range(pool.size() - 1, 0, -1):
		var j: int = r.randi_range(0, i)
		var tmp: String = pool[i]
		pool[i] = pool[j]
		pool[j] = tmp
	return pool.slice(0, maxi(limit, 0))


## Notas de prensa que aún no han salido (NewsFeed.get_scheduled_news).
static func news_lines() -> Array[String]:
	var out: Array[String] = []
	for item: Dictionary in NewsFeed.get_scheduled_news(Database.get_balance_int(B_DAYS_AHEAD)):
		out.append(TranslationServer.translate("OFFICE_EARLY_NEWS") % [int(item.get("day", 0)),
				TranslationServer.translate(str(item.get("headline_id", "")))])
	return out


## Orden del día de la próxima reunión Aurora.
static func meeting_line() -> String:
	var day: int = IdeaPool.get_next_meeting_day(GameClock.get_day())
	var schedule: Dictionary = IdeaPool.get_meeting_schedule()
	return TranslationServer.translate("OFFICE_EARLY_MEETING") % [day, HOUR_FORMAT % int(schedule.get("hour", 0))]


## Memorandos de investigaciones abiertas (y si el jugador figura en la lista corta).
static func case_lines() -> Array[String]:
	var out: Array[String] = []
	for inv: Investigation in Security.get_active_investigations():
		var key: String = "OFFICE_EARLY_CASE_YOU" if inv.suspects.has(PLAYER_ID) else "OFFICE_EARLY_CASE"
		out.append(TranslationServer.translate(key) % [incident_name(inv.incident_type), inv.phase])
	return out


static func incident_name(incident_type: String) -> String:
	var key: String = INCIDENT_FORMAT % incident_type.to_upper()
	var text: String = TranslationServer.translate(key)
	return text if text != key else TranslationServer.translate("OFFICE_UNKNOWN_INCIDENT")


## Ofertas de empleo: sillas vacantes (Company).
static func vacancy_lines() -> Array[String]:
	var out: Array[String] = []
	for occupation_id: String in Company.get_vacant_seats():
		var occ: OccupationData = Database.get_occupation(occupation_id)
		if occ != null:
			out.append(TranslationServer.translate("OFFICE_EARLY_VACANCY") % TranslationServer.translate(occ.name_key))
	return out


## Pases de visita impresos: compradores que vienen hoy.
static func buyer_lines() -> Array[String]:
	var out: Array[String] = []
	for visit: Dictionary in Company.get_buyers_today():
		out.append(TranslationServer.translate("OFFICE_EARLY_BUYER") % [str(visit.get("name", "")), TranslationServer.translate(str(visit.get("firm_key", "")))])
	return out


## Cotizaciones del terminal: precio y variación desde ayer.
static func quote_line() -> String:
	var history: Array[float] = Market.get_price_history(2)
	var price: float = Market.get_price()
	var before: float = history[0] if history.size() > 1 else price
	var delta: float = (price - before) / maxf(absf(before), MIN_PRICE) * PERCENT
	return TranslationServer.translate("OFFICE_QUOTE") % [price, delta]


## Confianza de los inversores (escucha en la sala de inversores).
static func investor_lines() -> Array[String]:
	var out: Array[String] = []
	for investor: InvestorData in Market.get_investors():
		out.append(TranslationServer.translate("OFFICE_INVESTOR_MOOD") % [investor.name, Market.get_investor_confidence(investor.id)])
	return out


## Una creencia de alguien de la sala sobre otro (rumor escuchado); "" si nadie habla de nada.
static func gossip_line(room_id: String, salt: String) -> String:
	var heard: Array[Belief] = []
	for npc: NPCRuntime in NPCDirector.get_npcs_in_room(room_id):
		for b: Belief in BeliefNet.get_beliefs_held_by(npc.id):
			if not b.is_record and b.subject != b.holder and not b.subject.is_empty():
				heard.append(b)
	if heard.is_empty():
		return ""
	var b: Belief = heard[OfficeKit.rng(salt).randi_range(0, heard.size() - 1)]
	var subject: String = TranslationServer.translate("OFFICE_YOU") if b.subject == PLAYER_ID else OfficeKit.npc_name(b.subject)
	return TranslationServer.translate("OFFICE_GOSSIP_BELIEF") % [OfficeKit.npc_name(b.holder), subject,
			TranslationServer.translate(BeliefNetSystem.fact_label_key(b.fact))]


## Apunta cada línea en el cuaderno (categoría archivos) para no depender de la memoria.
static func note_lines(lines: Array[String]) -> void:
	for line: String in lines:
		OfficeKit.note(NOTE_CATEGORY, "OFFICE_NOTE_LINE", [line])
