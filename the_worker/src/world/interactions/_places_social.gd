# _places_social.gd — Los corrillos (§7.7): fumadores en la calle (cada 2 h, sin cámaras), futbolín de P4 (información barata) y la mesa del clan en la cafetería (comida): escuchar lo que se cuenta y plantar un rumor.
# PROPIETARIO DE: nada (los vínculos, participantes y rumores son de SocialGraph; las creencias, de BeliefNet; «ya hoy», banderas places.*).
# ESCUCHA: nada.
class_name PlacesSocial
extends RefCounted

## · Participantes = SocialGraph.get_gathering_participants(corrillo) en activo (quien salió a fumar
##   en las últimas 2 h, quien pasó por el futbolín en la franja, quien come hoy en la cafetería). Sin
##   nadie, se dice cuándo se reúne. La mesa del clan solo tiene gente en la franja de comida
##   (lugares.corrillos.franja_clan); la propagación de ese corrillo ocurre igual al acabar la
##   franja (SocialGraph), esté o no el jugador.
## · ESCUCHAR (lugares.corrillos.minutos.<corrillo>): creencias que sostienen los participantes sobre
##   otros (BeliefNet), como mucho lugares.corrillos.lineas.<corrillo> líneas; en los corrillos de
##   verdades_primero (fumadores: sin cámaras, «aquí se dicen las verdades») primero lo que creen
##   de TI y, además, las parejas clandestinas de los presentes (material de chantaje). Si sobra
##   sitio: alguien que anda con una idea, un puesto vacante y el humor de la plantilla. Cada
##   línea queda en el cuaderno. Te quedas el número del primero (contacto proximity).
## · PLANTAR UN RUMOR (una vez por jornada y corrillo): a quién (tus objetivos marcados y los
##   presentes), qué (lugares.rumores.hechos) y confirmación; se lo cuentas al participante más
##   sociable: SocialGraph.inject_rumour_about (emite crime_committed rumour_planted) y se propaga en
##   la próxima sesión del corrillo. Un rumor sobre alguien dirige hacia él las investigaciones.

const T_SMOKING := "smoking_spot"
const T_FOOSBALL := "foosball_table"
const T_CLAN := "clan_table"
const TYPES: Array[String] = [T_SMOKING, T_FOOSBALL, T_CLAN]
const K_GROUP := "group"
const K_GATHERING := "corrillo"
const B_SMOKERS := "lugares.corrillos.fumadores"
const B_CLAN_BAND := "lugares.corrillos.franja_clan"
const B_LINES := "lugares.corrillos.lineas."
const B_MINUTES := "lugares.corrillos.minutos."
const B_TRUTHS := "lugares.corrillos.verdades_primero"
const B_FACTS := "lugares.rumores.hechos"
const B_CERTAINTY := "lugares.rumores.certeza"
const B_MAX_SUBJECTS := "lugares.rumores.max_sujetos"
const TITLE_FORMAT := "PLACES_GATHERING_TITLE_%s"
const EMPTY_FORMAT := "PLACES_GATHERING_EMPTY_%s"
const PLANT_KEY := "rumour."
const OPT_LISTEN := 0
const OPT_PLANT := 1
const NAMES_SHOWN := 3
const CONTACT_SOURCE := "proximity"
const NOTE_CATEGORY := "gossip"
const ANIM_CHAT := "chat"
const PLAYER_ID := "player"
const PAIR_JOIN := ":"
const IDEA_SALT := "gossip.idea"


static func handles(kind: String) -> bool:
	return TYPES.has(kind)


static func interact(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var gathering: String = gathering_of(item)
	if item.interact_type == T_CLAN and GameClock.get_current_band() != str(Database.get_balance(B_CLAN_BAND)):
		PlacesKit.say(ctx, "PLACES_CLAN_EMPTY")
		return
	var people: Array[String] = participants(gathering)
	if people.is_empty():
		PlacesKit.say(ctx, EMPTY_FORMAT % gathering.to_upper())
		return
	var planted: bool = PlacesKit.used_today(PLANT_KEY + gathering)
	var options: Array = [{"text_key": "PLACES_GATHERING_LISTEN", "args": [roundi(minutes_of(gathering))]},
			{"text_key": "PLACES_GATHERING_PLANT", "disabled": planted}, "PLACES_CLOSE"]
	var index: int = await PlacesKit.choose(ctx, TITLE_FORMAT % gathering.to_upper(), "PLACES_GATHERING_BODY",
			options, [PlacesKit.names_of(people, NAMES_SHOWN), people.size()])
	if index == OPT_LISTEN:
		await listen(player, ctx, gathering, people)
	elif index == OPT_PLANT:
		await plant(player, ctx, gathering, people)


## Corrillo del interactivo: data.group (fumadores), data.corrillo (mesas del keeper) o fumadores.
static func gathering_of(item: Interactable) -> String:
	var own: String = str(item.data.get(K_GROUP, item.data.get(K_GATHERING, "")))
	return own if not own.is_empty() else str(Database.get_balance(B_SMOKERS))


static func participants(gathering: String) -> Array[String]:
	var out: Array[String] = []
	for npc_id: String in SocialGraph.get_gathering_participants(gathering):
		if NPCDirector.is_active(npc_id):
			out.append(npc_id)
	return out


static func minutes_of(gathering: String) -> float:
	var path: String = B_MINUTES + gathering
	return Database.get_balance_float(path) if Database.has_balance(path) else 0.0


static func lines_of(gathering: String) -> int:
	var path: String = B_LINES + gathering
	return Database.get_balance_int(path) if Database.has_balance(path) else 1


# ─── Escuchar ─────────────────────────────────────────────────

static func listen(player: Node, ctx: Dictionary, gathering: String, people: Array[String]) -> void:
	PlacesKit.play(player, ANIM_CHAT)
	GameClock.advance_minutes(minutes_of(gathering))
	var contact: bool = PlayerState.add_contact(people[0], CONTACT_SOURCE)
	var truths: bool = PlacesKit.bal_strings(B_TRUTHS).has(gathering)
	var lines: Array[String] = gossip_lines(people, lines_of(gathering), truths)
	if contact:
		PlacesKit.good(ctx, "PLACES_GOSSIP_CONTACT", [PlacesKit.npc_name(people[0])], PlacesKit.SFX_CHAT)
	if lines.is_empty():
		PlacesKit.say(ctx, "PLACES_GOSSIP_NOTHING", [], ToastStack.KIND_INFO, PlacesKit.SFX_CHAT)
		return
	for line: String in lines:
		PlacesKit.note(NOTE_CATEGORY, "PLACES_NOTE_GOSSIP", [line])
	await PlacesKit.show_lines(ctx, "PLACES_GOSSIP_TITLE", lines)


## Lo que cuentan los presentes (creencias sobre otros); con `truths_first`, antes lo tuyo.
static func gossip_lines(people: Array[String], limit: int, truths_first: bool) -> Array[String]:
	var about_you: Array[Belief] = []
	var about_others: Array[Belief] = []
	for holder: String in people:
		for b: Belief in BeliefNet.get_beliefs_held_by(holder):
			if b.is_record or b.subject == b.holder:
				continue
			if b.subject == PLAYER_ID:
				about_you.append(b)
			elif NPCDirector.get_npc(b.subject) != null:
				about_others.append(b)
	var by_certainty: Callable = func(a: Belief, b: Belief) -> bool: return a.certainty > b.certainty
	about_you.sort_custom(by_certainty)
	about_others.sort_custom(by_certainty)
	var ordered: Array[Belief] = []
	ordered.append_array(about_you if truths_first else about_others)
	ordered.append_array(about_others if truths_first else about_you)
	var out: Array[String] = []
	for b: Belief in ordered.slice(0, maxi(limit, 0)):
		out.append(gossip_line(b))
	for line: String in extra_lines(people, truths_first):
		if out.size() < limit:
			out.append(line)
	return out


## Lo que también se comenta cuando las creencias no llenan la charla: parejas clandestinas (solo
## donde se dicen las verdades), quién anda con una idea, puestos vacantes y el humor de la plantilla.
static func extra_lines(people: Array[String], truths: bool) -> Array[String]:
	var out: Array[String] = []
	if truths:
		out.append_array(couple_lines(people))
	var ideas: Array[Dictionary] = IdeaPool.get_signalling_npcs()
	if not ideas.is_empty():
		var pick: Dictionary = ideas[PlacesKit.rng(IDEA_SALT).randi_range(0, ideas.size() - 1)]
		out.append(PlacesKit.tr_key("PLACES_GOSSIP_IDEA") % PlacesKit.npc_name(str(pick.get("npc_id", ""))))
	var vacancies: Array[String] = Company.get_vacant_seats()
	var occ: OccupationData = Database.get_occupation(vacancies[0]) if not vacancies.is_empty() else null
	if occ != null:
		out.append(PlacesKit.tr_key("PLACES_GOSSIP_VACANCY") % PlacesKit.tr_key(occ.name_key))
	out.append(PlacesKit.tr_key("PLACES_GOSSIP_MOOD") % [Company.get_discontent(), Company.get_strike_threshold()])
	return out


## Parejas clandestinas entre los presentes (material de chantaje, §7.7), sin repetir.
static func couple_lines(people: Array[String]) -> Array[String]:
	var out: Array[String] = []
	var seen: Array[String] = []
	for npc_id: String in people:
		for link: Dictionary in SocialGraph.get_blackmail_links(npc_id):
			var partner: String = str(link.get("to", "")) if str(link.get("from", "")) == npc_id else str(link.get("from", ""))
			var key: String = npc_id + PAIR_JOIN + partner if npc_id < partner else partner + PAIR_JOIN + npc_id
			if partner.is_empty() or seen.has(key):
				continue
			seen.append(key)
			out.append(PlacesKit.tr_key("PLACES_GOSSIP_COUPLE") % [PlacesKit.npc_name(npc_id), PlacesKit.npc_name(partner)])
	return out


static func gossip_line(b: Belief) -> String:
	var fact: String = PlacesKit.tr_key(BeliefNetSystem.fact_label_key(b.fact))
	if b.subject == PLAYER_ID:
		return PlacesKit.tr_key("PLACES_GOSSIP_ABOUT_YOU") % [PlacesKit.npc_name(b.holder), fact]
	return PlacesKit.tr_key("PLACES_GOSSIP_LINE") % [PlacesKit.npc_name(b.holder), PlacesKit.npc_name(b.subject), fact]


# ─── Plantar un rumor ─────────────────────────────────────────

static func plant(player: Node, ctx: Dictionary, gathering: String, people: Array[String]) -> void:
	var listener: String = people[0]
	var subject: String = await pick_subject(ctx, rumour_subjects(people, listener), listener)
	if subject.is_empty():
		return
	var fact: String = await pick_fact(ctx, subject)
	if fact.is_empty():
		return
	var args: Array = [PlacesKit.npc_name(listener), PlacesKit.npc_name(subject), fact_label(fact)]
	if not await PlacesKit.confirm(ctx, "PLACES_RUMOUR_TITLE", "PLACES_RUMOUR_CONFIRM", "PLACES_RUMOUR_GO", args):
		return
	PlacesKit.play(player, ANIM_CHAT)
	PlacesKit.spend_minutes("rumor")
	var id: String = SocialGraph.inject_rumour_about(listener, subject, fact, Database.get_balance_float(B_CERTAINTY))
	if id.is_empty():
		PlacesKit.refuse(ctx, "PLACES_RUMOUR_FAILED")
		return
	PlacesKit.mark_today(PLANT_KEY + gathering)
	PlacesKit.good(ctx, "PLACES_RUMOUR_PLANTED", args, PlacesKit.SFX_CHAT)


## Sujetos posibles: objetivos marcados y los presentes, sin quien escucha (tope max_sujetos).
static func rumour_subjects(people: Array[String], listener: String) -> Array[String]:
	var candidates: Array[String] = PlayerState.get_marked_targets()
	candidates.append_array(people)
	var out: Array[String] = []
	for npc_id: String in candidates:
		if npc_id != listener and not out.has(npc_id) and NPCDirector.is_active(npc_id):
			out.append(npc_id)
	return out.slice(0, Database.get_balance_int(B_MAX_SUBJECTS))


static func pick_subject(ctx: Dictionary, subjects: Array[String], listener: String) -> String:
	if subjects.is_empty():
		PlacesKit.refuse(ctx, "PLACES_RUMOUR_NOBODY")
		return ""
	var options: Array = []
	for npc_id: String in subjects:
		options.append({"text_key": "PLACES_RUMOUR_SUBJECT", "args": [PlacesKit.npc_name(npc_id)]})
	options.append("PLACES_CLOSE")
	var index: int = await PlacesKit.choose(ctx, "PLACES_RUMOUR_TITLE", "PLACES_RUMOUR_WHO", options,
			[PlacesKit.npc_name(listener)])
	return subjects[index] if index >= 0 and index < subjects.size() else ""


static func pick_fact(ctx: Dictionary, subject: String) -> String:
	var facts: Array[String] = PlacesKit.bal_strings(B_FACTS)
	var options: Array = []
	for fact: String in facts:
		options.append({"text_key": "PLACES_RUMOUR_FACT", "args": [fact_label(fact)]})
	options.append("PLACES_CLOSE")
	var index: int = await PlacesKit.choose(ctx, "PLACES_RUMOUR_TITLE", "PLACES_RUMOUR_WHAT", options,
			[PlacesKit.npc_name(subject)])
	return facts[index] if index >= 0 and index < facts.size() else ""


static func fact_label(fact: String) -> String:
	return PlacesKit.tr_key(BeliefNetSystem.fact_label_key(fact))
