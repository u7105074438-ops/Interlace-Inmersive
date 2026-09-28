# _office_loot.gd — Lo que se registra y se coge en la oficina: cajones, archivadores, expedientes de RR. HH., estanterías de material, correo interno, archivo de diseños y mesa de falsificación.
# PROPIETARIO DE: nada (estático; lo ya cogido y lo que quedó se recuerda con banderas "office.*" de PlayerState).
# ESCUCHA: nada.
class_name OfficeLoot
extends RefCounted

## · Cajón (§11.3, §12.4): ajeno siempre. Ruido de cajón (noise_emitted "drawer", ruido.radio_cajon)
##   al abrirlo, acto begin_act("drawer_forced") y, si termina, crime_committed("drawer_forced").
##   Contenido: los objetos de data.contains (una vez por partida) + una tirada diaria de
##   oficina.cajon.tabla (monedas sueltas, tentempié, papel, documento ajeno). Cada cosa que se
##   coge es un theft_small {value, item_id, owner}. Lo que se deja queda para hoy. Los cajones de
##   las viviendas (NightOps.get_house_type) los resuelve NightOps.loot_container.
## · Archivadores (archive_files, filing_cabinet): legal si es tu sala o tu puesto da acceso
##   (oficina.archivo.acceso_por_sala); si no, acto drawer_forced. Muestran lo que contienen
##   (auditoría: investigaciones abiertas antes de que te avisen, §22.10); llevarse sus documentos
##   (uno o todos) es siempre un acto theft_small. Pedidos extraviables (§23 order_filer):
##   confirmación + acto "sabotage" → crime_committed("sabotage") y su reputación baja.
## · Expedientes de RR. HH. (§22.6, §13.4): con el acceso del puesto → PERSONNEL. Si no, eliges
##   UNA persona (marcados, sala, nominados; oficina.expedientes.candidatos_max) y la intrusión
##   (drawer_forced) abre su expediente completo (PersonnelApp.open_full_file(id, "hr_intrusion"))
##   y, si tiene punto débil, te llevas su blackmail_file (theft_small).
## · Estantería de material (§6.5, §15.4 «~35 € diarios»): solo lo revendible
##   (oficina.material.vendibles); una unidad por jornada en todo el edificio; theft_small
##   {value, company_loss}. Lo demás (cuero, objetos de valor, químicos) no tiene comprador aquí.
## · Correo interno (§22.4, §23 mail_courier): rebuscar (acto y theft_small siempre, una vez al
##   día: dinero suelto, información temprana o nada) y enviar a un comprador el material robado.
## · Archivo de diseños (§23 junior_shoe_designer): sin IdeaPool.adopt_archive_idea (petición
##   abierta) solo se hojea; con él, acto idea_stolen + delito + idea presentable.
## · Mesa de falsificación (§5.3): exige la estampa. forged_authorization → Endgame.forge_authorization
##   (solo con el objetivo revelado); los demás productos se muestran sin uso todavía.

const B_DRAWER_TABLE := "oficina.cajon.tabla"
const B_COINS_MIN := "oficina.cajon.monedas_min"
const B_COINS_MAX := "oficina.cajon.monedas_max"
const B_DRAWER_NOISE := "ruido.radio_cajon"
const B_CHEAP_ITEM := "oficina.material.objeto_barato"
const B_MATERIAL_ITEMS := "oficina.material.objeto_por_material"
const B_SELLABLE := "oficina.material.vendibles"
const B_RESALE := "oficina.material.factor_reventa"
const B_MAIL_TABLE := "oficina.correo.tabla"
const B_MAIL_MIN := "oficina.correo.dinero_min"
const B_MAIL_MAX := "oficina.correo.dinero_max"
const B_ARCHIVE_ACCESS := "oficina.archivo.acceso_por_sala"
const B_MISPLACE_REP := "oficina.archivo.reputacion_pedidos"
const B_MISPLACE_DAYS := "oficina.archivo.enfriamiento_pedidos_dias"
const B_TARGETS_MAX := "oficina.archivo.objetivos_max"
const B_HR_CANDIDATES := "oficina.expedientes.candidatos_max"
const B_DESIGN_TEMPLATE := "oficina.diseno.plantilla"
const B_DESIGN_REMEMBERS := "oficina.diseno.recuerda"
const B_STAMP := "oficina.falsificacion.estampa"
const NOISE_DRAWER := "drawer"
const CRIME_DRAWER := "drawer_forced"
const CRIME_THEFT := "theft_small"
const CRIME_SABOTAGE := "sabotage"
const CRIME_FORGERY := "forgery"
const CRIME_IDEA := "idea_stolen"
const COINS := "coins"
const MAIL_OPENED := "mail_opened"
const NOTHING := "nothing"
const INFO := "info"
const CASH := "cash"
const KIND_DOCUMENT := "document"
const AUTHORIZATION := "forged_authorization"
const ADOPT_METHOD := "adopt_archive_idea"
const HR_REASON := "hr_intrusion"
const APP_PERSONNEL := "personnel"
const DOCS_AUDIT := "audit_cases"
const DOCS_COMPLAINTS := "complaints"
const DOCS_KEY_FORMAT := "OFFICE_ARCHIVE_DOCS_%s"
const LOOT_SEPARATOR := ":"
const SOLD_METHOD := "sold"
## Marca «ya hoy» del material: global, no por sala.
const SUPPLIES_KEY := "supplies"
## Claves de punto débil que dicen «ninguno» (NPC_WEAK_NONE, NPC_WEAK_NONE_UNBRIBABLE...).
const NO_WEAKNESS_PREFIX := "NPC_WEAK_NONE"


# ─── Cajones ──────────────────────────────────────────────────

static func use_drawer(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if not NightOps.get_house_type(OfficeKit.base_room(item.room_id)).is_empty():
		await _house_drawer(item, player, ctx)
		return
	var owner: String = OfficeKit.owner_of(item)
	var key: String = "drawer." + item.interact_id
	var left: Array = OfficeKit.get_list(key)
	if OfficeKit.used_today(key) and left.is_empty():
		OfficeKit.say(ctx, "OFFICE_DRAWER_EMPTY_TODAY", [OfficeKit.npc_name(owner)])
		return
	var room: String = item.room_id
	var drawer_id: String = item.interact_id
	var data: Dictionary = item.data.duplicate(true)
	if not await OfficeKit.confirm_if_watched(ctx):
		return
	OfficeKit.noise(player, B_DRAWER_NOISE, NOISE_DRAWER)
	if not await OfficeKit.run_act(ctx, player, CRIME_DRAWER, "cajon", false):
		return
	OfficeKit.commit(CRIME_DRAWER, room, {"owner": owner, "drawer_id": drawer_id})
	OfficeKit.spend_minutes("cajon")
	var loot: Array = left if OfficeKit.used_today(key) else drawer_loot(drawer_id, data)
	OfficeKit.mark_today(key)
	await offer_loot(ctx, loot, {"room": room, "owner": owner, "key": key, "unique": "taken." + drawer_id,
			"recorded": true, "title": "OFFICE_DRAWER_TITLE", "empty": "OFFICE_DRAWER_NOTHING"})


## Botín de hoy: lo único de los datos aún no cogido + una tirada de oficina.cajon.tabla.
static func drawer_loot(drawer_id: String, data: Dictionary) -> Array:
	var out: Array = unique_contents(drawer_id, data)
	var r: RandomNumberGenerator = OfficeKit.rng("drawer." + drawer_id)
	var pick: String = OfficeKit.roll_table(Database.get_balance(B_DRAWER_TABLE) as Array, r)
	if pick == COINS:
		out.append(COINS + LOOT_SEPARATOR + str(r.randi_range(Database.get_balance_int(B_COINS_MIN),
				Database.get_balance_int(B_COINS_MAX))))
	elif pick != NOTHING and Database.has_item(pick):
		out.append(pick)
	return out


static func unique_contents(container_id: String, data: Dictionary) -> Array:
	var taken: Array = OfficeKit.get_list("taken." + container_id)
	var out: Array = []
	for raw: Variant in data.get("contains", []):
		if Database.has_item(str(raw)) and not taken.has(str(raw)):
			out.append(str(raw))
	return out


## Ofrece lo encontrado: coger todo, una cosa o dejarlo. spec = {room, owner, key, unique, title, empty}.
static func offer_loot(ctx: Dictionary, loot: Array, spec: Dictionary) -> void:
	if loot.is_empty():
		OfficeKit.set_list(str(spec["key"]), [])
		OfficeKit.say(ctx, str(spec["empty"]), [OfficeKit.npc_name(str(spec["owner"]))])
		return
	var single: bool = loot.size() == 1
	var labels: Array = [] if single else [{"text_key": "OFFICE_TAKE_ALL", "args": [loot.size()]}]
	for entry: Variant in loot:
		labels.append({"text_key": "OFFICE_TAKE_ITEM", "args": [loot_name(str(entry))]})
	labels.append("OFFICE_LEAVE_IT")
	var index: int = await OfficeKit.choose(ctx, str(spec["title"]), "OFFICE_LOOT_BODY", labels,
			[OfficeKit.npc_name(str(spec["owner"]))])
	if single and index >= 0:
		index += 1
	var chosen: Array = loot.duplicate() if index == 0 else ([loot[index - 1]] if index > 0 and index <= loot.size() else [])
	var left: Array = loot.duplicate()
	var names: PackedStringArray = []
	for entry: Variant in chosen:
		if take_loot(str(entry), spec, ctx):
			left.erase(entry)
			names.append(loot_name(str(entry)))
	OfficeKit.set_list(str(spec["key"]), left)
	if not names.is_empty():
		OfficeKit.good(ctx, "OFFICE_TOOK", [", ".join(names)], OfficeKit.SFX_CASH)


static func loot_name(entry: String) -> String:
	if entry.begins_with(COINS + LOOT_SEPARATOR):
		return OfficeKit.tr_key("OFFICE_COINS") % int(entry.get_slice(LOOT_SEPARATOR, 1))
	return OfficeKit.item_name(entry)


## Coge una cosa (theft_small con su valor). false si no cabe. spec.recorded: el acto que abrió el
## contenedor (drawer_forced) ya dejó la incidencia object_missing; el robo no la duplica (§12.3).
static func take_loot(entry: String, spec: Dictionary, ctx: Dictionary) -> bool:
	var room: String = str(spec["room"])
	var record: bool = not bool(spec.get("recorded", false))
	if entry.begins_with(COINS + LOOT_SEPARATOR):
		var amount: int = int(entry.get_slice(LOOT_SEPARATOR, 1))
		PlayerState.add_money(amount, "drawer_cash")
		OfficeKit.commit(CRIME_THEFT, room, {"value": amount, "item_id": CASH, "owner": spec["owner"],
				"leaves_record": record})
		return true
	if not OfficeKit.can_take(entry) or not PlayerState.add_item(entry):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(entry)])
		return false
	var item: ItemData = Database.get_item(entry)
	OfficeKit.commit(CRIME_THEFT, room, {"value": OfficeKit.item_value(entry), "item_id": entry,
			"owner": spec["owner"], "document": item != null and InventoryRules.get_kind(item) == KIND_DOCUMENT,
			"leaves_record": record})
	var unique_key: String = str(spec.get("unique", ""))
	if not unique_key.is_empty():
		var taken: Array = OfficeKit.get_list(unique_key)
		taken.append(entry)
		OfficeKit.set_list(unique_key, taken)
	return true


## Cajón de una vivienda (§4.3): lo resuelve la operación nocturna en curso.
static func _house_drawer(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var ops: NightOps = OfficeKit.sim(ctx, "NightOps", NightOps.GROUP) as NightOps
	if ops == null or not ops.is_active():
		OfficeKit.refuse(ctx, "OFFICE_HOUSE_NO_OPERATION")
		return
	var drawer_id: String = item.interact_id
	if _house_container_empty(ops, drawer_id):
		OfficeKit.say(ctx, "OFFICE_DRAWER_NOTHING", [OfficeKit.tr_key("OFFICE_SOMEONE")])
		return
	OfficeKit.noise(player, B_DRAWER_NOISE, NOISE_DRAWER)
	if not await OfficeKit.run_act(ctx, player, "burglary", "cajon", false):
		return
	var result: Dictionary = ops.loot_container(drawer_id)
	_warn_witnesses(ctx, result.get("witnesses", []))
	if not bool(result.get("ok", false)):
		OfficeKit.refuse(ctx, NightOps.reason_key(str(result.get("reason", ""))))
		return
	var names: PackedStringArray = []
	for item_id: Variant in result.get("items", []):
		names.append(OfficeKit.item_name(str(item_id)))
	if names.is_empty():
		OfficeKit.say(ctx, "OFFICE_DRAWER_NOTHING", [OfficeKit.tr_key("OFFICE_SOMEONE")])
		return
	OfficeKit.good(ctx, "OFFICE_TOOK", [", ".join(names)], OfficeKit.SFX_CASH)


## El contenedor de la vivienda ya se vació (saqueado y sin restos).
static func _house_container_empty(ops: NightOps, container_id: String) -> bool:
	for c: Dictionary in ops.get_containers():
		if str(c.get("id", "")) == container_id:
			return bool(c.get("looted", false)) and int(c.get("left", 0)) <= 0
	return false


## Aviso si el saqueo tuvo testigos (el residente despierto o la seguridad privada).
static func _warn_witnesses(ctx: Dictionary, witnesses: Variant) -> void:
	if not witnesses is Array or (witnesses as Array).is_empty():
		return
	var names: PackedStringArray = []
	for id: Variant in witnesses:
		names.append(OfficeKit.npc_name(str(id)))
	OfficeKit.refuse(ctx, "OFFICE_HOUSE_WITNESSED", [", ".join(names)])


# ─── Archivadores ─────────────────────────────────────────────

## Registrar un archivador es parte del trabajo en tu sala o con el acceso de tu puesto.
static func archive_is_legal(item: Interactable) -> bool:
	if OfficeKit.is_own_room(item.room_id):
		return true
	var by_room: Dictionary = Database.get_balance(B_ARCHIVE_ACCESS) as Dictionary
	for access: Variant in by_room.get(OfficeKit.base_room(item.room_id), []):
		if OfficeKit.has_access(str(access)):
			return true
	return false


static func use_archive(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var room: String = item.room_id
	var archive_id: String = item.interact_id
	var data: Dictionary = item.data.duplicate(true)
	if archive_is_legal(item):
		OfficeKit.play(player, "drawer")
	else:
		if not await OfficeKit.confirm_if_watched(ctx, "archivo"):
			return
		OfficeKit.noise(player, B_DRAWER_NOISE, NOISE_DRAWER)
		if not await OfficeKit.run_act(ctx, player, CRIME_DRAWER, "archivo", false):
			return
		OfficeKit.commit(CRIME_DRAWER, room, {"archive_id": archive_id})
	OfficeKit.spend_minutes("archivo")
	var lines: Array[String] = archive_lines(data)
	OfficeInfo.note_lines(lines)
	await _archive_menu(ctx, player, {"room": room, "id": archive_id, "data": data}, lines)


## Lo que se lee en el archivador según data.documents.
static func archive_lines(data: Dictionary) -> Array[String]:
	var documents: String = str(data.get("documents", ""))
	var out: Array[String] = []
	match documents:
		DOCS_AUDIT:
			out = OfficeInfo.case_lines()
			if out.is_empty():
				out.append(OfficeKit.tr_key("OFFICE_ARCHIVE_NO_CASES"))
		DOCS_COMPLAINTS:
			out.append(OfficeKit.tr_key("OFFICE_ARCHIVE_COMPLAINTS") % Company.get_discontent())
		_:
			var key: String = DOCS_KEY_FORMAT % documents.to_upper()
			out.append(OfficeKit.tr_key(key) if OfficeKit.tr_key(key) != key else OfficeKit.tr_key("OFFICE_ARCHIVE_GENERIC"))
	return out


## Menú del archivador. archive = {room, id, data}. Llevarse papeles es un acto (theft_small)
## aunque registrar sea legal; «todo» si hay más de uno.
static func _archive_menu(ctx: Dictionary, player: Node, archive: Dictionary, lines: Array[String]) -> void:
	var archive_id: String = str(archive["id"])
	var loot: Array = unique_contents(archive_id, archive["data"])
	var misplace: bool = bool((archive["data"] as Dictionary).get("can_misplace", false))
	var offset: int = 1 if loot.size() > 1 else 0
	var labels: Array = [{"text_key": "OFFICE_TAKE_ALL", "args": [loot.size()]}] if offset == 1 else []
	for entry: Variant in loot:
		labels.append({"text_key": "OFFICE_TAKE_ITEM", "args": [OfficeKit.item_name(str(entry))]})
	if misplace:
		labels.append("OFFICE_ARCHIVE_MISPLACE")
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_ARCHIVE_TITLE", OfficeKit.INFO_BODY, labels,
			[OfficeKit.bullets(lines)])
	if index >= 0 and index < loot.size() + offset:
		var chosen: Array = loot.duplicate() if offset == 1 and index == 0 else [loot[index - offset]]
		await _take_documents(ctx, player, str(archive["room"]), archive_id, chosen)
	elif misplace and index == loot.size() + offset:
		await misplace_orders(ctx, player, str(archive["room"]))


static func _take_documents(ctx: Dictionary, player: Node, room: String, archive_id: String, chosen: Array) -> void:
	if not await OfficeKit.run_act(ctx, player, CRIME_THEFT, "archivo"):
		return
	var spec: Dictionary = {"room": room, "owner": "", "key": "archive." + archive_id, "unique": "taken." + archive_id}
	var names: PackedStringArray = []
	for entry: Variant in chosen:
		if take_loot(str(entry), spec, ctx):
			names.append(OfficeKit.item_name(str(entry)))
	if not names.is_empty():
		OfficeKit.good(ctx, "OFFICE_TOOK", [", ".join(names)])


## Extraviar los pedidos de alguien (§22.7, §23 order_filer): sabotaje con su reputación.
## Irreversible contra un compañero: confirmación (§13.7) y acto "sabotage" antes del delito.
static func misplace_orders(ctx: Dictionary, player: Node, room: String) -> void:
	if OfficeKit.days_since("misplace") < Database.get_balance_int(B_MISPLACE_DAYS):
		OfficeKit.refuse(ctx, "OFFICE_ARCHIVE_MISPLACE_SOON")
		return
	var targets: Array[String] = pick_targets(Database.get_balance_int(B_TARGETS_MAX))
	var index: int = await OfficeKit.choose(ctx, "OFFICE_ARCHIVE_TITLE", "OFFICE_ARCHIVE_MISPLACE_BODY", target_labels(targets))
	if index < 0 or index >= targets.size():
		return
	var target: String = targets[index]
	if not await OfficeKit.confirm(ctx, "OFFICE_ARCHIVE_TITLE", "OFFICE_ARCHIVE_MISPLACE_CONFIRM",
			"OFFICE_ARCHIVE_MISPLACE_GO", [OfficeKit.npc_name(target)]):
		return
	if not await OfficeKit.run_act(ctx, player, CRIME_SABOTAGE, "archivo"):
		return
	NPCDirector.modify_npc_reputation(target, Database.get_balance_float(B_MISPLACE_REP), "orders_misplaced")
	OfficeKit.commit(CRIME_SABOTAGE, room, {"target": target, "kind": "orders_misplaced"})
	OfficeKit.mark_today("misplace")
	OfficeKit.note(OfficeKit.NOTE_FILES, "OFFICE_NOTE_MISPLACED", [OfficeKit.npc_name(target)])
	OfficeKit.good(ctx, "OFFICE_ARCHIVE_MISPLACED", [OfficeKit.npc_name(target)])


## Opciones «objetivo» (nombre) + Cerrar.
static func target_labels(targets: Array[String]) -> Array:
	var labels: Array = []
	for npc_id: String in targets:
		labels.append({"text_key": "OFFICE_TARGET", "args": [OfficeKit.npc_name(npc_id)]})
	labels.append("OFFICE_CLOSE")
	return labels


## Objetivos: los marcados en PERSONNEL y después los compañeros de tu sala (activos).
static func pick_targets(limit: int) -> Array[String]:
	var out: Array[String] = []
	for npc_id: String in PlayerState.get_marked_targets():
		if NPCDirector.is_active(npc_id) and out.size() < limit:
			out.append(npc_id)
	var occ: OccupationData = PlayerState.get_occupation()
	for npc: NPCRuntime in NPCDirector.get_all_npcs():
		if out.size() >= limit or occ == null:
			break
		if NPCDirector.is_active(npc.id) and OfficeKit.base_room(npc.home_room) == occ.office_room and not out.has(npc.id):
			out.append(npc.id)
	return out


# ─── Expedientes de RR. HH. ───────────────────────────────────

static func use_personnel(item: Interactable, player: Node, ctx: Dictionary) -> void:
	if OfficeKit.has_access(PlayerStateSystem.ACCESS_FULL_FILES):
		OfficeKit.good(ctx, "OFFICE_HR_LEGAL")
		var view: UIRoot = OfficeKit.ui(ctx)
		if view != null:
			view.open_computer({"app": APP_PERSONNEL})
		return
	var key: String = "hr." + item.interact_id
	if OfficeKit.used_today(key):
		OfficeKit.say(ctx, "OFFICE_HR_DONE_TODAY")
		return
	var room: String = item.room_id
	var candidates: Array[String] = hr_candidates(Database.get_balance_int(B_HR_CANDIDATES))
	if candidates.is_empty():
		OfficeKit.say(ctx, "OFFICE_HR_NOBODY")
		return
	var index: int = await OfficeKit.choose(ctx, "OFFICE_HR_TITLE", "OFFICE_HR_PICK_BODY", target_labels(candidates))
	if index < 0 or index >= candidates.size():
		return
	var target: String = candidates[index]
	if not await OfficeKit.confirm_if_watched(ctx):
		return
	OfficeKit.noise(player, B_DRAWER_NOISE, NOISE_DRAWER)
	if not await OfficeKit.run_act(ctx, player, CRIME_DRAWER, "expedientes", false):
		return
	OfficeKit.commit(CRIME_DRAWER, room, {"files": "personnel", "target": target})
	OfficeKit.mark_today(key)
	OfficeKit.spend_minutes("expedientes")
	await _read_one_file(ctx, target, room)


## Lee el expediente completo de una persona (§13.4) y, si tiene punto débil, su nota.
static func _read_one_file(ctx: Dictionary, target: String, room: String) -> void:
	PersonnelApp.open_full_file(target, HR_REASON)
	var read: Array[String] = [target]
	var lines: Array[String] = [OfficeKit.tr_key("OFFICE_HR_READ") % OfficeKit.npc_name(target)]
	var leverage: String = take_blackmail_file(read, room)
	if not leverage.is_empty():
		lines.append(OfficeKit.tr_key("OFFICE_HR_LEVERAGE") % OfficeKit.npc_name(leverage))
	elif has_weakness(target):
		lines.append(OfficeKit.tr_key("OFFICE_INVENTORY_FULL") % OfficeKit.item_name("blackmail_file"))
	await OfficeKit.show_lines(ctx, "OFFICE_HR_TITLE", lines)


## A quién se puede buscar: marcados, compañeros de sala y nominados, sin expediente completo aún.
static func hr_candidates(limit: int) -> Array[String]:
	var pool: Array[String] = pick_targets(limit)
	for named: NPCData in Database.get_all_named_npcs():
		if not pool.has(named.id):
			pool.append(named.id)
	var out: Array[String] = []
	for npc_id: String in pool:
		if out.size() < limit and NPCDirector.is_active(npc_id) and not PlayerState.has_full_file(npc_id):
			out.append(npc_id)
	return out


static func has_weakness(npc_id: String) -> bool:
	var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
	return npc != null and not npc.weakness_key.is_empty() and not npc.weakness_key.begins_with(NO_WEAKNESS_PREFIX)


## Se lleva la nota comprometedora del primero con punto débil (blackmail_file). Devuelve su id.
static func take_blackmail_file(read: Array[String], room: String) -> String:
	for npc_id: String in read:
		if not has_weakness(npc_id):
			continue
		var npc: NPCRuntime = NPCDirector.get_npc(npc_id)
		var doc: ItemData = OfficeKit.item_copy("blackmail_file", {"npc_id": npc_id,
				"weakness_key": npc.weakness_key, "stackable": false})
		if not PlayerState.add_item_data(doc):
			return ""
		OfficeKit.commit(CRIME_THEFT, room, {"value": 0, "item_id": doc.id, "owner": npc_id, "document": true})
		return npc_id
	return ""


# ─── Material de oficina ──────────────────────────────────────

## Objeto de la estantería: por material (cuero, suelas), el barato si su reventa es menor.
static func shelf_item(data: Dictionary) -> String:
	var by_material: Dictionary = Database.get_balance(B_MATERIAL_ITEMS) as Dictionary
	var material: String = str(data.get("material", ""))
	if by_material.has(material):
		return str(by_material[material])
	var items: Array = data.get("items", [])
	var item_id: String = str(items[0]) if not items.is_empty() else str(Database.get_balance(B_CHEAP_ITEM))
	if data.has("resale_value") and int(data["resale_value"]) < OfficeKit.item_value(item_id):
		return str(Database.get_balance(B_CHEAP_ITEM))
	return item_id


## Solo el material que alguien compra (oficina.material.vendibles) se lleva aquí; cuero, suelas,
## objetos de valor o químicos no tienen comprador en la oficina: se mira y no se toca. La parte
## diaria es global (una unidad por jornada en todo el edificio, §15.4 «~35 € diarios»).
static func use_supplies(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var key: String = SUPPLIES_KEY
	var item_id: String = shelf_item(item.data)
	if not is_sellable(item_id):
		OfficeKit.play(player, "check_watch")
		OfficeKit.say(ctx, "OFFICE_SUPPLIES_NO_BUYER", [OfficeKit.item_name(item_id)])
		return
	if OfficeKit.used_today(key):
		OfficeKit.say(ctx, "OFFICE_SUPPLIES_DONE_TODAY")
		return
	if not OfficeKit.can_take(item_id):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(item_id)])
		return
	var room: String = item.room_id
	if not await OfficeKit.run_act(ctx, player, CRIME_THEFT, "material"):
		return
	if not PlayerState.add_item(item_id):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(item_id)])
		return
	var value: int = OfficeKit.item_value(item_id)
	OfficeKit.mark_today(key)
	OfficeKit.commit(CRIME_THEFT, room, {"value": value, "company_loss": value, "item_id": item_id})
	OfficeKit.spend_minutes("material")
	OfficeKit.good(ctx, "OFFICE_SUPPLIES_TAKEN", [OfficeKit.item_name(item_id), value])


static func is_sellable(item_id: String) -> bool:
	return (Database.get_balance(B_SELLABLE) as Array).has(item_id)


# ─── Correo interno ───────────────────────────────────────────

## Unidades de material revendible que llevas y lo que pagan.
static func sellable() -> Dictionary:
	var units: int = 0
	var money: int = 0
	var factor: float = Database.get_balance_float(B_RESALE)
	for raw: Variant in Database.get_balance(B_SELLABLE) as Array:
		var count: int = PlayerState.get_item_count(str(raw)) if PlayerState.is_carrying(str(raw)) else 0
		units += count
		money += roundi(float(count * OfficeKit.item_value(str(raw))) * factor)
	return {"units": units, "money": money}


static func use_mail(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var key: String = "mail." + item.interact_id
	var sale: Dictionary = sellable()
	var options: Array[String] = []
	var labels: Array = []
	if not OfficeKit.used_today(key):
		options.append(INFO)
		labels.append("OFFICE_MAIL_INTERCEPT")
	if int(sale["units"]) > 0:
		options.append(CASH)
		labels.append({"text_key": "OFFICE_MAIL_SELL", "args": [sale["units"], sale["money"]]})
	if options.is_empty():
		OfficeKit.say(ctx, "OFFICE_MAIL_DONE_TODAY")
		return
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_MAIL_TITLE", "OFFICE_MAIL_BODY", labels)
	if index < 0 or index >= options.size():
		return
	if options[index] == CASH:
		sell_supplies(ctx)
	else:
		await intercept_mail(key, item.room_id, player, ctx)


## Envía a un comprador todo el material revendible que llevas.
static func sell_supplies(ctx: Dictionary) -> int:
	var sale: Dictionary = sellable()
	for raw: Variant in Database.get_balance(B_SELLABLE) as Array:
		while PlayerState.is_carrying(str(raw)) and PlayerState.dispose_item(str(raw), SOLD_METHOD):
			pass
	PlayerState.add_money(int(sale["money"]), "supplies_resale")
	OfficeKit.spend_minutes("venta")
	OfficeKit.good(ctx, "OFFICE_MAIL_SOLD", [sale["units"], sale["money"]], OfficeKit.SFX_CASH)
	return int(sale["money"])


static func intercept_mail(key: String, room: String, player: Node, ctx: Dictionary) -> void:
	if not await OfficeKit.run_act(ctx, player, CRIME_THEFT, "correo"):
		return
	OfficeKit.mark_today(key)
	OfficeKit.spend_minutes("correo")
	var r: RandomNumberGenerator = OfficeKit.rng(key)
	var pick: String = OfficeKit.roll_table(Database.get_balance(B_MAIL_TABLE) as Array, r)
	var amount: int = r.randi_range(Database.get_balance_int(B_MAIL_MIN), Database.get_balance_int(B_MAIL_MAX)) \
			if pick == CASH else 0
	OfficeKit.commit(CRIME_THEFT, room, {"value": amount, "item_id": CASH if amount > 0 else MAIL_OPENED,
			"source": "internal_mail"})
	match pick:
		CASH:
			PlayerState.add_money(amount, "mail_cash")
			OfficeKit.good(ctx, "OFFICE_MAIL_CASH", [amount], OfficeKit.SFX_CASH)
		INFO:
			var lines: Array[String] = OfficeInfo.early_lines(1, key)
			if lines.is_empty():
				lines.append(OfficeKit.tr_key("OFFICE_EARLY_NOTHING"))
			OfficeInfo.note_lines(lines)
			await OfficeKit.show_lines(ctx, "OFFICE_MAIL_TITLE", lines)
		_:
			OfficeKit.say(ctx, "OFFICE_MAIL_NOTHING")


# ─── Diseños antiguos y falsificación ─────────────────────────

## Sin IdeaPool.adopt_archive_idea el diseño no se puede presentar: se hojea (legal) y se explica,
## en vez de hacer correr un riesgo sin premio. Con él: acto idea_stolen + delito + idea presentable.
static func use_design_archive(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var rememberer: String = str(Database.get_balance(B_DESIGN_REMEMBERS))
	if not IdeaPool.has_method(ADOPT_METHOD):
		OfficeKit.play(player, "check_watch")
		OfficeKit.spend_minutes("lectura")
		OfficeKit.say(ctx, "OFFICE_DESIGN_BROWSE", [OfficeKit.npc_name(rememberer)])
		return
	var key: String = "design." + item.interact_id
	if OfficeKit.used_today(key):
		OfficeKit.say(ctx, "OFFICE_DESIGN_DONE_TODAY")
		return
	var room: String = item.room_id
	if not await OfficeKit.run_act(ctx, player, CRIME_IDEA, "diseno"):
		return
	OfficeKit.mark_today(key)
	OfficeKit.spend_minutes("diseno")
	var idea_id: String = str(IdeaPool.call(ADOPT_METHOD, str(Database.get_balance(B_DESIGN_TEMPLATE)), rememberer))
	OfficeKit.commit(CRIME_IDEA, room, {"source": "design_archive", "idea_id": idea_id, "value": 0})
	if idea_id.is_empty():
		push_warning("OfficeLoot: adopt_archive_idea returned no idea")
		return
	OfficeKit.note("ideas", "OFFICE_NOTE_DESIGN", [OfficeKit.npc_name(rememberer)])
	OfficeKit.good(ctx, "OFFICE_DESIGN_IDEA", [OfficeKit.npc_name(rememberer)])


static func use_forgery(item: Interactable, player: Node, ctx: Dictionary) -> void:
	var stamp: String = str(Database.get_balance(B_STAMP))
	if not PlayerState.has_item(stamp):
		OfficeKit.refuse(ctx, "OFFICE_FORGE_NO_STAMP", [OfficeKit.item_name(stamp)])
		return
	var products: Array[String] = []
	var labels: Array = []
	for raw: Variant in item.data.get("produces", []):
		products.append(str(raw))
		labels.append(forge_label(str(raw)))
	labels.append("OFFICE_CLOSE")
	var index: int = await OfficeKit.choose(ctx, "OFFICE_FORGE_TITLE", "OFFICE_FORGE_BODY", labels)
	if index < 0 or index >= products.size():
		return
	await forge(products[index], item.room_id, player, ctx)


## Solo la autorización tiene uso hoy (Endgame); el resto se ve pero no se puede hacer.
static func forge_label(product: String) -> Dictionary:
	var key: String = "OFFICE_FORGE_MAKE"
	if product != AUTHORIZATION:
		key = "OFFICE_FORGE_NO_USE"
	elif not Endgame.is_objective_revealed():
		key = "OFFICE_FORGE_LOCKED"
	return {"text_key": key, "args": [OfficeKit.item_name(product)], "disabled": key != "OFFICE_FORGE_MAKE"}


static func forge(product: String, room: String, player: Node, ctx: Dictionary) -> void:
	if product == AUTHORIZATION and PlayerState.get_reputation() < Endgame.forgery_reputation_required():
		OfficeKit.refuse(ctx, "OFFICE_FORGE_LOW_REPUTATION", [roundi(Endgame.forgery_reputation_required())])
		return
	if not OfficeKit.can_take(product):
		OfficeKit.refuse(ctx, "OFFICE_INVENTORY_FULL", [OfficeKit.item_name(product)])
		return
	if not await OfficeKit.confirm(ctx, "OFFICE_FORGE_TITLE", "OFFICE_FORGE_CONFIRM", "OFFICE_FORGE_GO",
			[OfficeKit.item_name(product)]):
		return
	if not await OfficeKit.run_act(ctx, player, CRIME_FORGERY, "falsificacion"):
		return
	OfficeKit.spend_minutes("falsificacion")
	if product == AUTHORIZATION:
		var result: Dictionary = Endgame.forge_authorization()
		if not bool(result.get("ok", false)):
			OfficeKit.refuse(ctx, Endgame.reason_key(str(result.get("reason", ""))))
			return
	else:
		PlayerState.add_item(product)
		OfficeKit.commit(CRIME_FORGERY, room, {"document": product})
	OfficeKit.good(ctx, "OFFICE_FORGED", [OfficeKit.item_name(product)])
