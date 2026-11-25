# Copyright (c) 2026 ipungsx (https://github.com/ipungsx)
extends Node

const SAVE_PATH := "user://droidhero_v2_save.json"
const SONGS_DIR := "user://songs"

var settings: Dictionary = {
	"language": "",            # "" = system default, "en" or "id"
	"theme": "neon_cyber",
	"visualizer": "concert_arena", # concert_arena, neon_waveform, radial_spectrum, cyber_rain, plasma_aurora, minimal_dark
	"stage_lights_flash": true,    # toggleable strobe/blinking lights (turn off for slow songs)
	"board_style": "carbon",   # carbon, rosewood, obsidian
	"hit_window": "normal",    # strict, normal, lenient
	"haptics": true,           # subtle smartphone vibration on miss / star power
	"note_speed": 1.0,         # 0.7x .. 1.8x highway scroll speed
	"audio_offset_ms": 0.0,    # -150 .. +150 ms calibration
	"no_fail": false,          # casual mode without rock-out fail
	"strum_mode": false,
	"sfx_volume": 0.85,
	"music_volume": 1.0,
	"show_fps": true,
	"light_intensity": 1.0     # 0.4 .. 1.5 stage light intensity
}

var highscores: Dictionary = {} # key: song_id + ":" + diff -> {score, stars, accuracy, max_streak, fc}
var library: Array[Dictionary] = []

# Active session selection
var current_song: Dictionary = {}
var current_difficulty: String = "Expert" # Easy, Medium, Hard, Expert
var practice_start_sec: float = 0.0
var last_result: Dictionary = {}
var open_screen_on_menu: int = 0          # 0=Home, 1=SongList, 2=Difficulty
var intro_shown: bool = false

#Synthesized UI/SFX players
var _sfx_player: AudioStreamPlayer
var _sfx_miss: AudioStreamWAV
var _sfx_star: AudioStreamWAV
var _sfx_click: AudioStreamWAV

func _ready() -> void:
	Engine.max_fps = 60
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	get_tree().set_auto_accept_quit(false)
	get_tree().set_quit_on_go_back(false)
	_ensure_dirs()
	_setup_audio_buses()
	_build_sfx()
	load_data()
	I18n.init_from_settings(str(settings.get("language", "")))
	ThemeManager.current_theme_id = settings.get("theme", "neon_cyber")
	scan_library()

func _ensure_dirs() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SONGS_DIR))

func _setup_audio_buses() -> void:
	# Bus 0 = Master. Create Bus 1 = Music with SpectrumAnalyzer + LowPass for drum beat detection!
	if AudioServer.get_bus_index("Music") == -1:
		var idx := AudioServer.bus_count
		AudioServer.add_bus(idx)
		AudioServer.set_bus_name(idx, "Music")
		AudioServer.set_bus_send(idx, "Master")
		var spec := AudioEffectSpectrumAnalyzer.new()
		spec.buffer_length = 0.1
		spec.fft_size = AudioEffectSpectrumAnalyzer.FFT_SIZE_1024
		AudioServer.add_bus_effect(idx, spec, 0)

func get_music_spectrum() -> AudioEffectSpectrumAnalyzerInstance:
	var idx := AudioServer.get_bus_index("Music")
	if idx >= 0 and AudioServer.get_bus_effect_count(idx) > 0:
		return AudioServer.get_bus_effect_instance(idx, 0) as AudioEffectSpectrumAnalyzerInstance
	return null

func _build_sfx() -> void:
	_sfx_player = AudioStreamPlayer.new()
	add_child(_sfx_player)
	_sfx_click = _gen_tone_wav(880.0, 1320.0, 0.045, 0.28, false)
	_sfx_miss = _gen_tone_wav(155.0, 92.0, 0.14, 0.42, true)
	_sfx_star = _gen_tone_wav(523.25, 1046.5, 0.28, 0.40, false)

func _gen_tone_wav(f0: float, f1: float, dur: float, amp: float, noisy: bool) -> AudioStreamWAV:
	var sr := 22050
	var n := int(sr * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	var phase := 0.0
	for i in range(n):
		var t := float(i) / float(sr)
		var prog := t / dur
		var f := lerpf(f0, f1, prog)
		phase += TAU * f / float(sr)
		var env := (1.0 - prog) * minf(1.0, t / 0.004)
		var s := sin(phase) + 0.35 * sin(phase * 2.0)
		if noisy:
			s = s * 0.6 + sin(phase * 3.73) * 0.5
		var pcm := clampi(int(s * env * amp * 32000.0), -32767, 32767)
		data[i * 2] = pcm & 0xFF
		data[i * 2 + 1] = (pcm >> 8) & 0xFF
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sr
	wav.stereo = false
	wav.data = data
	return wav

func trigger_haptic(duration_ms: int = 25) -> void:
	if bool(settings.get("haptics", true)):
		Input.vibrate_handheld(duration_ms)

func get_total_stars() -> int:
	var total := 0
	for k in highscores.keys():
		var d: Dictionary = highscores[k]
		total += int(d.get("stars", 0))
	return total

func play_click() -> void:
	if settings.get("sfx_volume", 0.85) <= 0.01:
		return
	_sfx_player.stream = _sfx_click
	_sfx_player.volume_db = linear_to_db(settings.get("sfx_volume", 0.85) * 0.6)
	_sfx_player.play()

func play_miss() -> void:
	if settings.get("sfx_volume", 0.85) <= 0.01:
		return
	_sfx_player.stream = _sfx_miss
	_sfx_player.volume_db = linear_to_db(settings.get("sfx_volume", 0.85) * 0.75)
	_sfx_player.play()

func play_star_sfx() -> void:
	if settings.get("sfx_volume", 0.85) <= 0.01:
		return
	_sfx_player.stream = _sfx_star
	_sfx_player.volume_db = linear_to_db(settings.get("sfx_volume", 0.85) * 0.9)
	_sfx_player.play()

func load_data() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not f:
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) == TYPE_DICTIONARY:
		if parsed.has("settings") and typeof(parsed["settings"]) == TYPE_DICTIONARY:
			for k in parsed["settings"].keys():
				settings[k] = parsed["settings"][k]
		if parsed.has("highscores") and typeof(parsed["highscores"]) == TYPE_DICTIONARY:
			highscores = parsed["highscores"]

func save_data() -> void:
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify({
			"settings": settings,
			"highscores": highscores
		}, "\t"))

func record_score(song_id: String, diff: String, result: Dictionary) -> bool:
	var key := song_id + ":" + diff
	var prev: Dictionary = highscores.get(key, {})
	var prev_score: int = int(prev.get("score", 0))
	var is_new_best: bool = int(result.get("score", 0)) > prev_score
	if is_new_best or prev.is_empty():
		highscores[key] = {
			"score": int(result.get("score", 0)),
			"stars": int(result.get("stars", 1)),
			"accuracy": float(result.get("accuracy", 0.0)),
			"max_streak": int(result.get("max_streak", 0)),
			"fc": bool(result.get("fc", false))
		}
		save_data()
	return is_new_best

func get_best(song_id: String, diff: String) -> Dictionary:
	return highscores.get(song_id + ":" + diff, {})

func scan_library() -> void:
	library.clear()
	# 1. Always include built-in Neon Overdrive anthem
	library.append({
		"id": "bundled_neon_overdrive",
		"name": "Neon Overdrive (DroidHero Anthem)",
		"artist": "DroidHero Studio",
		"album": "Arena Stage Vol. 1",
		"charter": "DroidHeroV2",
		"genre": "Synth Rock",
		"year": "2026",
		"song_length": 48000,
		"diff_guitar": 4,
		"bundled": true,
		"chart_path": "res://assets/bundled/neon_overdrive.chart",
		"audio_path": "res://assets/bundled/neon_overdrive.wav"
	})
	# 2. Scan downloaded songs in user://songs/
	var dir := DirAccess.open(SONGS_DIR)
	if not dir:
		return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not dir.current_is_dir() and fname.ends_with(".sng"):
			var full_sng := SONGS_DIR + "/" + fname
			var meta_path := full_sng + ".json"
			var entry: Dictionary = {}
			if FileAccess.file_exists(meta_path):
				var mf := FileAccess.open(meta_path, FileAccess.READ)
				if mf:
					var j = JSON.parse_string(mf.get_as_text())
					if typeof(j) == TYPE_DICTIONARY:
						entry = j
			if entry.is_empty():
				var hdr := SngParser.peek_header(full_sng)
				if not hdr.is_empty():
					var m: Dictionary = hdr.get("metadata", {})
					entry = {
						"id": fname.get_basename(),
						"md5": fname.get_basename(),
						"name": m.get("name", fname.get_basename()),
						"artist": m.get("artist", "Unknown Artist"),
						"album": m.get("album", ""),
						"charter": m.get("charter", m.get("frets", "Community")),
						"genre": m.get("genre", "Rock"),
						"year": m.get("year", ""),
						"song_length": int(m.get("song_length", "180000")),
						"diff_guitar": int(m.get("diff_guitar", "3"))
					}
			if not entry.is_empty():
				entry["bundled"] = false
				entry["sng_path"] = full_sng
				library.append(entry)
		elif dir.current_is_dir() and not fname.begins_with("."):
			var folder := SONGS_DIR + "/" + fname
			var folder_entry := _scan_song_folder(folder, fname)
			if not folder_entry.is_empty():
				library.append(folder_entry)
		fname = dir.get_next()
	dir.list_dir_end()

func _scan_song_folder(folder: String, id_name: String) -> Dictionary:
	var chart_file := ""
	var audio_file := ""
	var d := DirAccess.open(folder)
	if not d:
		return {}
	d.list_dir_begin()
	var f := d.get_next()
	while f != "":
		var low := f.to_lower()
		if low.ends_with(".chart") or low.ends_with(".mid") or low.ends_with(".midi"):
			if chart_file == "" or low == "notes.chart" or low == "notes.mid":
				chart_file = folder + "/" + f
		elif low.ends_with(".opus") or low.ends_with(".ogg") or low.ends_with(".mp3") or low.ends_with(".wav"):
			if audio_file == "" or low.begins_with("song.") or low.begins_with("guitar."):
				audio_file = folder + "/" + f
		f = d.get_next()
	d.list_dir_end()
	if chart_file == "" or audio_file == "":
		return {}
	var meta := {
		"id": "folder_" + id_name,
		"name": id_name,
		"artist": "Custom Import",
		"album": "",
		"charter": "Custom",
		"genre": "Rock",
		"song_length": 180000,
		"diff_guitar": 3,
		"bundled": false,
		"folder_path": folder,
		"chart_path": chart_file,
		"audio_path": audio_file
	}
	var ini_path := folder + "/song.ini"
	if FileAccess.file_exists(ini_path):
		var inf := FileAccess.open(ini_path, FileAccess.READ)
		if inf:
			for line in inf.get_as_text().split("\n"):
				var eq := line.find("=")
				if eq > 0:
					var k := line.substr(0, eq).strip_edges().to_lower()
					var v := line.substr(eq + 1).strip_edges()
					if k in ["name", "artist", "album", "charter", "genre", "year"]:
						meta[k] = _strip_rich_tags(v)
	return meta

static func _strip_rich_tags(s: String) -> String:
	var rx := RegEx.new()
	rx.compile("<[^>]+>")
	return rx.sub(s, "", true).strip_edges()
