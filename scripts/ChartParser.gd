class_name ChartParser
extends RefCounted

# Parses Clone Hero / Guitar Hero notes.chart and notes.mid into unified time-indexed data:
# {
#   "resolution": 192,
#   "offset": 0.0,
#   "tempos": [{tick, bpm, time}],
#   "sections": [{time, name}],
#   "beat_lines": [{time, major}],
#   "tracks": { "Expert": Array[NoteDict], "Hard": ..., "Medium": ..., "Easy": ... },
#   "drums": [{time, type}] # type: 0=kick, 1=snare, 2=cymbal/tom
# }

const DIFF_ORDER := ["Expert", "Hard", "Medium", "Easy"]

static func parse_chart_text(text: String) -> Dictionary:
	var clean := text.lstrip("\ufeff")
	var resolution := 192
	var offset := 0.0
	var raw_tempos: Array[Dictionary] = []
	var raw_ts: Array[Dictionary] = []
	var raw_events: Array[Dictionary] = []
	var raw_tracks := {
		"Expert": [],
		"Hard": [],
		"Medium": [],
		"Easy": []
	}
	var fallback_tracks := {} # Lead/Bass/Rhythm fallback if Single is absent
	var raw_drums: Array[Dictionary] = []

	var section := ""
	for raw_line in clean.split("\n"):
		var line := raw_line.strip_edges()
		if line == "" or line == "{" or line == "}":
			continue
		if line.begins_with("[") and line.ends_with("]"):
			section = line.substr(1, line.length() - 2).strip_edges()
			continue
		var eq := line.find("=")
		if eq <= 0:
			continue
		var lhs := line.substr(0, eq).strip_edges()
		var rhs := line.substr(eq + 1).strip_edges()

		if section == "Song":
			var kl := lhs.to_lower()
			var val := rhs.trim_prefix("\"").trim_suffix("\"")
			if kl == "resolution":
				resolution = maxi(1, int(val))
			elif kl == "offset":
				offset = float(val)
		elif section == "SyncTrack":
			var tick := int(lhs)
			var parts := rhs.split(" ", false)
			if parts.size() >= 2:
				if parts[0] == "B":
					raw_tempos.append({"tick": tick, "bpm": maxf(10.0, float(parts[1]) / 1000.0)})
				elif parts[0] == "TS":
					var num := maxi(1, int(parts[1]))
					raw_ts.append({"tick": tick, "num": num})
		elif section == "Events":
			var tick := int(lhs)
			if rhs.begins_with("E "):
				var ev := rhs.substr(2).strip_edges().trim_prefix("\"").trim_suffix("\"")
				if ev.begins_with("section ") or ev.begins_with("prc_"):
					var sname := ev.trim_prefix("section ").trim_prefix("prc_").replace("_", " ").strip_edges()
					raw_events.append({"tick": tick, "name": sname})
		elif section.ends_with("Single"):
			var diff := section.trim_suffix("Single")
			if raw_tracks.has(diff):
				_parse_chart_note_line(int(lhs), rhs, raw_tracks[diff])
		elif section.ends_with("DoubleBass") or section.ends_with("DoubleRhythm") or section.ends_with("Keyboard"):
			for d in DIFF_ORDER:
				if section.begins_with(d):
					if not fallback_tracks.has(d):
						fallback_tracks[d] = []
					_parse_chart_note_line(int(lhs), rhs, fallback_tracks[d])
		elif section.ends_with("Drums"):
			# Prefer ExpertDrums, otherwise collect first drum track seen
			if section == "ExpertDrums" or raw_drums.is_empty():
				var parts := rhs.split(" ", false)
				if parts.size() >= 2 and parts[0] == "N":
					var ntype := int(parts[1])
					if ntype == 0 or ntype == 32:
						raw_drums.append({"tick": int(lhs), "type": 0}) # Kick
					elif ntype == 1:
						raw_drums.append({"tick": int(lhs), "type": 1}) # Snare
					elif ntype in [2, 3, 4]:
						raw_drums.append({"tick": int(lhs), "type": 2}) # Cymbal / Tom

	# Fill Single from fallback if chart only has Bass/Rhythm/Keys
	var any_single := false
	for d in DIFF_ORDER:
		if not raw_tracks[d].is_empty():
			any_single = true
	if not any_single:
		for d in DIFF_ORDER:
			if fallback_tracks.has(d):
				raw_tracks[d] = fallback_tracks[d]

	return _finalize_chart(resolution, offset, raw_tempos, raw_ts, raw_events, raw_tracks, raw_drums)

static func _parse_chart_note_line(tick: int, rhs: String, out_arr: Array) -> void:
	var parts := rhs.split(" ", false)
	if parts.size() < 3:
		return
	if parts[0] == "N":
		var code := int(parts[1])
		var length := int(parts[2])
		out_arr.append({"tick": tick, "kind": "N", "code": code, "len": length})
	elif parts[0] == "S":
		var scode := int(parts[1])
		var slen := int(parts[2])
		if scode == 2:
			out_arr.append({"tick": tick, "kind": "SP", "len": slen})

static func parse_midi_bytes(raw: PackedByteArray) -> Dictionary:
	if raw.size() < 14 or raw.slice(0, 4).get_string_from_ascii() != "MThd":
		return {}
	var pos := 8
	var _fmt := (raw[pos] << 8) | raw[pos + 1]
	var ntracks := (raw[pos + 2] << 8) | raw[pos + 3]
	var division := (raw[pos + 4] << 8) | raw[pos + 5]
	if division <= 0:
		division = 480
	pos = 14

	var raw_tempos: Array[Dictionary] = []
	var raw_ts: Array[Dictionary] = []
	var raw_events: Array[Dictionary] = []
	var raw_tracks := {"Expert": [], "Hard": [], "Medium": [], "Easy": []}
	var raw_drums: Array[Dictionary] = []

	# MIDI pitch ranges for PART GUITAR: Easy 60-64, Medium 72-76, Hard 84-88, Expert 96-100; SP=116
	var diff_bases := {"Easy": 60, "Medium": 72, "Hard": 84, "Expert": 96}

	for _t in range(ntracks):
		if pos + 8 > raw.size():
			break
		var tid := raw.slice(pos, pos + 4).get_string_from_ascii()
		var tlen := (raw[pos + 4] << 24) | (raw[pos + 5] << 16) | (raw[pos + 6] << 8) | raw[pos + 7]
		pos += 8
		var tend := mini(pos + tlen, raw.size())
		if tid != "MTrk":
			pos = tend
			continue

		var cur := pos
		var tick := 0
		var running := 0
		var track_name := ""
		var active_notes := {} # pitch -> start_tick
		var midi_events: Array[Dictionary] = []

		while cur < tend:
			# Read VLQ delta
			var delta := 0
			while cur < tend:
				var b := raw[cur]
				cur += 1
				delta = (delta << 7) | (b & 0x7F)
				if (b & 0x80) == 0:
					break
			tick += delta
			if cur >= tend:
				break
			var status := raw[cur]
			if status < 0x80:
				status = running
			else:
				cur += 1
				if status < 0xF0:
					running = status

			var hi := status & 0xF0
			if hi == 0x90 or hi == 0x80:
				if cur + 1 >= tend:
					break
				var pitch := raw[cur]
				var vel := raw[cur + 1]
				cur += 2
				var is_on := (hi == 0x90 and vel > 0)
				if is_on:
					active_notes[pitch] = tick
				else:
					if active_notes.has(pitch):
						var st_tick: int = active_notes[pitch]
						active_notes.erase(pitch)
						midi_events.append({"tick": st_tick, "pitch": pitch, "len": maxi(0, tick - st_tick)})
			elif hi == 0xA0 or hi == 0xB0 or hi == 0xE0:
				cur += 2
			elif hi == 0xC0 or hi == 0xD0:
				cur += 1
			elif status == 0xFF:
				if cur + 1 >= tend:
					break
				var mtype := raw[cur]
				cur += 1
				var mlen := 0
				while cur < tend:
					var b := raw[cur]
					cur += 1
					mlen = (mlen << 7) | (b & 0x7F)
					if (b & 0x80) == 0:
						break
				if cur + mlen > tend:
					break
				if mtype == 0x03: # Track name
					track_name = raw.slice(cur, cur + mlen).get_string_from_utf8().strip_edges().to_upper()
				elif mtype == 0x51 and mlen == 3: # Set Tempo (microseconds per quarter)
					var us := (raw[cur] << 16) | (raw[cur + 1] << 8) | raw[cur + 2]
					if us > 0:
						raw_tempos.append({"tick": tick, "bpm": 60000000.0 / float(us)})
				elif mtype == 0x58 and mlen >= 2: # Time signature
					raw_ts.append({"tick": tick, "num": maxi(1, raw[cur])})
				elif mtype == 0x01 or mtype == 0x05: # Text event
					var txt := raw.slice(cur, cur + mlen).get_string_from_utf8().strip_edges()
					if txt.begins_with("[section ") or txt.begins_with("[prc_"):
						var s := txt.trim_prefix("[").trim_suffix("]").trim_prefix("section ").trim_prefix("prc_").replace("_", " ")
						raw_events.append({"tick": tick, "name": s})
				cur += mlen
			elif status == 0xF0 or status == 0xF7:
				var slen := 0
				while cur < tend:
					var b := raw[cur]
					cur += 1
					slen = (slen << 7) | (b & 0x7F)
					if (b & 0x80) == 0:
						break
				cur += slen
			else:
				break

		pos = tend

		if track_name in ["PART GUITAR", "T1 GEMS", "PART LEAD"] or (track_name in ["PART BASS", "PART RHYTHM"] and raw_tracks["Expert"].is_empty()):
			var sp_ranges: Array[Dictionary] = []
			for ev in midi_events:
				if int(ev["pitch"]) == 116:
					sp_ranges.append({"tick": int(ev["tick"]), "kind": "SP", "len": int(ev["len"])})
			for d in DIFF_ORDER:
				var base: int = diff_bases[d]
				for sp in sp_ranges:
					raw_tracks[d].append(sp)
				for ev in midi_events:
					var p := int(ev["pitch"])
					if p >= base and p <= base + 4:
						raw_tracks[d].append({"tick": int(ev["tick"]), "kind": "N", "code": p - base, "len": int(ev["len"])})
					elif p == base + 5: # Forced HOPO marker
						raw_tracks[d].append({"tick": int(ev["tick"]), "kind": "N", "code": 5, "len": int(ev["len"])})
					elif p == 104: # Tap marker
						raw_tracks[d].append({"tick": int(ev["tick"]), "kind": "N", "code": 6, "len": int(ev["len"])})
		elif track_name in ["PART DRUMS", "PART DRUM"]:
			for ev in midi_events:
				var p := int(ev["pitch"])
				if p == 96 or p == 95:
					raw_drums.append({"tick": int(ev["tick"]), "type": 0})
				elif p == 97:
					raw_drums.append({"tick": int(ev["tick"]), "type": 1})
				elif p in [98, 99, 100]:
					raw_drums.append({"tick": int(ev["tick"]), "type": 2})

	return _finalize_chart(division, 0.0, raw_tempos, raw_ts, raw_events, raw_tracks, raw_drums)

static func _finalize_chart(
	resolution: int,
	offset: float,
	raw_tempos: Array[Dictionary],
	raw_ts: Array[Dictionary],
	raw_events: Array[Dictionary],
	raw_tracks: Dictionary,
	raw_drums: Array[Dictionary]
) -> Dictionary:
	# Sort & build cumulative tempo map
	raw_tempos.sort_custom(func(a, b): return int(a["tick"]) < int(b["tick"]))
	if raw_tempos.is_empty() or int(raw_tempos[0]["tick"]) > 0:
		raw_tempos.insert(0, {"tick": 0, "bpm": 120.0})

	var tempos: Array[Dictionary] = []
	var cur_time := offset
	var cur_tick := 0
	var cur_bpm := float(raw_tempos[0]["bpm"])
	for tp in raw_tempos:
		var tk := int(tp["tick"])
		if tk > cur_tick:
			cur_time += (float(tk - cur_tick) / float(resolution)) * (60.0 / cur_bpm)
			cur_tick = tk
		cur_bpm = float(tp["bpm"])
		tempos.append({"tick": tk, "bpm": cur_bpm, "time": cur_time})

	# Auto-downchart missing difficulties from highest available difficulty so every song has Easy/Medium/Hard/Expert!
	var highest_avail := ""
	for d in DIFF_ORDER:
		if not raw_tracks[d].is_empty():
			highest_avail = d
			break
	if highest_avail != "":
		if raw_tracks["Expert"].is_empty():
			raw_tracks["Expert"] = raw_tracks[highest_avail].duplicate(true)
		if raw_tracks["Hard"].is_empty():
			raw_tracks["Hard"] = _downchart(raw_tracks["Expert"], 4, resolution / 2)
		if raw_tracks["Medium"].is_empty():
			raw_tracks["Medium"] = _downchart(raw_tracks["Hard"], 3, resolution)
		if raw_tracks["Easy"].is_empty():
			raw_tracks["Easy"] = _downchart(raw_tracks["Medium"], 2, resolution * 2)

	var hopo_thresh := int(65.0 * float(resolution) / 192.0) # Standard 1/12th+1 Clone Hero HOPO threshold
	var sustain_min := int(float(resolution) * 0.35)
	var tracks := {}
	var max_tick := resolution * 16

	for d in DIFF_ORDER:
		var items: Array = raw_tracks[d]
		var sp_spans: Array[Vector2i] = []
		var by_tick := {}
		for it in items:
			var tk := int(it["tick"])
			if tk > max_tick:
				max_tick = tk
			if it["kind"] == "SP":
				sp_spans.append(Vector2i(tk, tk + maxi(1, int(it["len"]))))
			elif it["kind"] == "N":
				if not by_tick.has(tk):
					by_tick[tk] = {"frets": {}, "force_flip": false, "tap": false}
				var code := int(it["code"])
				if code >= 0 and code <= 4:
					by_tick[tk]["frets"][code] = maxi(int(by_tick[tk]["frets"].get(code, 0)), int(it["len"]))
				elif code == 5:
					by_tick[tk]["force_flip"] = true
				elif code == 6:
					by_tick[tk]["tap"] = true
				elif code == 7: # Open note -> map to Green/Center chord feel on 5-lane mobile
					by_tick[tk]["frets"][0] = maxi(int(by_tick[tk]["frets"].get(0, 0)), int(it["len"]))

		var sorted_ticks := by_tick.keys()
		sorted_ticks.sort()
		var built: Array[Dictionary] = []
		var prev_tick := -999999
		var prev_fret := -1
		var prev_chord := false

		for tk_var in sorted_ticks:
			var tk: int = int(tk_var)
			var group: Dictionary = by_tick[tk]
			var fdict: Dictionary = group["frets"]
			if fdict.is_empty():
				continue
			var frets := fdict.keys()
			frets.sort()
			var is_chord: bool = frets.size() > 1
			var natural_hopo: bool = (not is_chord) and (prev_tick >= 0) and ((tk - prev_tick) <= hopo_thresh) and (prev_chord or int(frets[0]) != prev_fret)
			var is_hopo: bool = natural_hopo
			if bool(group["force_flip"]):
				is_hopo = not is_hopo
			var is_tap: bool = bool(group["tap"])
			var in_sp: bool = false
			for sp in sp_spans:
				if tk >= sp.x and tk < sp.y:
					in_sp = true
					break
			var t0 := tick_to_time(tk, resolution, tempos)
			for fr in frets:
				var lticks := int(fdict[fr])
				var dur := 0.0
				if lticks >= sustain_min:
					dur = maxf(0.0, tick_to_time(tk + lticks, resolution, tempos) - t0)
				built.append({
					"tick": tk,
					"time": t0,
					"end_time": t0 + dur,
					"dur": dur,
					"lane": int(fr),
					"hopo": is_hopo or is_tap,
					"tap": is_tap,
					"sp": in_sp,
					"chord": is_chord,
					"hit": false,
					"missed": false,
					"sustain_done": false
				})
			prev_tick = tk
			prev_fret = int(frets[0])
			prev_chord = is_chord
		tracks[d] = built

	# Sections
	raw_events.sort_custom(func(a, b): return int(a["tick"]) < int(b["tick"]))
	var sections: Array[Dictionary] = []
	for ev in raw_events:
		sections.append({
			"time": tick_to_time(int(ev["tick"]), resolution, tempos),
			"name": str(ev["name"])
		})

	# Beat lines for highway grid & fallback rhythmic drum pulse
	raw_ts.sort_custom(func(a, b): return int(a["tick"]) < int(b["tick"]))
	if raw_ts.is_empty() or int(raw_ts[0]["tick"]) > 0:
		raw_ts.insert(0, {"tick": 0, "num": 4})
	var beat_lines: Array[Dictionary] = []
	var btick := 0
	var ts_idx := 0
	var beat_in_bar := 0
	var end_limit := max_tick + resolution * 8
	while btick <= end_limit:
		while ts_idx + 1 < raw_ts.size() and btick >= int(raw_ts[ts_idx + 1]["tick"]):
			ts_idx += 1
			beat_in_bar = 0
		var num := int(raw_ts[ts_idx]["num"])
		beat_lines.append({
			"tick": btick,
			"time": tick_to_time(btick, resolution, tempos),
			"major": (beat_in_bar % num) == 0
		})
		beat_in_bar += 1
		btick += resolution

	# Drum cues (exact drum chart events if available, otherwise rhythmic kick/snare groove synced to tempo map + audio analyzer!)
	var drums: Array[Dictionary] = []
	if not raw_drums.is_empty():
		raw_drums.sort_custom(func(a, b): return int(a["tick"]) < int(b["tick"]))
		var last_dt := -999
		var last_tp := -1
		for dr in raw_drums:
			if int(dr["tick"]) == last_dt and int(dr["type"]) == last_tp:
				continue
			last_dt = int(dr["tick"])
			last_tp = int(dr["type"])
			drums.append({
				"time": tick_to_time(int(dr["tick"]), resolution, tempos),
				"type": int(dr["type"])
			})
	else:
		# Synthesize beat-synced kick/snare/hat markers from SyncTrack so lights ALWAYS dance on beat + audio bass energy!
		for i in range(beat_lines.size()):
			var bt := float(beat_lines[i]["time"])
			if bt < 0.0:
				continue
			var m4 := i % 4
			if m4 == 0 or m4 == 2:
				drums.append({"time": bt, "type": 0}) # Kick on 1 & 3
			else:
				drums.append({"time": bt, "type": 1}) # Snare on 2 & 4

	return {
		"resolution": resolution,
		"offset": offset,
		"tempos": tempos,
		"sections": sections,
		"beat_lines": beat_lines,
		"tracks": tracks,
		"drums": drums
	}

static func _downchart(src: Array, max_lane: int, min_gap: int) -> Array:
	var out := []
	var last_tk := -999999
	for it in src:
		if it["kind"] == "SP":
			out.append(it.duplicate())
			continue
		var code := int(it["code"])
		if code > 4:
			continue
		var tk := int(it["tick"])
		if tk - last_tk < min_gap:
			continue
		last_tk = tk
		var mapped_lane := mini(code, max_lane)
		out.append({"tick": tk, "kind": "N", "code": mapped_lane, "len": int(it["len"])})
	return out

static func tick_to_time(tick: int, resolution: int, tempos: Array[Dictionary]) -> float:
	if tempos.is_empty():
		return float(tick) / float(resolution) * 0.5
	var lo := 0
	var hi := tempos.size() - 1
	while lo < hi:
		var mid := (lo + hi + 1) >> 1
		if int(tempos[mid]["tick"]) <= tick:
			lo = mid
		else:
			hi = mid - 1
	var tp := tempos[lo]
	var dticks := tick - int(tp["tick"])
	return float(tp["time"]) + (float(dticks) / float(resolution)) * (60.0 / float(tp["bpm"]))

static func apply_delay(chart_data: Dictionary, delay_sec: float) -> void:
	chart_data["offset"] = float(chart_data.get("offset", 0.0)) + delay_sec
	for tp in chart_data.get("tempos", []):
		tp["time"] = float(tp["time"]) + delay_sec
	for sc in chart_data.get("sections", []):
		sc["time"] = float(sc["time"]) + delay_sec
	for bl in chart_data.get("beat_lines", []):
		bl["time"] = float(bl["time"]) + delay_sec
	for dr in chart_data.get("drums", []):
		dr["time"] = float(dr["time"]) + delay_sec
	var tracks: Dictionary = chart_data.get("tracks", {})
	for d in tracks.keys():
		for n in tracks[d]:
			n["time"] = float(n["time"]) + delay_sec
			n["end_time"] = float(n["end_time"]) + delay_sec
