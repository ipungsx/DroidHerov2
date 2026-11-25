class_name SngParser
extends RefCounted

# Reads .sng binary package metadata and unmasks inner files (chart/mid, audio stems, album art)

static func peek_header(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f or f.get_length() < 42:
		return {}
	var magic := f.get_buffer(6).get_string_from_ascii()
	if magic != "SNGPKG":
		return {}
	var ver := f.get_32()
	var mask := f.get_buffer(16)
	var _meta_len := f.get_64()
	var meta_cnt := f.get_64()
	if meta_cnt > 4096:
		return {}
	var meta := {}
	for _i in range(meta_cnt):
		var kl := f.get_32()
		if kl < 0 or kl > 512:
			break
		var k := f.get_buffer(kl).get_string_from_utf8().to_lower()
		var vl := f.get_32()
		if vl < 0 or vl > 65536:
			break
		var v := f.get_buffer(vl).get_string_from_utf8()
		meta[k] = GameState._strip_rich_tags(v)
	var _fm_len := f.get_64()
	var fm_cnt := f.get_64()
	var files: Array[Dictionary] = []
	if fm_cnt <= 256:
		for _j in range(fm_cnt):
			var fnl := f.get_8()
			var fn := f.get_buffer(fnl).get_string_from_utf8()
			var cl := f.get_64()
			var ci := f.get_64()
			files.append({"name": fn, "len": cl, "idx": ci})
	return {
		"version": ver,
		"mask": mask,
		"metadata": meta,
		"files": files
	}

static func unmask_bytes(raw: PackedByteArray, mask: PackedByteArray) -> PackedByteArray:
	var lut := PackedByteArray()
	lut.resize(256)
	for c in range(256):
		lut[c] = mask[c & 15] ^ c
	var n := raw.size()
	for i in range(n):
		raw[i] = raw[i] ^ lut[i & 255]
	return raw

static func extract_file_bytes(path: String, hdr: Dictionary, filename: String) -> PackedByteArray:
	var f := FileAccess.open(path, FileAccess.READ)
	if not f:
		return PackedByteArray()
	var mask: PackedByteArray = hdr.get("mask", PackedByteArray())
	for fi in hdr.get("files", []):
		if str(fi["name"]).to_lower() == filename.to_lower():
			f.seek(int(fi["idx"]))
			var buf := f.get_buffer(int(fi["len"]))
			return unmask_bytes(buf, mask)
	return PackedByteArray()

static func get_available_difficulties(song_info: Dictionary) -> Array[String]:
	var saved = song_info.get("available_diffs", [])
	if typeof(saved) == TYPE_ARRAY and not saved.is_empty():
		var out: Array[String] = []
		for d in saved:
			var ds := str(d)
			if ds in ["Easy", "Medium", "Hard", "Expert"] and not out.has(ds):
				out.append(ds)
		if not out.is_empty():
			return out

	# Inspect actual chart inside .sng or loose folder without decoding audio
	var chart_data: Dictionary = {}
	if song_info.has("sng_path"):
		var sng_path := str(song_info["sng_path"])
		var hdr := peek_header(sng_path)
		if not hdr.is_empty():
			for fi in hdr.get("files", []):
				var fn := str(fi["name"]).to_lower()
				if fn.ends_with(".chart"):
					var raw := extract_file_bytes(sng_path, hdr, str(fi["name"]))
					if not raw.is_empty():
						chart_data = ChartParser.parse_chart_text(raw.get_string_from_utf8())
						break
				elif fn.ends_with(".mid") or fn.ends_with(".midi"):
					var raw := extract_file_bytes(sng_path, hdr, str(fi["name"]))
					if not raw.is_empty():
						chart_data = ChartParser.parse_midi_bytes(raw)
						break
	elif song_info.has("chart_path"):
		var cpath := str(song_info["chart_path"])
		var cf := FileAccess.open(cpath, FileAccess.READ)
		if cf:
			if cpath.to_lower().ends_with(".chart"):
				chart_data = ChartParser.parse_chart_text(cf.get_as_text())
			else:
				chart_data = ChartParser.parse_midi_bytes(cf.get_buffer(cf.get_length()))

	var charted = chart_data.get("charted_diffs", [])
	var res: Array[String] = []
	if typeof(charted) == TYPE_ARRAY:
		for d in charted:
			res.append(str(d))
	if res.is_empty():
		return ["Easy", "Medium", "Hard", "Expert"]
	return res

static func load_song_package(song_info: Dictionary) -> Dictionary:
	# Returns { "chart_data": Dictionary, "streams": Array[AudioStream], "album_tex": Texture2D, "error": String }
	if song_info.get("bundled", false) or song_info.has("chart_path"):
		return _load_loose_package(song_info)
	if song_info.has("sng_path"):
		return _load_sng_package(str(song_info["sng_path"]))
	return {"error": "Invalid song path"}

static func _load_loose_package(song_info: Dictionary) -> Dictionary:
	var cpath := str(song_info.get("chart_path", ""))
	var apath := str(song_info.get("audio_path", ""))
	var chart_data: Dictionary = {}
	if cpath.to_lower().ends_with(".chart"):
		var cf := FileAccess.open(cpath, FileAccess.READ)
		if not cf:
			return {"error": "Cannot open chart: " + cpath}
		chart_data = ChartParser.parse_chart_text(cf.get_as_text())
	else:
		var mf := FileAccess.open(cpath, FileAccess.READ)
		if not mf:
			return {"error": "Cannot open MIDI: " + cpath}
		chart_data = ChartParser.parse_midi_bytes(mf.get_buffer(mf.get_length()))

	var streams: Array[AudioStream] = []
	if apath.begins_with("res://"):
		var st = load(apath)
		if st is AudioStream:
			streams.append(st)
	else:
		var af := FileAccess.open(apath, FileAccess.READ)
		if af:
			var st := bytes_to_audio_stream(apath, af.get_buffer(af.get_length()))
			if st:
				streams.append(st)
	if streams.is_empty():
		return {"error": "Could not decode audio file"}
	return {
		"chart_data": chart_data,
		"streams": streams,
		"album_tex": null,
		"error": ""
	}

static func _load_sng_package(sng_path: String) -> Dictionary:
	var hdr := peek_header(sng_path)
	if hdr.is_empty():
		return {"error": "Invalid or corrupted .sng file"}
	var f := FileAccess.open(sng_path, FileAccess.READ)
	if not f:
		return {"error": "Cannot open .sng file"}
	var mask: PackedByteArray = hdr["mask"]
	var chart_data: Dictionary = {}
	var streams: Array[AudioStream] = []
	var album_tex: Texture2D = null

	# Priority stems so full multitrack Clone Hero songs play complete band + guitar + drums!
	var stem_prefixes := ["song.", "guitar.", "drums.", "drums_1.", "drums_2.", "drums_3.", "drums_4.", "bass.", "rhythm.", "keys.", "vocals."]

	for fi in hdr["files"]:
		var fn: String = str(fi["name"])
		var low := fn.to_lower()
		if low.ends_with(".chart"):
			f.seek(int(fi["idx"]))
			var raw := unmask_bytes(f.get_buffer(int(fi["len"])), mask)
			chart_data = ChartParser.parse_chart_text(raw.get_string_from_utf8())
		elif (low.ends_with(".mid") or low.ends_with(".midi")) and chart_data.is_empty():
			f.seek(int(fi["idx"]))
			var raw := unmask_bytes(f.get_buffer(int(fi["len"])), mask)
			chart_data = ChartParser.parse_midi_bytes(raw)
		elif low.begins_with("album.") and (low.ends_with(".jpg") or low.ends_with(".jpeg") or low.ends_with(".png") or low.ends_with(".webp")):
			f.seek(int(fi["idx"]))
			var raw := unmask_bytes(f.get_buffer(int(fi["len"])), mask)
			var img := Image.new()
			var err := ERR_FILE_UNRECOGNIZED
			if low.ends_with(".png"):
				err = img.load_png_from_buffer(raw)
			elif low.ends_with(".webp"):
				err = img.load_webp_from_buffer(raw)
			else:
				err = img.load_jpg_from_buffer(raw)
			if err == OK:
				album_tex = ImageTexture.create_from_image(img)
		elif low.ends_with(".opus") or low.ends_with(".ogg") or low.ends_with(".mp3") or low.ends_with(".wav"):
			var base := low.get_file()
			if base.begins_with("preview.") or base.begins_with("crowd."):
				continue
			var wanted := false
			for p in stem_prefixes:
				if base.begins_with(p):
					wanted = true
					break
			if wanted or streams.is_empty():
				f.seek(int(fi["idx"]))
				var raw := unmask_bytes(f.get_buffer(int(fi["len"])), mask)
				var st := bytes_to_audio_stream(low, raw)
				if st:
					streams.append(st)

	if chart_data.is_empty():
		return {"error": "No valid notes.chart or notes.mid inside .sng"}
	if streams.is_empty():
		return {"error": "No playable audio stream found inside .sng"}

	# Apply song.ini / sng header delay if chart offset wasn't set
	var meta: Dictionary = hdr.get("metadata", {})
	if meta.has("delay"):
		var delay_sec := float(meta["delay"]) / 1000.0
		if absf(delay_sec) > 0.0001 and absf(float(chart_data.get("offset", 0.0))) < 0.0001:
			ChartParser.apply_delay(chart_data, delay_sec)

	return {
		"chart_data": chart_data,
		"streams": streams,
		"album_tex": album_tex,
		"metadata": meta,
		"error": ""
	}

static func import_zip_to_folder(zip_path: String) -> Dictionary:
	var zr := ZIPReader.new()
	if zr.open(zip_path) != OK:
		return {"error": "Cannot open .zip archive"}
	var files := zr.get_files()
	if files.is_empty():
		zr.close()
		return {"error": "Empty .zip archive"}
	var folder_id := "zip_" + str(Time.get_unix_time_from_system())
	var out_dir := GameState.SONGS_DIR + "/" + folder_id
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	for zf in files:
		if zf.ends_with("/"):
			continue
		var base := zf.get_file()
		if base == "":
			continue
		var data := zr.read_file(zf)
		var wf := FileAccess.open(out_dir + "/" + base, FileAccess.WRITE)
		if wf:
			wf.store_buffer(data)
	zr.close()
	GameState.scan_library()
	return {"error": "", "folder": out_dir}

static func bytes_to_audio_stream(filename: String, raw: PackedByteArray) -> AudioStream:
	var low := filename.to_lower()
	if raw.size() < 12:
		return null
	# Detect Ogg Opus vs Ogg Vorbis by inspecting header signature
	var is_ogg := raw.slice(0, 4).get_string_from_ascii() == "OggS"
	var has_opus_head := false
	if is_ogg and raw.size() > 36:
		var head_Window := raw.slice(0, min(128, raw.size())).get_string_from_ascii()
		if head_Window.find("OpusHead") != -1:
			has_opus_head = true
	if low.ends_with(".opus") or has_opus_head:
		if ClassDB.class_exists("AudioStreamOpus"):
			var st = ClassDB.class_call_static("AudioStreamOpus", "load_from_buffer", raw)
			if st is AudioStream:
				return st
	if low.ends_with(".ogg") or (is_ogg and not has_opus_head):
		var vorbis := AudioStreamOggVorbis.load_from_buffer(raw)
		if vorbis:
			return vorbis
	if low.ends_with(".mp3") or (raw[0] == 0xFF and (raw[1] & 0xE0) == 0xE0) or raw.slice(0, 3).get_string_from_ascii() == "ID3":
		var mp3 := AudioStreamMP3.new()
		mp3.data = raw
		return mp3
	if low.ends_with(".wav") or raw.slice(0, 4).get_string_from_ascii() == "RIFF":
		return _parse_wav_buffer(raw)
	# Fallback attempt Opus -> Vorbis -> MP3
	if ClassDB.class_exists("AudioStreamOpus"):
		var op = ClassDB.class_call_static("AudioStreamOpus", "load_from_buffer", raw)
		if op is AudioStream and op.get_length() > 0.1:
			return op
	var vb := AudioStreamOggVorbis.load_from_buffer(raw)
	if vb and vb.get_length() > 0.1:
		return vb
	return null

static func _parse_wav_buffer(raw: PackedByteArray) -> AudioStreamWAV:
	if raw.size() < 44:
		return null
	var spb := StreamPeerBuffer.new()
	spb.data_array = raw
	spb.big_endian = false
	spb.seek(22)
	var channels := spb.get_u16()
	var sample_rate := spb.get_u32()
	spb.seek(34)
	var bits := spb.get_u16()
	# Locate "data" chunk
	var pos := 12
	while pos + 8 < raw.size():
		var cid := raw.slice(pos, pos + 4).get_string_from_ascii()
		spb.seek(pos + 4)
		var csize := spb.get_u32()
		if cid == "data":
			var end_idx := mini(pos + 8 + csize, raw.size())
			var wav := AudioStreamWAV.new()
			wav.mix_rate = sample_rate
			wav.stereo = (channels >= 2)
			wav.format = AudioStreamWAV.FORMAT_16_BITS if bits == 16 else AudioStreamWAV.FORMAT_8_BITS
			wav.data = raw.slice(pos + 8, end_idx)
			return wav
		pos += 8 + csize
	return null
