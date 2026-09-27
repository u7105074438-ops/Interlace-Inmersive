# audio_case.gd — Cuerpo de test_audio: degradación del hilo musical, efectos, ambientes, subtítulos y bandas sin hilo.
# PROPIETARIO DE: nada.
# ESCUCHA: EventBus.subtitle_posted y EventBus.noise_emitted (conexiones temporales para comprobarlos).
extends TestCase

const RISING: Array[String] = ["jitter", "wow", "flutter", "sour", "atonal", "dropouts_per_s",
		"cuts_per_s", "hiss"]
const FALLING: Array[String] = ["tempo", "lowpass_hz"]
const BAND_PROBES: Dictionary = {0.0: 0, 10.0: 0, 25.0: 0, 25.5: 1, 26.0: 1, 40.0: 1, 50.0: 1,
		51.0: 2, 65.0: 2, 75.0: 2, 76.0: 3, 90.0: 3, 100.0: 3}
const RENDER_SECONDS := 12.0
const WAIT_STEP_S := 0.1
const WAIT_STEPS := 300
const FAKE_NPC_SOURCE := "extends Node2D\nvar npc_id: String = \"\"\nvar occupation_id: String = \"\"\n"
const TEST_HZ := 440.0
const STRETCH_TEMPO := 0.9
const STRETCH_LOOP_S := 6.0
const STRETCH_OUT_S := 4
const FAKE_SWITCHES := 16
const PROFILE_DIR := "user://test_audio_profile"
const TRITONE := 6

var _subs: Array[Dictionary] = []
var _noises: Array[Dictionary] = []
var _rate: int = 0


func run_case() -> void:
	new_run()
	_rate = AudioTuning.integer("audio.frecuencia_muestreo")
	check(_rate > 0, "audio sample rate comes from balance")
	_check_degradation_bands()
	_check_degradation_monotonic()
	_check_sfx_buffers()
	_check_ambience_buffers()
	_check_noise_classification()
	_check_offline_render()
	_check_time_stretch()
	_check_deck_swaps()
	_check_wav_writer()
	_check_npc_listener()
	_check_voice_priority()
	_check_epilogue_choice()
	await _run_director_checks()


func _run_director_checks() -> void:
	EventBus.subtitle_posted.connect(_on_subtitle)
	EventBus.noise_emitted.connect(_on_noise)
	SaveSystem.set_storage_dir(PROFILE_DIR)
	var director: AudioDirector = AudioDirector.new()
	add_child(director)
	await wait_frames(2)
	await _check_director_events(director)
	await _check_single_director(director)
	await _check_floor_arrangements(director)
	await _check_stale_swap(director)
	await _check_arrival_by_elevator(director)
	await _check_guard_radio(director)
	await _check_music_pieces(director)
	director.queue_free()
	await wait_frames(2)
	await _check_non_blocking_exit()
	DirAccess.remove_absolute(SaveSystem.get_profile_path())
	SaveSystem.set_storage_dir("")
	EventBus.noise_emitted.disconnect(_on_noise)
	EventBus.subtitle_posted.disconnect(_on_subtitle)


func _on_subtitle(key: String, position: Vector2, importance: int) -> void:
	_subs.append({"key": key, "position": position, "importance": importance})


func _on_noise(position: Vector2, radius: float, source: String) -> void:
	_noises.append({"position": position, "radius": radius, "source": source})


# ─── Degradación (§14.9) ─────────────────────────────────────────

func _check_degradation_bands() -> void:
	var table: Dictionary = AudioTuning.dict("audio.degradacion")
	var levels: Array = table.get("niveles", [])
	check_eq(levels.size(), 4, "four degradation levels in balance")
	for s: float in BAND_PROBES.keys():
		check_eq(int(MuzakSynth.degradation(s)["band"]), int(BAND_PROBES[s]), "suspicion %s → band" % s)
	for band: int in levels.size():
		var d: Dictionary = MuzakSynth.degradation([10.0, 40.0, 65.0, 90.0][band])
		var lv: Dictionary = levels[band]
		check_near(float(d["tempo"]), float(lv["tempo"]), 0.0001, "band %d tempo from balance" % band)
		check_near(float(d["atonal"]), float(lv["atonales"]), 0.0001, "band %d atonality" % band)
	var d0: Dictionary = MuzakSynth.degradation(10.0)
	var d1: Dictionary = MuzakSynth.degradation(40.0)
	var d2: Dictionary = MuzakSynth.degradation(65.0)
	var d3: Dictionary = MuzakSynth.degradation(90.0)
	check(float(d0["tempo"]) == 1.0 and float(d0["sour"]) == 0.0 and float(d0["dropouts_per_s"]) == 0.0,
			"0-25: normal playback")
	check(float(d1["tempo"]) < 1.0 and float(d1["sour"]) > 0.0 and float(d1["dropouts_per_s"]) == 0.0
			and float(d1["jitter"]) == 0.0, "26-50: slightly slower, occasional sour note, no silences")
	check(float(d2["jitter"]) > 0.0 and float(d2["wow"]) > float(d1["wow"])
			and float(d2["dropouts_per_s"]) > 0.0, "51-75: worn tape (irregular tempo, wow, silences)")
	var clean3: float = 1.0 - float(d3["atonal"]) - float(d3["sour"])
	check(float(d3["atonal"]) >= 0.4 and clean3 <= 0.35 and float(d3["cuts_per_s"]) > 0.0,
			"76-100: near-atonal and cuts out intermittently")
	check(clean3 >= 0.25, "76-100: enough clean notes that the tune stays recognisable (%.2f)" % clean3)
	check(float(d1["jump_fade_s"]) > 0.0 and float(d1["jump_lead_s"]) > float(d1["jump_fade_s"]),
			"tempo changes stretch each beat (crossfade ends before the next beat)")
	var shifts: Array = table.get("atonal_semitonos", [])
	var tritones: int = shifts.count(TRITONE) + shifts.count(-TRITONE)
	check(not shifts.is_empty() and float(tritones) / float(shifts.size()) <= 0.2,
			"atonal jumps weighted to ±1/±2 semitones (few tritones)")


func _check_degradation_monotonic() -> void:
	var prev: Dictionary = MuzakSynth.degradation(0.0)
	var ok: bool = true
	for s: int in range(1, 101):
		var d: Dictionary = MuzakSynth.degradation(float(s))
		for key: String in RISING:
			ok = ok and float(d[key]) >= float(prev[key])
		for key: String in FALLING:
			ok = ok and float(d[key]) <= float(prev[key])
		ok = ok and int(d["band"]) >= int(prev["band"])
		prev = d
	check(ok, "degradation is monotonic in suspicion (0..100)")


# ─── Efectos y ambientes ─────────────────────────────────────────

func _check_sfx_buffers() -> void:
	var empty: Array[String] = []
	var missing_sub: Array[String] = []
	for id: String in SfxBank.ids():
		var buf: PackedFloat32Array = SfxBank.render(id, _rate)
		var p: float = SynthDSP.peak(buf)
		if buf.is_empty() or p < 0.05 or is_nan(p) or p > 1.0:
			empty.append(id)
		var key: String = SfxBank.subtitle_key(id)
		if not key.is_empty() and tr(key) == key:
			missing_sub.append(key)
	check(empty.is_empty(), "every SFX id renders a non-empty, non-clipping buffer %s" % str(empty))
	check(missing_sub.is_empty(), "every SFX subtitle key is localised %s" % str(missing_sub))
	for band: Dictionary in AudioTuning.all_bands():
		var alarm: String = SfxBank.alarm_for_band(str(band["id"]))
		check(SfxBank.has_sfx(alarm) and alarm.ends_with(str(band["id"])), "alarm varies per band: %s" % alarm)
	check(SfxBank.render("no_such_sound", _rate).is_empty(), "unknown SFX id renders nothing")
	var a: AudioStreamWAV = SfxBank.get_stream("card_beep", _rate)
	check(a != null and SfxBank.get_stream("card_beep", _rate) == a, "SFX streams are cached for the process")


func _check_ambience_buffers() -> void:
	var bpm: float = AudioTuning.num("audio.ambiente.fabrica_bpm")
	var bad: Array[String] = []
	for id: String in Ambience.IDS:
		var buf: PackedFloat32Array = Ambience.render(id, _rate, bpm)
		if buf.size() < _rate or SynthDSP.peak(buf) <= 0.0:
			bad.append(id)
		elif absf(buf[0] - buf[buf.size() - 1]) > _max_step(buf) * 1.05:
			bad.append(id + "(seam)")
	check(bad.is_empty(), "every ambience renders a seamless loop %s" % str(bad))
	var unknown: Array[String] = []
	for band: Dictionary in AudioTuning.all_bands():
		if not Ambience.IDS.has(str(band.get("ambient_sound", ""))):
			unknown.append(str(band.get("ambient_sound", "")))
	for sound: String in _room_ambient_sounds():
		if not Ambience.IDS.has(sound):
			unknown.append(sound)
	check(unknown.is_empty(), "every ambient_sound in the data has a recipe %s" % str(unknown))


## Mayor salto entre muestras consecutivas dentro del bucle (la costura no debe superarlo).
func _max_step(buf: PackedFloat32Array) -> float:
	var m: float = 0.0
	for i: int in range(1, buf.size()):
		m = maxf(m, absf(buf[i] - buf[i - 1]))
	return m


func _room_ambient_sounds() -> Array[String]:
	var out: Array[String] = []
	for file_name: String in DirAccess.get_files_at("res://data/rooms/"):
		if not file_name.ends_with(".json"):
			continue
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/rooms/" + file_name))
		if not parsed is Dictionary:
			continue
		for room: Variant in (parsed as Dictionary).get("rooms", []):
			var sound: String = str((room as Dictionary).get("ambient_sound", ""))
			if not sound.is_empty() and not out.has(sound):
				out.append(sound)
	return out


func _check_noise_classification() -> void:
	var radii: Dictionary = {"sneak": 1.0, "walk": 3.5}
	var cases: Dictionary = {
		"player_sneak": "step_sneak", "player_walk": "step_walk", "player_sprint": "step_sprint",
		"drawer": "drawer_open", "lock_forced": "lock_forcing", "break_object": "break_object",
		"card_reader": "card_beep", "freight_elevator": "freight_elevator", "phone_vibration": "",
		"npc_voice": "",
	}
	for source: String in cases.keys():
		check_eq(AudioDirector.classify_noise(source, 3.0, radii), cases[source], "noise '%s'" % source)
	check_eq(AudioDirector.classify_noise("player", 0.8, radii), "step_sneak", "unnamed player noise by radius (sneak)")
	check_eq(AudioDirector.classify_noise("", 3.5, radii), "step_walk", "unnamed noise by radius (walk)")
	check_eq(AudioDirector.classify_noise("", 9.0, radii), "step_sprint", "unnamed noise by radius (sprint)")


# ─── Render sin conexión: la cinta se degrada de verdad ──────────

func _check_offline_render() -> void:
	var stems: Dictionary = MuzakSynth.render_piece("muzak", "standard", MuzakSynth.render_config("muzak"))
	var mel: Array = stems["mel"]
	check_eq(mel.size(), MuzakSynth.VARIANT_COUNT, "muzak stems carry clean/sour/atonal melodies")
	check(SynthDSP.peak(stems["acc"]) > 0.05 and SynthDSP.peak(mel[0]) > 0.05, "muzak stems are audible")
	check(_difference(mel[0], mel[1]) > 0.01, "sour melody differs from the clean one")
	var stats: Array[Dictionary] = []
	for s: float in [0.0, 40.0, 65.0, 90.0]:
		stats.append(_deck_stats(MuzakSynth.render_offline(stems, s, RENDER_SECONDS, true)))
	check_near(float(stats[0]["rate"]), 1.0, 0.002, "suspicion 0: tape at nominal speed")
	check(float(stats[1]["rate"]) < float(stats[0]["rate"]), "suspicion 40: slower tempo")
	check_near(float(stats[1]["pitch"]), 1.0, 0.005, "suspicion 40: slower but not transposed")
	check(float(stats[3]["rate"]) < float(stats[2]["rate"]), "suspicion 90 slower than 65")
	check(float(stats[2]["rate_std"]) > float(stats[1]["rate_std"]) * 4.0,
			"suspicion 65: irregular tempo (wow/flutter)")
	check(float(stats[2]["pitch_std"]) > float(stats[1]["pitch_std"]) * 4.0, "suspicion 65: the pitch wobbles")
	check(float(stats[0]["silent"]) == 0.0 and float(stats[1]["silent"]) == 0.0, "no silences below 51")
	check(float(stats[3]["silent"]) > float(stats[2]["silent"]), "suspicion 90 cuts out more than 65")
	check(float(stats[0]["degraded"]) == 0.0, "suspicion 0: every melody note clean")
	check(float(stats[1]["degraded"]) > 0.0, "suspicion 40: occasional out-of-tune note")
	check(float(stats[3]["atonal"]) > float(stats[2]["atonal"]) + 0.2, "suspicion 90: mostly atonal melody")
	for st: Dictionary in stats:
		check(float(st["rms"]) > 0.02, "offline render is audible (rms %.3f)" % float(st["rms"]))


func _deck_stats(result: Dictionary) -> Dictionary:
	var tele: Dictionary = result["telemetry"]
	var gains: PackedFloat32Array = tele["gain"]
	var variants: PackedByteArray = tele["variant"]
	var silent: int = 0
	var degraded: int = 0
	var atonal: int = 0
	for i: int in gains.size():
		silent += 1 if gains[i] < 0.1 else 0
		degraded += 1 if variants[i] != MuzakSynth.VARIANT_CLEAN else 0
		atonal += 1 if variants[i] == MuzakSynth.VARIANT_ATONAL else 0
	var n: float = maxf(1.0, float(gains.size()))
	var samples: PackedFloat32Array = result["samples"]
	var rate: Vector2 = _mean_std(tele["rate"])
	var pitch: Vector2 = _mean_std(tele["pitch"])
	return {"rate": rate.x, "rate_std": rate.y, "pitch": pitch.x, "pitch_std": pitch.y,
			"silent": silent / n, "degraded": degraded / n, "atonal": atonal / n,
			"rms": SynthDSP.rms(samples, 0, samples.size())}


func _mean_std(values: PackedFloat32Array) -> Vector2:
	var mean: float = 0.0
	for v: float in values:
		mean += v
	mean /= maxf(1.0, float(values.size()))
	var sq: float = 0.0
	for v: float in values:
		sq += (v - mean) * (v - mean)
	return Vector2(mean, sqrt(sq / maxf(1.0, float(values.size()))))


func _difference(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	var acc: float = 0.0
	for i: int in mini(a.size(), b.size()):
		acc += absf(a[i] - b[i])
	return acc / maxf(1.0, float(mini(a.size(), b.size())))


## La pletina estira el tiempo sin transponer: un seno de 440 Hz a tempo 0,9 sigue a 440 Hz y la
## música avanza al 90 % (en modo cinta, sin saltos por pulso, bajaría a 396 Hz).
func _check_time_stretch() -> void:
	var sine: PackedFloat32Array = SynthDSP.silence(STRETCH_LOOP_S, _rate)
	SynthDSP.tone_into(sine, _rate, 0.0, STRETCH_LOOP_S, TEST_HZ, TEST_HZ, 0.5, SynthDSP.Wave.SINE, 0.0, 0.0)
	var silent: PackedFloat32Array = PackedFloat32Array()
	silent.resize(sine.size())
	var stems: Dictionary = {"rate": _rate, "length": sine.size(), "acc": sine, "mel": [silent],
			"switches": PackedInt32Array(), "piece": "test", "arrangement": "sine",
			"spb": float(_rate) * 60.0 / AudioTuning.num("audio.piezas_bpm.muzak")}
	var params: Dictionary = MuzakSynth.degradation(0.0)
	params["tempo"] = STRETCH_TEMPO
	var stretched: Vector2 = _deck_frequency(stems, params)
	params.erase("jump_fade_s")
	var tape: Vector2 = _deck_frequency(stems, params)
	check_near(stretched.x, TEST_HZ, TEST_HZ * 0.015, "slower tempo keeps the key (%.1f Hz)" % stretched.x)
	check_near(stretched.y, STRETCH_TEMPO, 0.03, "…while the music advances at tempo 0.9 (%.3f)" % stretched.y)
	check_near(tape.x, TEST_HZ * STRETCH_TEMPO, TEST_HZ * 0.015, "reference: tape mode transposes (%.1f Hz)" % tape.x)


## (frecuencia por cruces por cero, avance musical por segundo de salida).
func _deck_frequency(stems: Dictionary, params: Dictionary) -> Vector2:
	var deck: MuzakDeck = MuzakDeck.new()
	deck.setup(_rate, 1, 0.0, 0.0)
	deck.load_stems_now(stems)
	deck.set_degradation(params, true)
	var out: PackedVector2Array = deck.process(_rate * STRETCH_OUT_S)
	var crossings: int = 0
	for i: int in range(1, out.size()):
		if out[i - 1].x < 0.0 and out[i].x >= 0.0:
			crossings += 1
	return Vector2(float(crossings) / float(STRETCH_OUT_S), deck.get_position_s() / float(STRETCH_OUT_S))


## Pistas sintéticas (baratas) para probar los cambios de pistas de la pletina.
func _fake_stems(arrangement: String, variants: int) -> Dictionary:
	var acc: PackedFloat32Array = PackedFloat32Array()
	acc.resize(_rate)
	var mel: Array = []
	for v: int in variants:
		mel.append(acc.duplicate())
	var switches: PackedInt32Array = PackedInt32Array()
	for k: int in FAKE_SWITCHES:
		switches.append(k * _rate / FAKE_SWITCHES)
	return {"rate": _rate, "length": _rate, "acc": acc, "mel": mel, "switches": switches, "piece": "muzak",
			"arrangement": arrangement, "degradable": true, "spb": float(_rate) / float(FAKE_SWITCHES / 2)}


func _check_deck_swaps() -> void:
	var deck: MuzakDeck = MuzakDeck.new()
	deck.setup(_rate, 3, 0.0, AudioTuning.num("audio.muzak.fundido_cambio_s"))
	deck.load_stems_now(_fake_stems("a", MuzakSynth.VARIANT_COUNT))
	deck.set_degradation(MuzakSynth.degradation(90.0), true)
	deck.process(512)
	deck.load_stems(_fake_stems("b", 1), true)
	check(deck.has_pending(), "a band change waits for its short fade")
	deck.upgrade_stems(_fake_stems("b", MuzakSynth.VARIANT_COUNT))
	check_eq(deck.variant_count(), MuzakSynth.VARIANT_COUNT, "an upgrade during a pending swap replaces the pending stems")
	deck.process(_rate / 2)
	check(not deck.has_pending() and deck.loaded_id() == "muzak|b", "the pending swap is applied")
	check_eq(deck.variant_count(), MuzakSynth.VARIANT_COUNT, "…with every variant (no stale clean-only melody)")
	deck.load_stems(_fake_stems("c", 1), true)
	deck.skip(0.5)
	check(not deck.has_pending() and deck.loaded_id() == "muzak|c", "a floor without muzak applies a pending swap at once")
	deck.upgrade_stems(_fake_stems("c", MuzakSynth.VARIANT_COUNT))
	check_eq(deck.variant_count(), MuzakSynth.VARIANT_COUNT, "variants arrive after that swap")
	deck.record_telemetry = true
	deck.process(_rate * 2)
	var off_key: int = 0
	for v: int in deck.get_telemetry()["variant"]:
		off_key += 1 if v != MuzakSynth.VARIANT_CLEAN else 0
	check(off_key > 0, "suspicion 90 after the swaps still plays sour/atonal notes")


func _check_wav_writer() -> void:
	var buf: PackedFloat32Array = SynthDSP.silence(0.25, _rate)
	SynthDSP.tone_into(buf, _rate, 0.0, 0.25, 440.0, 440.0, 0.5, SynthDSP.Wave.SINE, 0.01, 0.0)
	var path: String = OS.get_user_data_dir().path_join("test_audio_writer.wav")
	check_eq(SynthDSP.write_wav(path, buf, _rate), OK, "WAV writer succeeds")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	check_eq(bytes.slice(0, 4).get_string_from_ascii(), "RIFF", "WAV has RIFF header")
	check_eq(bytes.slice(8, 12).get_string_from_ascii(), "WAVE", "WAV has WAVE tag")
	check_eq(bytes.decode_u32(24), _rate, "WAV sample rate field")
	check_eq(bytes.size(), 44 + buf.size() * 2, "WAV size = header + 16-bit PCM")
	DirAccess.remove_absolute(path)


# ─── Oído sobre los NPCs ─────────────────────────────────────────

func _listener_config() -> Dictionary:
	var px: float = AudioTuning.px_per_metre()
	return {
		"hear_px": AudioTuning.num("audio.npcs.distancia_escucha_m") * px,
		"npc_min_speed": AudioTuning.num("audio.npcs.velocidad_min_px_s"),
		"npc_step_s": AudioTuning.num("audio.npcs.paso_intervalo_s"),
		"seated_s": AudioTuning.num("audio.npcs.sentado_s"),
		"approach_px": AudioTuning.num("audio.npcs.acercamiento_min_px"),
		"radio_interval": AudioTuning.range_of("audio.npcs.radio_intervalo_s"),
		"max_steps": AudioTuning.integer("audio.npcs.max_pasos_por_barrido"),
		"radio_occupations": AudioTuning.list("audio.npcs.radio_ocupaciones"),
	}


func _fake_npc(npc_id: String, occupation: String, pos: Vector2) -> Node2D:
	var script: GDScript = GDScript.new()
	script.source_code = FAKE_NPC_SOURCE
	script.reload()
	var npc: Node2D = script.new() as Node2D
	npc.set("npc_id", npc_id)
	npc.set("occupation_id", occupation)
	npc.position = pos
	add_child(npc)
	return npc


## walker: se acerca fuera de la vista, se sienta 6 s y se levanta · stander: de pie 6 s junto a la
## fuente y se va (sin silla) · seen: se acerca a la vista (x < 0) · guard · far (fuera de oído).
func _check_npc_listener() -> void:
	var cfg: Dictionary = _listener_config()
	var hear: float = float(cfg["hear_px"])
	var npcs: Dictionary = {
		"walker": _fake_npc("npc_walker", "", Vector2(hear * 0.9, 0.0)),
		"stander": _fake_npc("npc_stander", "", Vector2(hear * 0.5, hear * 0.3)),
		"seen": _fake_npc("npc_seen", "", Vector2(-hear * 0.9, 0.0)),
		"guard": _fake_npc("npc_guard", "security_guard", Vector2(0.0, 100.0)),
		"far": _fake_npc("npc_far", "", Vector2(hear * 3.0, 0.0)),
	}
	var listener: NpcListener = NpcListener.new()
	listener.setup(cfg, 7)
	var walker: Node2D = npcs["walker"]
	listener.set_probes(func(n: Node2D) -> bool: return n == walker,
			func(p: Vector2) -> bool: return p.x < 0.0)
	var events: Array[Dictionary] = _drive_npcs(listener, npcs)
	_check_listener_events(events, hear)
	check(listener.nearest_guard(Vector2.ZERO).is_equal_approx((npcs["guard"] as Node2D).position), "nearest guard tracked")
	for n: Variant in npcs.values():
		(n as Node).queue_free()


func _drive_npcs(listener: NpcListener, npcs: Dictionary) -> Array[Dictionary]:
	var nodes: Array[Node] = []
	for n: Variant in npcs.values():
		nodes.append(n as Node)
	var events: Array[Dictionary] = []
	for i: int in 400:
		var moving: bool = i < 30 or i > 90
		if moving:
			(npcs["walker"] as Node2D).position.x -= 12.0 * (1.0 if i < 30 else -1.0)
			(npcs["stander"] as Node2D).position.y += 12.0
			(npcs["far"] as Node2D).position.y += 12.0
		if i < 30:
			(npcs["seen"] as Node2D).position.x += 12.0
		events.append_array(listener.scan(nodes, Vector2.ZERO, 0.1))
	return events


func _check_listener_events(events: Array[Dictionary], hear: float) -> void:
	check(_has_event(events, "npc_step", NpcListener.APPROACH_KEY, SfxBank.IMPORTANCE_DANGER),
			"steps approaching out of sight → warning subtitle")
	check(_has_event(events, "npc_step", NpcListener.NEARBY_KEY, SfxBank.IMPORTANCE_AMBIENT),
			"steps approaching in plain view → quiet 'footsteps nearby' (own key)")
	var creaks: int = 0
	for e: Dictionary in events:
		creaks += 1 if str(e["sfx"]) == "chair_creak" else 0
	check_eq(creaks, 1, "only the seated NPC creaks a chair when standing up (not the one standing)")
	check(_has_event(events, "guard_radio", "", -1), "guards' radios crackle now and then")
	for e: Dictionary in events:
		if (e["position"] as Vector2).distance_to(Vector2.ZERO) > hear:
			check(false, "an out-of-range NPC produced a sound")
			break


func _has_event(events: Array[Dictionary], sfx: String, subtitle: String, importance: int) -> bool:
	for e: Dictionary in events:
		if str(e["sfx"]) == sfx and (subtitle.is_empty() or str(e["subtitle"]) == subtitle) \
				and (importance < 0 or int(e["importance"]) == importance):
			return true
	return false


func _check_voice_priority() -> void:
	var meta: Array[Vector2] = [Vector2(2, 1), Vector2(0, 5), Vector2(1, 2), Vector2(0, 3)]
	var all_busy: Array[bool] = [true, true, true, true]
	check_eq(SfxVoices.pick([true, false, true, true], meta, 0), 1, "a free voice is used first")
	check_eq(SfxVoices.pick(all_busy, meta, 0), 3, "a footstep steals the oldest footstep")
	var important: Array[Vector2] = [Vector2(2, 1), Vector2(1, 5), Vector2(2, 2), Vector2(1, 3)]
	check_eq(SfxVoices.pick(all_busy, important, 0), SfxVoices.NO_VOICE, "a footstep never cuts a radio or a lock")
	check_eq(SfxVoices.pick(all_busy, important, 2), 3, "an urgent sound steals the least important, oldest voice")


## Epílogo con una instantánea real de Tracking (§14.9: varía según el eje dominante).
func _check_epilogue_choice() -> void:
	Tracking.add("gold", 40, "test_audio")
	var gold: Dictionary = AudioDirector.epilogue_choice(Tracking.get_snapshot())
	check(str(gold["axis"]) == "gold" and not bool(gold["worn"]), "dominant gold → gold theme")
	for axis: String in ["blood", "silk", "sweat"]:
		Tracking.add(axis, 40, "test_audio")
	check(bool(Tracking.get_snapshot()["hybrid"]), "balanced axes make a hybrid run")
	check_eq(str(AudioDirector.epilogue_choice(Tracking.get_snapshot())["axis"]), AudioDirector.EPILOGUE_HYBRID,
			"hybrid run → the building's own muzak")
	Tracking.add("ruin", AudioTuning.integer("seguimiento.umbral_ruina_cascaron"), "test_audio")
	check(bool(AudioDirector.epilogue_choice(Tracking.get_snapshot())["worn"]), "ruin 'husk' → the theme on worn tape")
	Tracking.reset_for_new_run()
	check_eq(str(AudioDirector.epilogue_choice(Tracking.get_snapshot())["axis"]), AudioDirector.EPILOGUE_HYBRID,
			"no style at all → the building's own muzak")


# ─── AudioDirector: subtítulos de cada evento informativo (§13.10) ─

func _has_sub(key: String, importance: int = -1) -> bool:
	for s: Dictionary in _subs:
		if str(s["key"]) == key and (importance < 0 or int(s["importance"]) == importance):
			return true
	return false


func _count_sub(key: String) -> int:
	var n: int = 0
	for s: Dictionary in _subs:
		n += 1 if str(s["key"]) == key else 0
	return n


func _sub(key: String) -> Dictionary:
	for s: Dictionary in _subs:
		if str(s["key"]) == key:
			return s
	return {}


func _check_director_events(director: AudioDirector) -> void:
	_subs.clear()
	EventBus.player_caught_redhanded.emit("npc_a", "theft_small", 1)
	check(_has_sub("SUB_CAUGHT", SfxBank.IMPORTANCE_DANGER), "flagrancy posts a critical subtitle")
	check(director.get_deck().is_silenced(), "flagrancy interrupts the muzak")
	EventBus.phone_message_received.emit("npc_a", "MSG_TEST", false)
	check(_has_sub("SUB_PHONE_BUZZ"), "phone vibration posts a subtitle")
	director.set_phone_silenced(true)
	check(FileAccess.file_exists(SaveSystem.get_profile_path()), "silencing the phone is saved to the profile")
	var buzzes: int = _count_sub("SUB_PHONE_BUZZ")
	await get_tree().create_timer(1.1).timeout
	EventBus.phone_message_received.emit("npc_a", "MSG_TEST", false)
	check_eq(_count_sub("SUB_PHONE_BUZZ"), buzzes, "a silenced phone does not vibrate")
	director.set_phone_silenced(false)
	_check_stairs_no_chime()
	EventBus.card_reader_logged.emit("elevator_bank_reader", "player", 1, 9)
	check(_has_sub("SUB_CARD_BEEP"), "card reader beep posts a subtitle")
	EventBus.floor_changed.emit(2, 3)
	check(_has_sub("SUB_ELEVATOR_CHIME"), "arriving by elevator chimes")
	check_eq(director.get_arrangement(), "compressed", "the pit gets the compressed arrangement")
	_emit_player_noises()
	await _check_masks_and_alarms(director)
	await _check_chatter()
	var unlocalised: Array[String] = []
	for s: Dictionary in _subs:
		if tr(str(s["key"])) == str(s["key"]):
			unlocalised.append(str(s["key"]))
	check(unlocalised.is_empty(), "every posted subtitle is localised %s" % str(unlocalised))


## Pasar la tarjeta del ascensor y bajar por la escalera no hace sonar la campanilla.
func _check_stairs_no_chime() -> void:
	EventBus.card_reader_logged.emit("elevator_bank_reader", "player", 1, 9)
	EventBus.room_entered.emit("main_stairs@1", true)
	EventBus.floor_changed.emit(1, 2)
	EventBus.room_entered.emit("main_stairs@2", true)
	check(not _has_sub("SUB_ELEVATOR_CHIME"), "badging the elevator then taking the stairs: no chime")


func _emit_player_noises() -> void:
	var at: Vector2 = Vector2(96.0, 0.0)
	EventBus.noise_emitted.emit(at, AudioTuning.num("ruido.radio_esprint"), "player_sprint")
	check(_has_sub("SUB_OWN_STEPS_SPRINT"), "sprinting posts a subtitle")
	check((_sub("SUB_OWN_STEPS_SPRINT").get("position", Vector2.ZERO) as Vector2).is_equal_approx(at),
			"subtitle carries the sound position")
	EventBus.noise_emitted.emit(at, AudioTuning.num("ruido.radio_cajon"), "drawer")
	EventBus.noise_emitted.emit(at, AudioTuning.num("ruido.radio_forzar_cerradura"), "lock_forced")
	EventBus.noise_emitted.emit(at, AudioTuning.num("ruido.radio_romper_objeto"), "break_object")
	check(_has_sub("SUB_DRAWER"), "drawer posts a subtitle")
	check(_has_sub("SUB_LOCK_FORCING"), "lock forcing posts a subtitle")
	check(_has_sub("SUB_BREAK", SfxBank.IMPORTANCE_DANGER), "breaking something posts a warning subtitle")


func _check_masks_and_alarms(director: AudioDirector) -> void:
	var masks: Array[bool] = []
	director.mask_changed.connect(func(m: bool) -> void: masks.append(m))
	EventBus.room_entered.emit("call_center", true)
	check(director.is_masked() and _has_sub("SUB_MASK_ON"), "acoustic mask room → indicator + subtitle")
	EventBus.room_entered.emit("hr_office", true)
	check(not director.is_masked() and _has_sub("SUB_MASK_OFF"), "leaving the mask → subtitle")
	check_eq(masks, [true, false], "mask_changed signal for the HUD indicator")
	EventBus.alert_level_changed.emit(0, AudioTuning.integer("audio.alarma.nivel_minimo"))
	check(_has_sub("SUB_PA_SECURITY") and not _has_sub("SUB_GUARD_RADIO"),
			"rising alert with no guard on the floor → building PA, not a phantom radio")
	check(_has_sub("SUB_ALARM_THE_PIT", SfxBank.IMPORTANCE_DANGER), "alarm of the floor's band")
	EventBus.suspicion_changed.emit(0.0, 60.0)
	check_eq(director.get_muzak_band(), 2, "suspicion 60 → worn-tape band")
	check(_has_sub("SUB_MUZAK_WORN", SfxBank.IMPORTANCE_DANGER), "muzak degradation posts a subtitle")
	EventBus.suspicion_changed.emit(60.0, 5.0)
	EventBus.alert_level_changed.emit(AudioTuning.integer("audio.alarma.nivel_minimo"), 0)
	await wait_frames(1)


func _check_chatter() -> void:
	var npc: Node2D = _fake_npc("npc_chatty", "", Vector2(120.0, 0.0))
	npc.add_to_group("npcs")
	EventBus.npc_decided.emit("npc_chatty", "chat_with_colleague", {})
	check(_has_sub("SUB_CHATTER") or _has_sub("SUB_CONVERSATION"), "NPC chatter posts a subtitle")
	npc.queue_free()
	await wait_frames(1)


## Un director nuevo (p. ej. el del menú) deja en reposo al anterior: nada se duplica. El móvil
## que vibra es ruido real para los NPC.
func _check_single_director(director: AudioDirector) -> void:
	var second: AudioDirector = AudioDirector.new()
	add_child(second)
	await wait_frames(2)
	check(second.is_active() and not director.is_active(), "the newest AudioDirector takes over")
	check(AudioDirector.find(get_tree()) == second, "find() returns the active director")
	check_eq(get_tree().get_nodes_in_group(AudioDirector.GROUP).size(), 1, "only the active director is in the group")
	var player: Node2D = Node2D.new()
	player.position = Vector2(50.0, 60.0)
	player.add_to_group("player")
	add_child(player)
	await get_tree().create_timer(1.1).timeout
	_subs.clear()
	_noises.clear()
	EventBus.phone_message_received.emit("npc_a", "MSG_TEST", false)
	check_eq(_count_sub("SUB_PHONE_BUZZ"), 1, "two directors never duplicate a sound's subtitle")
	check(_noises.size() == 1 and str(_noises[0]["source"]) == AudioDirector.PHONE_NOISE_SOURCE
			and (_noises[0]["position"] as Vector2).is_equal_approx(player.position)
			and is_equal_approx(float(_noises[0]["radius"]), AudioTuning.num("ruido.radio_movil")),
			"a vibrating phone is a real noise at the player (radius from balance)")
	player.queue_free()
	second.queue_free()
	await wait_frames(2)
	check(director.is_active() and AudioDirector.find(get_tree()) == director, "the previous director resumes")


# ─── Bandas: arreglos, fábrica sin hilo, exterior nocturno ───────

func _check_floor_arrangements(director: AudioDirector) -> void:
	var ambience: Ambience = director.get_ambience()
	var no_muzak: Dictionary = {
		100: ["assembly_line", "SUB_FACTORY_RHYTHM"], 200: ["street_ambient", "SUB_NIGHT_STREET"],
	}
	for f: int in no_muzak.keys():
		EventBus.floor_changed.emit(3, f)
		check_eq(director.get_arrangement(), "none", "floor %d has no muzak arrangement" % f)
		check(not director.is_muzak_active(), "floor %d selects no muzak" % f)
		check_eq(ambience.current_id(), no_muzak[f][0], "floor %d ambience" % f)
		check(_has_sub(no_muzak[f][1]), "floor %d explains the missing music" % f)
	var expected: Dictionary = {-2: "muffled", 3: "compressed", 8: "standard", 15: "strings", 19: "orchestral"}
	for f: int in expected.keys():
		EventBus.floor_changed.emit(0, f)
		check_eq(director.get_arrangement(), expected[f], "floor %d arrangement" % f)
		check(director.is_muzak_active(), "floor %d plays muzak" % f)
	check(await _wait_music(director), "muzak for the current band renders in the background")
	check_eq(director.get_deck().variant_count(), MuzakSynth.VARIANT_COUNT, "degradable variants arrive")
	await wait_frames(3)
	check((director.get_node("MuzakPlayer") as AudioStreamPlayer).playing, "the muzak generator is playing")
	var lead: float = AudioTuning.num("audio.muzak.adelanto_s") * float(_rate)
	check(director.get_queued_music_frames() > 0 and director.get_queued_music_frames() <= int(lead) + 1,
			"only ~adelanto_s of music is queued (changes and the flagrancy cut are heard at once)")
	director.interrupt_muzak(AudioTuning.num("audio.corte_flagrancia_s"))
	check_eq(director.get_queued_music_frames(), 0, "flagrancy drops the queued music: the cut is immediate")
	EventBus.floor_changed.emit(19, 100)
	await wait_frames(3)
	check(not (director.get_node("MuzakPlayer") as AudioStreamPlayer).playing, "no muzak on the factory floor")


func _wait_music(director: AudioDirector) -> bool:
	for i: int in WAIT_STEPS:
		var deck: MuzakDeck = director.get_deck()
		if director.is_music_ready() and (director.get_piece() != "muzak"
				or deck.variant_count() >= MuzakSynth.VARIANT_COUNT):
			return true
		await get_tree().create_timer(WAIT_STEP_S).timeout
	return false


## Revisión: pasar por una planta nueva y bajar a la fábrica mientras se renderiza no debe dejar
## la melodía limpia para siempre (la versión pendiente vieja volvía sin variantes).
func _check_stale_swap(director: AudioDirector) -> void:
	EventBus.floor_changed.emit(100, 3)
	check(await _wait_music(director), "the pit's muzak is ready")
	EventBus.floor_changed.emit(3, 8)
	EventBus.floor_changed.emit(8, 100)
	var key: String = MuzakLibrary.key_for("muzak", "standard")
	for i: int in WAIT_STEPS:
		if MuzakLibrary.is_complete(key):
			break
		await get_tree().create_timer(WAIT_STEP_S).timeout
	await wait_frames(3)
	EventBus.floor_changed.emit(100, 8)
	check(await _wait_music(director), "back on the floor, its muzak is ready")
	check_eq(director.get_deck().loaded_id(), key, "the deck plays that band's arrangement")
	check_eq(director.get_deck().variant_count(), MuzakSynth.VARIANT_COUNT,
			"leaving for the factory mid-render never brings back a clean-only melody")


## Llegar dentro de la cabina (la sala llega después del cambio de planta) hace sonar la campanilla.
func _check_arrival_by_elevator(_director: AudioDirector) -> void:
	await get_tree().create_timer(1.1).timeout
	_subs.clear()
	EventBus.room_entered.emit("corridors_low@8", true)
	EventBus.floor_changed.emit(8, 9)
	EventBus.room_entered.emit("main_elevator_1@9", true)
	check(_has_sub("SUB_ELEVATOR_CHIME"), "arriving inside the elevator car chimes")
	EventBus.room_entered.emit("corridors_low@9", true)


## Con el reloj en marcha se escucha a los NPC: la radio del vigilante más cercano, con posición.
func _check_guard_radio(director: AudioDirector) -> void:
	check(not director.is_listening(), "clock paused: NPC hearing stops (nothing accumulates)")
	GameClock.resume()
	check(director.is_listening(), "clock running: NPC hearing on")
	var guard: Node2D = _fake_npc("npc_guard_on_floor", "security_guard", Vector2(150.0, 40.0))
	guard.add_to_group("npcs")
	await get_tree().create_timer(0.35).timeout
	_subs.clear()
	EventBus.alert_level_changed.emit(1, 2)
	var radio: Dictionary = _sub("SUB_GUARD_RADIO")
	check(not radio.is_empty() and int(radio["importance"]) == SfxBank.IMPORTANCE_DANGER
			and (radio["position"] as Vector2).is_equal_approx(guard.position),
			"rising alert → the nearest guard's radio, from where the guard is")
	GameClock.pause()
	guard.queue_free()
	await wait_frames(1)


func _check_music_pieces(director: AudioDirector) -> void:
	director.play_menu_music()
	check_eq(director.get_mode(), AudioDirector.MODE_MENU, "menu music mode")
	check(await _wait_music(director), "menu music renders")
	check_eq(director.get_deck().variant_count(), 1, "menu music never degrades")
	EventBus.game_over.emit("fired", "ending_test", {"blood": 3, "gold": 40, "silk": 10, "sweat": 5})
	check_eq(director.get_mode(), AudioDirector.MODE_EPILOGUE, "game over → epilogue music")
	check_eq(director.get_piece(), "epilogue_gold", "epilogue follows the dominant axis")
	check(await _wait_music(director), "epilogue music renders")
	director.play_epilogue(AudioDirector.EPILOGUE_HYBRID)
	check_eq(director.get_piece(), "epilogue_hybrid", "no dominant axis → the building's own muzak")
	director.play_epilogue("no_such_axis")
	check_eq(director.get_piece(), "epilogue_ruin", "unknown axis → the ruined tape")
	director.stop_music()
	check_eq(director.get_mode(), AudioDirector.MODE_OFF, "music can be stopped")


## Revisión: salir del árbol con un render en curso no bloquea el hilo principal; el render
## termina solo y lo recoge el siguiente poll (queda en la caché para el próximo director).
func _check_non_blocking_exit() -> void:
	var director: AudioDirector = AudioDirector.new()
	add_child(director)
	await wait_frames(2)
	await _drain_library()
	director.play_epilogue("silk")
	var key: String = MuzakLibrary.key_for("epilogue_silk", MuzakSynth.default_arrangement("epilogue_silk"))
	check(MuzakLibrary.render_in_flight(), "a render is in flight")
	remove_child(director)
	director.free()
	check(MuzakLibrary.render_in_flight(), "freeing the director did not wait for the render")
	await _drain_library()
	check(not MuzakLibrary.get_stems(key).is_empty(), "the orphaned render is collected into the shared cache")


func _drain_library() -> void:
	for i: int in WAIT_STEPS:
		MuzakLibrary.poll()
		if not MuzakLibrary.is_rendering():
			return
		await get_tree().create_timer(WAIT_STEP_S).timeout
