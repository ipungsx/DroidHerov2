extends Control

# DroidHeroV2 HD Wide-Highway Guitar Engine (1600x720 60fps + Multi-Touch + Sustain Friction FX)

const BASE_PERFECT := 0.044
const BASE_GREAT := 0.088
const BASE_GOOD := 0.135
const MAX_SPARKS := 64

var _stage: ConcertStage
var _highway_canvas: Control
var _hud_layer: Control
var _pause_panel: PanelContainer
var _fail_panel: PanelContainer

# Audio players (single stream or synchronized multi-stem songs)
var _players: Array[AudioStreamPlayer] = []
var _song_duration: float = 30.0

# Chart & Note runtime state
var _chart: Dictionary = {}
var _notes: Array = []
var _beat_lines: Array = []
var _drums: Array = []
var _sections: Array = []

var _note_cursor: int = 0      # Earliest unresolved note head (for miss checks)
var _render_cursor: int = 0    # Earliest note whose sustain tail is still on screen!
var _beat_cursor: int = 0
var _drum_cursor: int = 0
var _section_cursor: int = 0

# Smooth drift-free clock
var _song_time: float = -2.4
var _audio_drift_avg: float = 0.0
var _started_audio: bool = false
var _paused: bool = false
var _failed: bool = false
var _finished: bool = false
var _speed_scale: float = 1.0
var _visible_ahead_sec: float = 1.40
var _audio_offset_sec: float = 0.0
var _win_scale: float = 1.0
var _beat_pulse: float = 0.0

# Scoring, Combo, Rock Meter, Star Power & Solo Tracking
var _score: int = 0
var _combo: int = 0
var _max_streak: int = 0
var _rock_meter: float = 60.0
var _star_power: float = 0.0
var _sp_active: bool = false
var _whammy_active: bool = false
var _whammy_key: bool = false
var _whammy_phase: float = 0.0

var _hits_perfect: int = 0
var _hits_great: int = 0
var _hits_good: int = 0
var _misses: int = 0
var _total_notes: int = 0
var _hit_offsets_ms: Array[float] = []

# Guitar Solo section tracker
var _in_solo: bool = false
var _solo_hits: int = 0
var _solo_total: int = 0
var _solo_bonus_total: int = 0

# Per-lane state (5 lanes: G, R, Y, B, O)
var _lane_pressed: Array[bool] = [false, false, false, false, false]
var _key_pressed: Array[bool] = [false, false, false, false, false]
var _fret_pop: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _lane_flash: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _hit_flames: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _hit_shock: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _sustain_spark_cd: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _active_sustains: Array = [null, null, null, null, null]
var _touch_to_lane: Dictionary = {}

# Zero-GC Spark Particle Pool (for hit sparks & continuous sustain grinding friction!)
var _spark_x: PackedFloat32Array = PackedFloat32Array()
var _spark_y: PackedFloat32Array = PackedFloat32Array()
var _spark_vx: PackedFloat32Array = PackedFloat32Array()
var _spark_vy: PackedFloat32Array = PackedFloat32Array()
var _spark_life: PackedFloat32Array = PackedFloat32Array()
var _spark_max: PackedFloat32Array = PackedFloat32Array()
var _spark_col: PackedColorArray = PackedColorArray()
var _spark_head: int = 0

# Judgement & Solo feedback
var _judge_text: String = "SIAP ROCK!"
var _judge_col: Color = Color.CYAN
var _judge_timer: float = 1.4
var _current_section: String = "Intro"

# HUD Controls
var _lbl_score: Label
var _lbl_combo: Label
var _lbl_mult: Label
var _lbl_acc: Label
var _lbl_section: Label
var _lbl_solo: Label
var _lbl_fps: Label
var _lbl_time: Label
var _pause_btn: Button
var _sp_btn: Button
var _whammy_btn: Button
var _progress_bar: ProgressBar

# Preallocated draw buffers
var _quad_pts: PackedVector2Array = PackedVector2Array()
var _quad_cols: PackedColorArray = PackedColorArray()
var _quad_uvs: PackedVector2Array = PackedVector2Array()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quad_pts.resize(4)
	_quad_cols.resize(4)
	_quad_uvs.resize(4)
	_spark_x.resize(MAX_SPARKS)
	_spark_y.resize(MAX_SPARKS)
	_spark_vx.resize(MAX_SPARKS)
	_spark_vy.resize(MAX_SPARKS)
	_spark_life.resize(MAX_SPARKS)
	_spark_max.resize(MAX_SPARKS)
	_spark_col.resize(MAX_SPARKS)
	_spark_life.fill(0.0)

	_speed_scale = clampf(float(GameState.practice_speed), 0.5, 1.5)
	var note_spd := clampf(float(GameState.settings.get("note_speed", 1.0)), 0.6, 2.0)
	_visible_ahead_sec = 1.38 / note_spd
	_audio_offset_sec = float(GameState.settings.get("audio_offset_ms", 0.0)) / 1000.0

	# Compute difficulty + setting hit window multiplier
	var hw_mode := str(GameState.settings.get("hit_window", "normal"))
	var mode_mul := 0.80 if hw_mode == "strict" else (1.22 if hw_mode == "lenient" else 1.0)
	var diff_mul := 1.0
	match GameState.current_difficulty:
		"Easy": diff_mul = 1.20
		"Medium": diff_mul = 1.12
		"Hard": diff_mul = 1.05
		_: diff_mul = 1.0
	_win_scale = mode_mul * diff_mul

	_build_scene_tree()
	_load_active_song()

func _build_scene_tree() -> void:
	# 1. Concert Stage Background
	_stage = ConcertStage.new()
	_stage.music_playing = false
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	# 2. HD Wide Perspective Guitar Highway Canvas
	_highway_canvas = Control.new()
	_highway_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highway_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highway_canvas.draw.connect(_draw_highway)
	add_child(_highway_canvas)

	# 3. Smartphone Upper HUD Overlay (completely clear of wide lower fretboard!)
	_hud_layer = Control.new()
	_hud_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_hud_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_hud_layer)

	var t := ThemeManager.get_theme_data()

	# Top Progress Bar
	_progress_bar = ProgressBar.new()
	_progress_bar.show_percentage = false
	_progress_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_progress_bar.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_progress_bar.offset_bottom = 8
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0, 0, 0, 0.6)
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = t["accent"]
	_progress_bar.add_theme_stylebox_override("background", pb_bg)
	_progress_bar.add_theme_stylebox_override("fill", pb_fg)
	_hud_layer.add_child(_progress_bar)

	# Top-Left HD Score & Accuracy Card (Portrait 720px width)
	var score_card := PanelContainer.new()
	score_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_card.position = Vector2(14, 34)
	score_card.custom_minimum_size = Vector2(335, 136)
	score_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 18, 2, 10))
	_hud_layer.add_child(score_card)

	var sc_vbox := VBoxContainer.new()
	sc_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc_vbox.add_theme_constant_override("separation", 2)
	score_card.add_child(sc_vbox)

	var song_title := Label.new()
	song_title.text = str(GameState.current_song.get("name", "Neon Overdrive")).left(22)
	if ThemeManager.font_semi:
		song_title.add_theme_font_override("font", ThemeManager.font_semi)
	song_title.add_theme_font_size_override("font_size", 20)
	song_title.add_theme_color_override("font_color", t["text_dim"])
	sc_vbox.add_child(song_title)

	_lbl_score = Label.new()
	_lbl_score.text = "0"
	if ThemeManager.font_display:
		_lbl_score.add_theme_font_override("font", ThemeManager.font_display)
	_lbl_score.add_theme_font_size_override("font_size", 42)
	_lbl_score.add_theme_color_override("font_color", t["text"])
	sc_vbox.add_child(_lbl_score)

	var meta_hb := HBoxContainer.new()
	meta_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc_vbox.add_child(meta_hb)

	_lbl_section = Label.new()
	_lbl_section.text = GameState.current_difficulty.to_upper() + _speed_tag()
	_lbl_section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lbl_section.clip_text = true
	if ThemeManager.font_body:
		_lbl_section.add_theme_font_override("font", ThemeManager.font_body)
	_lbl_section.add_theme_font_size_override("font_size", 19)
	_lbl_section.add_theme_color_override("font_color", t["accent"])
	meta_hb.add_child(_lbl_section)

	_lbl_acc = Label.new()
	_lbl_acc.text = "100%"
	if ThemeManager.font_display:
		_lbl_acc.add_theme_font_override("font", ThemeManager.font_display)
	_lbl_acc.add_theme_font_size_override("font_size", 19)
	_lbl_acc.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
	meta_hb.add_child(_lbl_acc)

	# Top-Right Multiplier, Streak, Time & Pause Card (Portrait 720px width)
	var right_card := PanelContainer.new()
	right_card.mouse_filter = Control.MOUSE_FILTER_PASS
	right_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_card.offset_left = -355
	right_card.offset_top = 34
	right_card.offset_right = -14
	right_card.offset_bottom = 170
	right_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["accent_2"], 18, 2, 10))
	_hud_layer.add_child(right_card)

	var rc_hbox := HBoxContainer.new()
	rc_hbox.add_theme_constant_override("separation", 10)
	rc_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	right_card.add_child(rc_hbox)

	_lbl_mult = Label.new()
	_lbl_mult.text = "1x"
	if ThemeManager.font_display:
		_lbl_mult.add_theme_font_override("font", ThemeManager.font_display)
	_lbl_mult.add_theme_font_size_override("font_size", 46)
	_lbl_mult.add_theme_color_override("font_color", t["accent"])
	_lbl_mult.custom_minimum_size = Vector2(84, 0)
	_lbl_mult.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rc_hbox.add_child(_lbl_mult)

	var st_vbox := VBoxContainer.new()
	st_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	st_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	rc_hbox.add_child(st_vbox)

	_lbl_combo = Label.new()
	_lbl_combo.text = "0 STREAK"
	if ThemeManager.font_body:
		_lbl_combo.add_theme_font_override("font", ThemeManager.font_body)
	_lbl_combo.add_theme_font_size_override("font_size", 24)
	_lbl_combo.add_theme_color_override("font_color", t["text"])
	st_vbox.add_child(_lbl_combo)

	_lbl_time = Label.new()
	_lbl_time.text = "0:00 / 0:00"
	if ThemeManager.font_semi:
		_lbl_time.add_theme_font_override("font", ThemeManager.font_semi)
	_lbl_time.add_theme_font_size_override("font_size", 18)
	_lbl_time.add_theme_color_override("font_color", t["text_dim"])
	st_vbox.add_child(_lbl_time)

	_lbl_fps = Label.new()
	_lbl_fps.text = "60 FPS"
	if ThemeManager.font_semi:
		_lbl_fps.add_theme_font_override("font", ThemeManager.font_semi)
	_lbl_fps.add_theme_font_size_override("font_size", 17)
	_lbl_fps.add_theme_color_override("font_color", t["accent_2"])
	_lbl_fps.visible = bool(GameState.settings.get("show_fps", true))
	st_vbox.add_child(_lbl_fps)

	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.custom_minimum_size = Vector2(68, 68)
	ThemeManager.style_button(_pause_btn, false)
	_pause_btn.add_theme_font_size_override("font_size", 28)
	_pause_btn.pressed.connect(_toggle_pause)
	rc_hbox.add_child(_pause_btn)

	# Solo Live Banner (Upper Center below top cards)
	_lbl_solo = Label.new()
	_lbl_solo.visible = false
	_lbl_solo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lbl_solo.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_lbl_solo.offset_left = -180
	_lbl_solo.offset_top = 186
	_lbl_solo.offset_right = 180
	_lbl_solo.offset_bottom = 228
	if ThemeManager.font_display:
		_lbl_solo.add_theme_font_override("font", ThemeManager.font_display)
	_lbl_solo.add_theme_font_size_override("font_size", 28)
	_lbl_solo.add_theme_color_override("font_color", t["star_power"])
	_hud_layer.add_child(_lbl_solo)

	# Upper-Left Star Power Trigger Button (neatly above horizon)
	_sp_btn = Button.new()
	_sp_btn.text = "STAR\n0%"
	_sp_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sp_btn.offset_left = 14
	_sp_btn.offset_top = 186
	_sp_btn.offset_right = 170
	_sp_btn.offset_bottom = 278
	ThemeManager.style_button(_sp_btn, true, t["star_power"])
	_sp_btn.add_theme_font_size_override("font_size", 21)
	_sp_btn.pressed.connect(_try_activate_star_power)
	_hud_layer.add_child(_sp_btn)

	# Upper-Right Whammy Bar Button (neatly above horizon)
	_whammy_btn = Button.new()
	_whammy_btn.text = "WHAMMY\nBAR"
	_whammy_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_whammy_btn.offset_left = -170
	_whammy_btn.offset_top = 186
	_whammy_btn.offset_right = -14
	_whammy_btn.offset_bottom = 278
	ThemeManager.style_button(_whammy_btn, false, t["accent_2"])
	_whammy_btn.add_theme_font_size_override("font_size", 21)
	_whammy_btn.button_down.connect(func(): _whammy_active = true)
	_whammy_btn.button_up.connect(func(): _whammy_active = false)
	_hud_layer.add_child(_whammy_btn)

	_build_overlays(t)

func _build_overlays(t: Dictionary) -> void:
	# Smartphone Pause Modal
	_pause_panel = PanelContainer.new()
	_pause_panel.visible = false
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.offset_left = -310
	_pause_panel.offset_top = -230
	_pause_panel.offset_right = 310
	_pause_panel.offset_bottom = 230
	_pause_panel.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.04, 0.04, 0.09, 0.97), t["accent"], 26, 3, 24))
	add_child(_pause_panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 18)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_panel.add_child(pv)

	var ptitle := Label.new()
	ptitle.text = "PERMAINAN DIJEDA"
	ptitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		ptitle.add_theme_font_override("font", ThemeManager.font_display)
	ptitle.add_theme_font_size_override("font_size", 36)
	ptitle.add_theme_color_override("font_color", t["accent"])
	pv.add_child(ptitle)

	var btn_resume := Button.new()
	btn_resume.text = "▶  LANJUTKAN MAIN"
	btn_resume.custom_minimum_size = Vector2(0, 76)
	ThemeManager.style_button(btn_resume, true)
	btn_resume.pressed.connect(_toggle_pause)
	pv.add_child(btn_resume)

	var btn_restart := Button.new()
	btn_restart.text = "↻  ULANGI LAGU"
	btn_restart.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_restart, false)
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	pv.add_child(btn_restart)

	var btn_quit := Button.new()
	btn_quit.text = "◀  KEMBALI KE DAFTAR LAGU"
	btn_quit.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_quit, false, t["accent_2"])
	btn_quit.pressed.connect(func():
		GameState.practice_speed = 1.0
		GameState.practice_start_sec = 0.0
		GameState.open_screen_on_menu = 1
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	pv.add_child(btn_quit)

	# Fail Modal
	_fail_panel = PanelContainer.new()
	_fail_panel.visible = false
	_fail_panel.set_anchors_preset(Control.PRESET_CENTER)
	_fail_panel.offset_left = -330
	_fail_panel.offset_top = -225
	_fail_panel.offset_right = 330
	_fail_panel.offset_bottom = 225
	_fail_panel.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.09, 0.02, 0.04, 0.98), Color(1.0, 0.2, 0.28), 26, 3, 24))
	add_child(_fail_panel)

	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 18)
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	_fail_panel.add_child(fv)

	var ftitle := Label.new()
	ftitle.text = "ROCK METER HABIS!"
	ftitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		ftitle.add_theme_font_override("font", ThemeManager.font_display)
	ftitle.add_theme_font_size_override("font_size", 38)
	ftitle.add_theme_color_override("font_color", Color(1.0, 0.25, 0.32))
	fv.add_child(ftitle)

	var fsub := Label.new()
	fsub.text = "Aktifkan No-Fail atau mode latihan 75% untuk berlatih bagian sulit."
	fsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fsub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		fsub.add_theme_font_override("font", ThemeManager.font_body)
	fsub.add_theme_font_size_override("font_size", 25)
	fv.add_child(fsub)

	var btn_retry := Button.new()
	btn_retry.text = "↻  COBA LAGI"
	btn_retry.custom_minimum_size = Vector2(0, 76)
	ThemeManager.style_button(btn_retry, true, Color(1.0, 0.28, 0.35))
	btn_retry.pressed.connect(func(): get_tree().reload_current_scene())
	fv.add_child(btn_retry)

	var btn_fquit := Button.new()
	btn_fquit.text = "◀  PILIH LAGU LAIN"
	btn_fquit.custom_minimum_size = Vector2(0, 72)
	ThemeManager.style_button(btn_fquit, false)
	btn_fquit.pressed.connect(func():
		GameState.open_screen_on_menu = 1
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	fv.add_child(btn_fquit)

func _speed_tag() -> String:
	if absf(_speed_scale - 1.0) > 0.02:
		return " • " + str(int(round(_speed_scale * 100.0))) + "%"
	return ""

func _load_active_song() -> void:
	if GameState.current_song.is_empty():
		GameState.scan_library()
		if not GameState.library.is_empty():
			GameState.current_song = GameState.library[0]

	var pkg := SngParser.load_song_package(GameState.current_song)
	if str(pkg.get("error", "")) != "":
		_judge_text = "LOAD ERROR: " + str(pkg["error"])
		_judge_col = Color.RED
		_judge_timer = 10.0
		return

	_chart = pkg["chart_data"]
	var tracks: Dictionary = _chart.get("tracks", {})
	var diff := GameState.current_difficulty
	if not tracks.has(diff) or tracks[diff].is_empty():
		diff = "Expert"
	_notes = tracks.get(diff, []).duplicate(true)
	_total_notes = _notes.size()
	_beat_lines = _chart.get("beat_lines", [])
	_drums = _chart.get("drums", [])
	_sections = _chart.get("sections", [])

	var streams: Array = pkg["streams"]
	_song_duration = 10.0
	var music_vol_db := linear_to_db(clampf(float(GameState.settings.get("music_volume", 1.0)), 0.02, 1.2))
	for st in streams:
		var p := AudioStreamPlayer.new()
		p.stream = st
		p.bus = "Music"
		p.pitch_scale = _speed_scale
		p.volume_db = music_vol_db
		add_child(p)
		_players.append(p)
		if st.get_length() > _song_duration:
			_song_duration = st.get_length()

	if not _notes.is_empty():
		var last_end := float(_notes[_notes.size() - 1]["end_time"]) + 2.2
		if last_end > _song_duration:
			_song_duration = last_end

	var start_s := maxf(0.0, GameState.practice_start_sec)
	_song_time = start_s - 2.2 * _speed_scale
	if start_s > 0.1:
		while _note_cursor < _notes.size() and float(_notes[_note_cursor]["time"]) < start_s:
			_notes[_note_cursor]["hit"] = true
			_note_cursor += 1
		_render_cursor = _note_cursor
		while _drum_cursor < _drums.size() and float(_drums[_drum_cursor]["time"]) < start_s:
			_drum_cursor += 1
		while _beat_cursor < _beat_lines.size() and float(_beat_lines[_beat_cursor]["time"]) < start_s:
			_beat_cursor += 1

func _is_music_audible() -> bool:
	if not _started_audio or _paused or _failed or _finished:
		return false
	if float(GameState.settings.get("music_volume", 1.0)) <= 0.02:
		return false
	for p in _players:
		if p.playing and not p.stream_paused:
			return true
	return false

func _spawn_spark(x: float, y: float, vx: float, vy: float, life: float, col: Color) -> void:
	var idx := _spark_head
	_spark_head = (_spark_head + 1) % MAX_SPARKS
	_spark_x[idx] = x
	_spark_y[idx] = y
	_spark_vx[idx] = vx
	_spark_vy[idx] = vy
	_spark_life[idx] = life
	_spark_max[idx] = life
	_spark_col[idx] = col

func _process(delta: float) -> void:
	if _paused or _failed or _finished:
		_stage.music_playing = false
		return

	# Smooth YARG-style real-time clock with gentle <=1.5% slew toward audio position (zero jitter!)
	var start_target := maxf(0.0, GameState.practice_start_sec)
	if not _started_audio:
		_song_time += delta * _speed_scale
		if _song_time >= start_target:
			_started_audio = true
			for p in _players:
				p.play(start_target)
	else:
		if not _players.is_empty() and _players[0].playing:
			var raw_pos := _players[0].get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
			var target_t := raw_pos - _audio_offset_sec
			var err := target_t - _song_time
			if absf(err) > 0.12:
				_song_time = target_t
				_audio_drift_avg = 0.0
			else:
				_audio_drift_avg = lerpf(_audio_drift_avg, err, minf(1.0, delta * 5.0))
				var slew := clampf(1.0 + _audio_drift_avg * 0.45, 0.985, 1.015)
				_song_time += delta * _speed_scale * slew
		else:
			_song_time += delta * _speed_scale

	_stage.music_playing = _is_music_audible()
	_beat_pulse = maxf(0.0, _beat_pulse - delta * 4.5)

	# Update progress, clock, & FPS
	_progress_bar.value = clampf((_song_time / maxf(1.0, _song_duration)) * 100.0, 0.0, 100.0)
	var cur_sec := maxi(0, int(_song_time))
	var tot_sec := maxi(1, int(_song_duration))
	_lbl_time.text = "%d:%02d / %d:%02d" % [cur_sec / 60, cur_sec % 60, tot_sec / 60, tot_sec % 60]
	if _lbl_fps.visible:
		_lbl_fps.text = str(Engine.get_frames_per_second()) + " FPS"

	# Trigger chart drum lighting cues only when music is actively playing
	while _drum_cursor < _drums.size() and float(_drums[_drum_cursor]["time"]) <= _song_time + 0.015:
		var dr: Dictionary = _drums[_drum_cursor]
		if _stage.music_playing:
			_stage.trigger_drum(int(dr["type"]), 1.05)
			if int(dr["type"]) == 0:
				_beat_pulse = 1.0
		_drum_cursor += 1

	# Advance section & Guitar Solo tracker
	while _section_cursor < _sections.size() and float(_sections[_section_cursor]["time"]) <= _song_time:
		var next_sec := str(_sections[_section_cursor]["name"])
		_handle_section_change(next_sec)
		_section_cursor += 1

	# Star Power drain
	if _sp_active:
		_star_power -= delta * 12.5
		if _star_power <= 0.0:
			_star_power = 0.0
			_sp_active = false
	_stage.star_power_active = _sp_active
	_stage.combo_level = _base_multiplier()
	_update_sp_button()

	# Animate 3D raised frets, hit flames, shockwaves, & active long-note sustain friction!
	_whammy_phase += delta * 20.0
	var any_sustain := false
	var sz := size
	var strike_y := sz.y * 0.835
	var strike_hw := sz.x * 0.478
	var cx := sz.x * 0.5

	for l in range(5):
		if _lane_pressed[l]:
			_fret_pop[l] = 1.0
		else:
			_fret_pop[l] = maxf(0.0, _fret_pop[l] - delta * 11.5)
		_lane_flash[l] = maxf(0.0, _lane_flash[l] - delta * 6.5)
		_hit_flames[l] = maxf(0.0, _hit_flames[l] - delta * 5.4)
		_hit_shock[l] = maxf(0.0, _hit_shock[l] - delta * 5.0)
		_sustain_spark_cd[l] = maxf(0.0, _sustain_spark_cd[l] - delta)

		var sn = _active_sustains[l]
		if sn != null:
			if not _lane_pressed[l]:
				# Finger released early -> mark sustain dropped so tail dims instead of vanishing
				sn["sustain_dropped"] = true
				_active_sustains[l] = null
			elif _song_time >= float(sn["end_time"]):
				sn["sustain_done"] = true
				_active_sustains[l] = null
			else:
				any_sustain = true
				var mult := _effective_multiplier()
				_score += int(round(delta * 140.0 * float(mult)))
				_hit_flames[l] = maxf(_hit_flames[l], 0.45)
				if _whammy_active:
					_star_power = minf(100.0, _star_power + delta * 11.5)
				elif bool(sn["sp"]):
					_star_power = minf(100.0, _star_power + delta * 6.5)

				# Continuous friction sparks spraying from the exact seam between round gem & long ribbon!
				if _sustain_spark_cd[l] <= 0.0 and sz.x > 10.0:
					_sustain_spark_cd[l] = 0.020
					var lf := ((float(l) + 0.5) / 5.0) * 2.0 - 1.0
					var rx := cx + lf * strike_hw
					var lane_w := strike_hw * 2.0 / 5.0
					var seam_y := strike_y - _fret_pop[l] * 18.0 - lane_w * 0.24
					var sp_col: Color = Color(0.55, 0.98, 1.0) if _sp_active else Color(1.0, 0.88, 0.35).lerp(ThemeManager.LANE_COLORS[l], 0.35)
					for s_i in range(2):
						var side := -1.0 if (s_i == 0) else 1.0
						var vx := side * randf_range(115.0, 320.0) + randf_range(-35.0, 35.0)
						var vy := randf_range(-340.0, -140.0)
						_spawn_spark(rx + side * randf_range(6.0, 22.0), seam_y, vx, vy, randf_range(0.16, 0.28), sp_col)

	# Update flying spark particles
	for idx in range(MAX_SPARKS):
		if _spark_life[idx] > 0.0:
			_spark_life[idx] -= delta
			_spark_x[idx] += _spark_vx[idx] * delta
			_spark_y[idx] += _spark_vy[idx] * delta
			_spark_vy[idx] += 760.0 * delta

	if not _players.is_empty():
		var bend := 1.0 + (sin(_whammy_phase) * 0.024 if (_whammy_active and any_sustain) else 0.0)
		for p in _players:
			p.pitch_scale = _speed_scale * bend

	# Advance _render_cursor ONLY after full note end_time has scrolled past!
	while _render_cursor < _notes.size() and float(_notes[_render_cursor]["end_time"]) < _song_time - 0.22:
		_render_cursor += 1

	# Check HOPO / Tap auto-catch
	_process_hopo_holds()

	# Miss notes whose head scrolled past GOOD window
	var good_win := BASE_GOOD * _win_scale * _speed_scale
	while _note_cursor < _notes.size():
		var n: Dictionary = _notes[_note_cursor]
		if bool(n["hit"]) or bool(n["missed"]):
			_note_cursor += 1
			continue
		if _song_time - float(n["time"]) > good_win:
			n["missed"] = true
			_on_note_missed()
			_note_cursor += 1
		else:
			break

	if _judge_timer > 0.0:
		_judge_timer = maxf(0.0, _judge_timer - delta)

	_update_hud_numbers()
	_highway_canvas.queue_redraw()

	if _started_audio and _song_time >= _song_duration:
		_complete_song()

func _handle_section_change(next_sec: String) -> void:
	# Finish previous Guitar Solo if exiting one
	if _in_solo and _solo_total > 0:
		var pct := int(round((float(_solo_hits) / float(_solo_total)) * 100.0))
		var bonus := _solo_hits * (120 if pct >= 95 else (75 if pct >= 85 else 35))
		_score += bonus
		_solo_bonus_total += bonus
		_judge_text = "SOLO %d%%  +%d!" % [pct, bonus]
		_judge_col = Color(0.25, 0.98, 1.0)
		_judge_timer = 1.35
		_in_solo = false
		_lbl_solo.visible = false

	_current_section = next_sec
	_lbl_section.text = GameState.current_difficulty.to_upper() + " • " + _current_section.to_upper() + _speed_tag()

	if "solo" in next_sec.to_lower():
		_in_solo = true
		_solo_hits = 0
		_solo_total = 0
		var next_sec_time := _song_duration
		if _section_cursor + 1 < _sections.size():
			next_sec_time = float(_sections[_section_cursor + 1]["time"])
		for i in range(_note_cursor, _notes.size()):
			var nt := float(_notes[i]["time"])
			if nt >= next_sec_time:
				break
			if nt >= _song_time - 0.05:
				_solo_total += 1
		if _solo_total > 0:
			_lbl_solo.visible = true
			_lbl_solo.text = "🎸 SOLO 100%"
		else:
			_in_solo = false

func _process_hopo_holds() -> void:
	if _combo <= 0:
		return
	var win := 0.045 * _win_scale * _speed_scale
	for i in range(_note_cursor, _notes.size()):
		var n: Dictionary = _notes[i]
		var dt := float(n["time"]) - _song_time
		if dt > win:
			break
		if bool(n["hit"]) or bool(n["missed"]):
			continue
		if (bool(n["hopo"]) or bool(n["tap"])) and absf(dt) <= win:
			var lane := int(n["lane"])
			if _lane_pressed[lane]:
				var higher_held := false
				if not bool(n["tap"]):
					for h in range(lane + 1, 5):
						if _lane_pressed[h]:
							higher_held = true
							break
				if not higher_held:
					_register_hit(n, 0.0, false)

func _input(event: InputEvent) -> void:
	if _paused or _failed or _finished:
		if event.is_action_pressed("ui_cancel"):
			_toggle_pause()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			if _pause_btn and _pause_btn.get_global_rect().grow(8.0).has_point(te.position):
				return
			if _sp_btn and _sp_btn.get_global_rect().grow(6.0).has_point(te.position):
				_touch_to_lane[te.index] = -1
				_try_activate_star_power()
				get_viewport().set_input_as_handled()
				return
			if _whammy_btn and _whammy_btn.get_global_rect().grow(6.0).has_point(te.position):
				_touch_to_lane[te.index] = -2
				_recompute_touch_lanes()
				get_viewport().set_input_as_handled()
				return
			var l := _pos_to_lane(te.position)
			if l >= 0:
				_touch_to_lane[te.index] = l
				_recompute_touch_lanes()
				_press_lane(l)
				get_viewport().set_input_as_handled()
		else:
			if _touch_to_lane.has(te.index):
				var prev_l: int = _touch_to_lane[te.index]
				_touch_to_lane.erase(te.index)
				_recompute_touch_lanes()
				if prev_l >= 0 and not _lane_pressed[prev_l]:
					_release_lane(prev_l)
				get_viewport().set_input_as_handled()

	elif event is InputEventScreenDrag:
		var de := event as InputEventScreenDrag
		if _touch_to_lane.has(de.index):
			var old_l: int = _touch_to_lane[de.index]
			if old_l >= 0:
				var new_l := _pos_to_lane(de.position)
				if new_l >= 0 and new_l != old_l:
					_touch_to_lane[de.index] = new_l
					_recompute_touch_lanes()
					if not _lane_pressed[old_l]:
						_release_lane(old_l)
					_press_lane(new_l)
			get_viewport().set_input_as_handled()

	elif event is InputEventKey:
		var ke := event as InputEventKey
		if ke.echo:
			return
		var lane := _key_to_lane(ke.keycode)
		if lane >= 0:
			_key_pressed[lane] = ke.pressed
			_recompute_touch_lanes()
			if ke.pressed:
				_press_lane(lane)
			elif not _lane_pressed[lane]:
				_release_lane(lane)
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_SPACE and ke.pressed:
			_try_activate_star_power()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_SHIFT:
			_whammy_key = ke.pressed
			_recompute_touch_lanes()
			get_viewport().set_input_as_handled()
		elif ke.keycode == KEY_ESCAPE and ke.pressed:
			_toggle_pause()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and not DisplayServer.is_touchscreen_available():
			if _pause_btn and _pause_btn.get_global_rect().has_point(mb.position):
				return
			if _sp_btn and _sp_btn.get_global_rect().has_point(mb.position):
				return
			if _whammy_btn and _whammy_btn.get_global_rect().has_point(mb.position):
				return
			var l := _pos_to_lane(mb.position)
			if l >= 0:
				if mb.pressed:
					_press_lane(l)
				else:
					_release_lane(l)

func _recompute_touch_lanes() -> void:
	for i in range(5):
		_lane_pressed[i] = _key_pressed[i]
	var whammy_held := _whammy_key
	for idx in _touch_to_lane.keys():
		var l: int = _touch_to_lane[idx]
		if l >= 0 and l < 5:
			_lane_pressed[l] = true
		elif l == -2:
			whammy_held = true
	_whammy_active = whammy_held

func _key_to_lane(code: Key) -> int:
	match code:
		KEY_A, KEY_1, KEY_Z: return 0
		KEY_S, KEY_2, KEY_X: return 1
		KEY_D, KEY_3, KEY_C, KEY_J: return 2
		KEY_F, KEY_4, KEY_V, KEY_K: return 3
		KEY_G, KEY_5, KEY_B, KEY_L, KEY_SEMICOLON: return 4
	return -1

func _pos_to_lane(pos: Vector2) -> int:
	var sz := size
	if sz.x <= 1.0 or sz.y <= 1.0:
		return -1
	# Wide ergonomic touch zone across the lower half of the portrait smartphone screen
	if pos.y < sz.y * 0.50:
		return -1
	var top_y := sz.y * 0.145
	var strike_y := sz.y * 0.835
	var bot_y := sz.y * 0.996
	var top_hw := sz.x * 0.255
	var strike_hw := sz.x * 0.478
	var bot_hw := sz.x * 0.498
	var cx := sz.x * 0.5
	var hw_y := strike_hw
	if pos.y <= strike_y:
		var ty := clampf((pos.y - top_y) / maxf(1.0, strike_y - top_y), 0.0, 1.0)
		hw_y = lerpf(top_hw, strike_hw, ty)
	else:
		var ty := clampf((pos.y - strike_y) / maxf(1.0, bot_y - strike_y), 0.0, 1.0)
		hw_y = lerpf(strike_hw, bot_hw, ty)
	var pad_x := sz.x * 0.06
	if pos.x < (cx - hw_y - pad_x) or pos.x > (cx + hw_y + pad_x):
		return -1
	var norm := (pos.x - (cx - hw_y)) / maxf(1.0, hw_y * 2.0)
	return clampi(int(floor(norm * 5.0)), 0, 4)

func _press_lane(lane: int) -> void:
	_lane_pressed[lane] = true
	_fret_pop[lane] = 1.0
	_lane_flash[lane] = 1.0

	var best_note = null
	var best_signed_dt := 0.0
	var best_err := 999.0
	var max_w := BASE_GOOD * _win_scale * _speed_scale
	for i in range(_note_cursor, _notes.size()):
		var n: Dictionary = _notes[i]
		var dt := _song_time - float(n["time"]) # positive = late, negative = early
		if -dt > max_w:
			break
		if bool(n["hit"]) or bool(n["missed"]):
			continue
		if int(n["lane"]) == lane and absf(dt) <= max_w:
			if absf(dt) < best_err:
				best_err = absf(dt)
				best_signed_dt = dt
				best_note = n
			break

	if best_note != null:
		_register_hit(best_note, best_signed_dt / _speed_scale, true)
	else:
		var near_any := false
		for i in range(_note_cursor, mini(_note_cursor + 8, _notes.size())):
			if absf(float(_notes[i]["time"]) - _song_time) <= max_w * 1.35:
				near_any = true
				break
		if not near_any and _started_audio and _combo > 0:
			_combo = 0
			_rock_meter = maxf(5.0, _rock_meter - 2.5)

func _release_lane(lane: int) -> void:
	_lane_pressed[lane] = false
	if _active_sustains[lane] != null:
		_active_sustains[lane]["sustain_dropped"] = true
		_active_sustains[lane] = null

func _register_hit(note: Dictionary, signed_err_sec: float, record_offset: bool) -> void:
	note["hit"] = true
	var abs_err_sec := absf(signed_err_sec)
	if record_offset and _started_audio:
		_hit_offsets_ms.append(signed_err_sec * 1000.0)

	var lane := int(note["lane"])
	_combo += 1
	if _combo > _max_streak:
		_max_streak = _combo
	if _in_solo:
		_solo_hits += 1
		var s_pct := int(round((float(_solo_hits) / float(maxi(1, _solo_total))) * 100.0))
		_lbl_solo.text = "🎸 SOLO %d%%" % s_pct

	var mult := _effective_multiplier()
	var perf_w := BASE_PERFECT * _win_scale
	var great_w := BASE_GREAT * _win_scale
	var base_pts := 50
	if abs_err_sec <= perf_w:
		_hits_perfect += 1
		base_pts = 135
		_hit_flames[lane] = 1.0
		_hit_shock[lane] = 1.0
		_judge_text = "PERFECT!"
		_judge_col = Color(0.18, 1.0, 0.88)
	elif abs_err_sec <= great_w:
		_hits_great += 1
		base_pts = 115
		_hit_flames[lane] = 0.82
		_hit_shock[lane] = 0.78
		_judge_text = "GREAT!"
		_judge_col = Color(0.35, 1.0, 0.42)
	else:
		_hits_good += 1
		base_pts = 100
		_hit_flames[lane] = 0.48
		_hit_shock[lane] = 0.50
		_judge_text = "GOOD"
		_judge_col = Color(1.0, 0.86, 0.22)
	_judge_timer = 0.50

	# Burst a few crisp hit sparks on tight timing
	if abs_err_sec <= great_w and size.x > 10.0:
		var lf := ((float(lane) + 0.5) / 5.0) * 2.0 - 1.0
		var rx := size.x * 0.5 + lf * (size.x * 0.478)
		var ry := size.y * 0.835 - 18.0
		var scol: Color = Color(0.55, 0.98, 1.0) if _sp_active else Color(1.0, 0.82, 0.28)
		for k in range(5):
			var ang := -PI * 0.5 + randf_range(-0.95, 0.95)
			var spd := randf_range(160.0, 360.0)
			_spawn_spark(rx, ry, cos(ang) * spd, sin(ang) * spd, randf_range(0.16, 0.26), scol)

	_score += base_pts * mult
	_rock_meter = minf(100.0, _rock_meter + (3.2 if _sp_active else 1.8))

	if bool(note["sp"]):
		_star_power = minf(100.0, _star_power + 9.0)
	elif _combo % 10 == 0:
		_star_power = minf(100.0, _star_power + 5.0)

	# Keep long sustain note active and locked onto the raised fret!
	if float(note["dur"]) > 0.08:
		note["sustain_dropped"] = false
		note["sustain_done"] = false
		_active_sustains[lane] = note

func _on_note_missed() -> void:
	_misses += 1
	if _combo >= 6:
		GameState.play_miss()
		GameState.trigger_haptic(28)
	_combo = 0
	_judge_text = "MISS"
	_judge_col = Color(1.0, 0.22, 0.30)
	_judge_timer = 0.50
	_rock_meter -= 5.8
	if _rock_meter <= 0.0:
		if bool(GameState.settings.get("no_fail", false)) or absf(_speed_scale - 1.0) > 0.02:
			_rock_meter = 8.0
		else:
			_rock_meter = 0.0
			_trigger_fail()

func _base_multiplier() -> int:
	if _combo >= 30: return 4
	if _combo >= 20: return 3
	if _combo >= 10: return 2
	return 1

func _effective_multiplier() -> int:
	return _base_multiplier() * (2 if _sp_active else 1)

func _try_activate_star_power() -> void:
	if not _sp_active and _star_power >= 50.0:
		_sp_active = true
		GameState.play_star_sfx()
		GameState.trigger_haptic(45)
		_stage.trigger_drum(0, 1.45)
		_stage.trigger_drum(1, 1.45)
		_judge_text = "STAR POWER! 2X"
		_judge_col = ThemeManager.get_theme_data()["star_power"]
		_judge_timer = 1.1

func _update_sp_button() -> void:
	var pct := int(round(_star_power))
	if _sp_active:
		_sp_btn.text = "⚡ OVERDRIVE!\n" + str(pct) + "%"
		_sp_btn.modulate = Color(1.2, 1.2, 1.2, 1.0)
	elif _star_power >= 50.0:
		var pulse := 0.88 + 0.18 * sin(_song_time * 9.0)
		_sp_btn.text = "⚡ AKTIFKAN!\n" + str(pct) + "%"
		_sp_btn.modulate = Color(pulse, 1.0, 1.0, 1.0)
	else:
		_sp_btn.text = "STAR POWER\n" + str(pct) + "%"
		_sp_btn.modulate = Color(0.75, 0.78, 0.85, 0.88)

func _update_hud_numbers() -> void:
	_lbl_score.text = _format_commas(_score)
	_lbl_combo.text = str(_combo) + " STREAK"
	var m := _effective_multiplier()
	_lbl_mult.text = str(m) + "x"
	var hit_so_far := _hits_perfect + _hits_great + _hits_good
	var seen := hit_so_far + _misses
	var live_acc := 100.0 if seen == 0 else (float(hit_so_far) / float(seen)) * 100.0
	_lbl_acc.text = "%.0f%% HIT" % live_acc
	var t := ThemeManager.get_theme_data()
	_lbl_mult.add_theme_color_override("font_color", t["star_power"] if _sp_active else (t["accent_2"] if m >= 4 else t["accent"]))

static func _format_commas(val: int) -> String:
	var s := str(val)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		if cnt > 0 and cnt % 3 == 0:
			out = "," + out
		out = s[i] + out
		cnt += 1
	return out

func _toggle_pause() -> void:
	if _failed or _finished:
		return
	_paused = not _paused
	_pause_panel.visible = _paused
	_touch_to_lane.clear()
	for i in range(5):
		_key_pressed[i] = false
		_lane_pressed[i] = false
	for p in _players:
		p.stream_paused = _paused

func _trigger_fail() -> void:
	_failed = true
	_stage.music_playing = false
	GameState.play_miss()
	GameState.trigger_haptic(80)
	for p in _players:
		p.stop()
	_fail_panel.visible = true

func _complete_song() -> void:
	_finished = true
	_stage.music_playing = false
	for p in _players:
		p.stop()
	if _in_solo and _solo_total > 0:
		_handle_section_change("Outro")

	var hit_total := _hits_perfect + _hits_great + _hits_good
	var denom := maxi(1, hit_total + _misses)
	var acc := (float(hit_total) / float(denom)) * 100.0
	var stars := 1
	if acc >= 92.0: stars = 5
	elif acc >= 82.0: stars = 4
	elif acc >= 70.0: stars = 3
	elif acc >= 55.0: stars = 2
	var is_fc := (_misses == 0 and hit_total > 0 and GameState.practice_start_sec <= 0.01)

	# Compute median signed timing error (ms) for Switch-Hero style timing calibration tip!
	var median_ms := 0.0
	if _hit_offsets_ms.size() >= 10:
		var sorted := _hit_offsets_ms.duplicate()
		sorted.sort()
		median_ms = sorted[sorted.size() / 2]

	var res := {
		"score": _score,
		"stars": stars,
		"accuracy": acc,
		"max_streak": _max_streak,
		"perfect": _hits_perfect,
		"great": _hits_great,
		"good": _hits_good,
		"missed": _misses,
		"total_notes": denom,
		"solo_bonus": _solo_bonus_total,
		"median_offset_ms": median_ms,
		"hit_samples": _hit_offsets_ms.size(),
		"fc": is_fc,
		"difficulty": GameState.current_difficulty,
		"practice": (absf(_speed_scale - 1.0) > 0.02 or GameState.practice_start_sec > 0.01)
	}
	if not bool(res["practice"]):
		res["new_best"] = GameState.record_score(str(GameState.current_song.get("id", "song")), GameState.current_difficulty, res)
	else:
		res["new_best"] = false
	GameState.last_result = res
	GameState.practice_speed = 1.0
	GameState.practice_start_sec = 0.0
	get_tree().change_scene_to_file("res://scenes/Results.tscn")

# ============================================================================
# 60FPS HIGH-DEFINITION WIDE PERSPECTIVE GUITAR RENDERER
# ============================================================================

func _project_depth(norm_ahead: float) -> float:
	var d := 1.0 - norm_ahead
	return pow(maxf(0.0, d), 1.80) if d >= 0.0 else - ( -d ) * 1.42

func _draw_highway() -> void:
	var sz := size
	var t := ThemeManager.get_theme_data()
	var top_y := sz.y * 0.145
	var strike_y := sz.y * 0.835
	var bot_y := sz.y * 0.996
	var top_hw := sz.x * 0.255
	var strike_hw := sz.x * 0.478
	var bot_hw := sz.x * 0.498
	var cx := sz.x * 0.5

	# 1. HD Textured Perspective Fretboard Deck (Carbon / Rosewood / Obsidian)
	var edge_col: Color = t["star_power"] if _sp_active else t["highway_edge"]
	var board_tex := HDAssets.get_board_texture(str(GameState.settings.get("board_style", "carbon")))
	_quad_pts[0] = Vector2(cx - top_hw, top_y)
	_quad_pts[1] = Vector2(cx + top_hw, top_y)
	_quad_pts[2] = Vector2(cx + bot_hw, bot_y)
	_quad_pts[3] = Vector2(cx - bot_hw, bot_y)
	if board_tex != null:
		var scroll_v := fmod(maxf(0.0, _song_time) * 1.8, 1.0)
		_quad_uvs[0] = Vector2(0.0, scroll_v)
		_quad_uvs[1] = Vector2(3.0, scroll_v)
		_quad_uvs[2] = Vector2(3.0, scroll_v + 4.0)
		_quad_uvs[3] = Vector2(0.0, scroll_v + 4.0)
		_quad_cols[0] = Color(0.85, 0.88, 0.95, 0.82)
		_quad_cols[1] = Color(0.85, 0.88, 0.95, 0.82)
		_quad_cols[2] = Color(1.0, 1.0, 1.0, 0.98)
		_quad_cols[3] = Color(1.0, 1.0, 1.0, 0.98)
		_highway_canvas.draw_polygon(_quad_pts, _quad_cols, _quad_uvs, board_tex)
	else:
		var hw_col: Color = t["highway"]
		_quad_cols.fill(hw_col)
		_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

	# Horizon top fade-in mist for smooth note entry
	var fade_y := lerpf(top_y, strike_y, 0.14)
	var fade_hw := lerpf(top_hw, strike_hw, 0.14)
	_quad_pts[0] = Vector2(cx - top_hw, top_y)
	_quad_pts[1] = Vector2(cx + top_hw, top_y)
	_quad_pts[2] = Vector2(cx + fade_hw, fade_y)
	_quad_pts[3] = Vector2(cx - fade_hw, fade_y)
	_quad_cols[0] = Color(0.02, 0.02, 0.05, 0.85)
	_quad_cols[1] = Color(0.02, 0.02, 0.05, 0.85)
	_quad_cols[2] = Color(0.02, 0.02, 0.05, 0.0)
	_quad_cols[3] = Color(0.02, 0.02, 0.05, 0.0)
	_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

	# Pressed lane beam & wide lower touch-pad glow
	for l in range(5):
		var lcol := ThemeManager.LANE_COLORS[l]
		if _sp_active:
			lcol = lcol.lerp(t["star_power"], 0.45)
		var f0 := float(l) / 5.0 * 2.0 - 1.0
		var f1 := float(l + 1) / 5.0 * 2.0 - 1.0

		var pad_alpha := 0.34 if _lane_pressed[l] else 0.10
		_quad_pts[0] = Vector2(cx + f0 * strike_hw, strike_y)
		_quad_pts[1] = Vector2(cx + f1 * strike_hw, strike_y)
		_quad_pts[2] = Vector2(cx + f1 * bot_hw, bot_y)
		_quad_pts[3] = Vector2(cx + f0 * bot_hw, bot_y)
		_quad_cols[0] = Color(lcol.r, lcol.g, lcol.b, pad_alpha * 0.45)
		_quad_cols[1] = Color(lcol.r, lcol.g, lcol.b, pad_alpha * 0.45)
		_quad_cols[2] = Color(lcol.r, lcol.g, lcol.b, pad_alpha)
		_quad_cols[3] = Color(lcol.r, lcol.g, lcol.b, pad_alpha)
		_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

		var energy := maxf(1.0 if _lane_pressed[l] else 0.0, _lane_flash[l] * 0.55)
		if energy > 0.02:
			_quad_pts[0] = Vector2(cx + f0 * top_hw, top_y)
			_quad_pts[1] = Vector2(cx + f1 * top_hw, top_y)
			_quad_pts[2] = Vector2(cx + f1 * strike_hw, strike_y)
			_quad_pts[3] = Vector2(cx + f0 * strike_hw, strike_y)
			_quad_cols[0] = Color(lcol.r, lcol.g, lcol.b, 0.02 * energy)
			_quad_cols[1] = Color(lcol.r, lcol.g, lcol.b, 0.02 * energy)
			_quad_cols[2] = Color(lcol.r, lcol.g, lcol.b, 0.25 * energy)
			_quad_cols[3] = Color(lcol.r, lcol.g, lcol.b, 0.25 * energy)
			_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

	# 2. Scrolling Metallic Fret Wires (Measure & Beat Lines)
	while _beat_cursor < _beat_lines.size() and float(_beat_lines[_beat_cursor]["time"]) < _song_time - 0.15:
		_beat_cursor += 1
	for i in range(_beat_cursor, _beat_lines.size()):
		var bt := float(_beat_lines[i]["time"])
		var norm := (bt - _song_time) / _visible_ahead_sec
		if norm > 1.0:
			break
		var p := _project_depth(norm)
		var y := lerpf(top_y, strike_y, p)
		if y > bot_y:
			continue
		var hw := lerpf(top_hw, strike_hw, p)
		var major := bool(_beat_lines[i]["major"])
		var fade_in := clampf((1.0 - norm) * 5.0, 0.0, 1.0)
		var a := clampf(p * (0.62 if major else 0.28) * fade_in, 0.03, 0.72)
		_highway_canvas.draw_line(Vector2(cx - hw, y), Vector2(cx + hw, y), Color(0.88, 0.94, 1.0, a), 3.6 if major else 1.8)

	# 3. Crisp HD Lane Divider Strings & Outer Chrome/Neon Rails
	for s in range(1, 5):
		var fn := float(s) / 5.0 * 2.0 - 1.0
		_highway_canvas.draw_line(
			Vector2(cx + fn * top_hw, top_y),
			Vector2(cx + fn * bot_hw, bot_y),
			Color(1.0, 1.0, 1.0, 0.24),
			2.2
		)
	var rail_w := 5.5 + _beat_pulse * 3.0
	# Outer metallic bevel + glowing inner rail
	_highway_canvas.draw_line(Vector2(cx - top_hw - 3, top_y), Vector2(cx - bot_hw - 4, bot_y), Color(0.18, 0.20, 0.26, 0.95), rail_w + 4.0)
	_highway_canvas.draw_line(Vector2(cx + top_hw + 3, top_y), Vector2(cx + bot_hw + 4, bot_y), Color(0.18, 0.20, 0.26, 0.95), rail_w + 4.0)
	_highway_canvas.draw_line(Vector2(cx - top_hw, top_y), Vector2(cx - bot_hw, bot_y), edge_col, rail_w)
	_highway_canvas.draw_line(Vector2(cx + top_hw, top_y), Vector2(cx + bot_hw, bot_y), edge_col, rail_w)

	# 4. Upper Side Meters (Rock Meter & Star Power tucked cleanly in upper half!)
	_draw_upper_side_meters(cx, top_y, strike_y, top_hw, strike_hw, t)

	# 5. Beat-Pulsing Strike Line & Base Unpressed Fret Sockets
	var strike_glow := 0.55 + _beat_pulse * 0.35
	_highway_canvas.draw_line(Vector2(cx - strike_hw, strike_y), Vector2(cx + strike_hw, strike_y), Color(1, 1, 1, strike_glow), 4.5 + _beat_pulse * 2.5)
	for l in range(5):
		if _fret_pop[l] <= 0.02:
			_draw_fret_3d(l, cx, strike_y, strike_hw)

	# 6. HD Multi-Layered Sustain Ribbons (uses _render_cursor so held notes NEVER vanish!)
	for i in range(_render_cursor, _notes.size()):
		var n: Dictionary = _notes[i]
		var head_norm := (float(n["time"]) - _song_time) / _visible_ahead_sec
		if head_norm > 1.02:
			break
		if float(n["dur"]) <= 0.06 or bool(n["missed"]) or bool(n["sustain_done"]):
			continue
		var tail_norm := (float(n["end_time"]) - _song_time) / _visible_ahead_sec
		if tail_norm <= 0.0:
			continue

		var lane := int(n["lane"])
		var held: bool = (_active_sustains[lane] == n)
		var dropped: bool = bool(n.get("sustain_dropped", false))

		# When hit & held (or dropped), clamp bottom of ribbon cleanly at strike line (0.0) so it feeds into the fret!
		var n0 := clampf(head_norm, 0.0 if bool(n["hit"]) else -0.12, 1.0)
		var n1 := clampf(tail_norm, 0.0, 1.0)
		if n1 <= n0:
			continue

		var p0 := _project_depth(n0)
		var p1 := _project_depth(n1)
		var y0 := lerpf(top_y, strike_y, p0)
		var y1 := lerpf(top_y, strike_y, p1)
		var hw0 := lerpf(top_hw, strike_hw, p0)
		var hw1 := lerpf(top_hw, strike_hw, p1)
		var lf := ((float(lane) + 0.5) / 5.0) * 2.0 - 1.0
		var x0 := cx + lf * hw0
		var x1 := cx + lf * hw1
		var lane_w0 := hw0 * 2.0 / 5.0
		var lane_w1 := hw1 * 2.0 / 5.0
		var w0 := lane_w0 * (0.28 if held else 0.21)
		var w1 := lane_w1 * (0.28 if held else 0.21)

		var scol: Color = t["star_power"] if (_sp_active or bool(n["sp"])) else ThemeManager.LANE_COLORS[lane]
		if dropped:
			scol = scol.darkened(0.45)

		if held:
			# Subtle grind vibration + Whammy wave along held sustain ribbon
			var vib := sin(_song_time * 46.0 + float(lane)) * (5.5 if _whammy_active else 2.2)
			x0 += vib * 0.35
			if _whammy_active:
				w0 *= 1.38

			# Outer plasma aura ribbon when actively held
			_quad_pts[0] = Vector2(x1 - w1 * 1.65, y1)
			_quad_pts[1] = Vector2(x1 + w1 * 1.65, y1)
			_quad_pts[2] = Vector2(x0 + w0 * 1.65, y0)
			_quad_pts[3] = Vector2(x0 - w0 * 1.65, y0)
			_quad_cols[0] = Color(scol.r, scol.g, scol.b, 0.14)
			_quad_cols[1] = Color(scol.r, scol.g, scol.b, 0.14)
			_quad_cols[2] = Color(scol.r, scol.g, scol.b, 0.36)
			_quad_cols[3] = Color(scol.r, scol.g, scol.b, 0.36)
			_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

		# Main sustain ribbon body
		var sa := 0.96 if held else (0.30 if dropped else 0.78)
		_quad_pts[0] = Vector2(x1 - w1, y1)
		_quad_pts[1] = Vector2(x1 + w1, y1)
		_quad_pts[2] = Vector2(x0 + w0, y0)
		_quad_pts[3] = Vector2(x0 - w0, y0)
		_quad_cols[0] = Color(scol.r, scol.g, scol.b, sa * 0.72)
		_quad_cols[1] = Color(scol.r, scol.g, scol.b, sa * 0.72)
		_quad_cols[2] = Color(scol.r, scol.g, scol.b, sa)
		_quad_cols[3] = Color(scol.r, scol.g, scol.b, sa)
		_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

		# Hot center core beam
		var core_a := 0.95 if held else (0.18 if dropped else 0.45)
		_highway_canvas.draw_line(Vector2(x1, y1), Vector2(x0, y0), Color(1, 1, 1, core_a), 4.6 if held else 2.6)

	# 7. HD Ray-Lit 3D Cut-Jewel Note Gems (Back-to-Front Painter's Order)
	var max_idx := _note_cursor
	while max_idx < _notes.size() and (float(_notes[max_idx]["time"]) - _song_time) <= _visible_ahead_sec:
		max_idx += 1
	for i in range(max_idx - 1, _note_cursor - 1, -1):
		if i < 0 or i >= _notes.size():
			continue
		var n: Dictionary = _notes[i]
		if bool(n["hit"]):
			continue
		var norm := (float(n["time"]) - _song_time) / _visible_ahead_sec
		if norm < -0.14 or norm > 1.0:
			continue
		var p := _project_depth(norm)
		var ny := lerpf(top_y, strike_y, p)
		var nhw := lerpf(top_hw, strike_hw, p)
		var lane := int(n["lane"])
		var lf := ((float(lane) + 0.5) / 5.0) * 2.0 - 1.0
		var nx := cx + lf * nhw
		var lane_w := nhw * 2.0 / 5.0
		var gw := lane_w * 0.88
		# Foreshorten gem height slightly near horizon for realistic 3D camera angle
		var perspective_flat := lerpf(0.78, 1.0, p)
		var gh := gw * 0.64 * perspective_flat
		var fade_a := clampf((1.0 - norm) * 6.5, 0.0, 1.0)
		var mod_col := Color(1, 1, 1, fade_a)
		if bool(n["missed"]):
			mod_col = Color(0.42, 0.42, 0.46, 0.52)

		var tex: Texture2D = null
		if (_sp_active or bool(n["sp"])) and not bool(n["missed"]):
			tex = HDAssets.gem_star_hopo if (bool(n["hopo"]) or bool(n["tap"])) else HDAssets.gem_star
			if HDAssets.radial_glow_tex != null:
				var gr := gw * 0.72
				_highway_canvas.draw_texture_rect(
					HDAssets.radial_glow_tex,
					Rect2(nx - gr, ny - gr * 0.65, gr * 2.0, gr * 1.3),
					false,
					Color(0.2, 0.96, 1.0, 0.34 * fade_a)
				)
		elif lane >= 0 and lane < HDAssets.gem_strum.size():
			if bool(n["tap"]):
				tex = HDAssets.gem_tap[lane]
			elif bool(n["hopo"]):
				tex = HDAssets.gem_hopo[lane]
			else:
				tex = HDAssets.gem_strum[lane]

		if tex != null:
			_highway_canvas.draw_texture_rect(
				tex,
				Rect2(nx - gw * 0.5, ny - gh * 0.52, gw, gh),
				false,
				mod_col
			)

	# 8. Popped-Up ("Timbul") 3D Raised Frets + Clamped Round Gem & Friction Seam with Long Sustain!
	for l in range(5):
		if _fret_pop[l] > 0.02:
			_draw_fret_3d(l, cx, strike_y, strike_hw)

		var sn = _active_sustains[l]
		if sn != null:
			var lf := ((float(l) + 0.5) / 5.0) * 2.0 - 1.0
			var rx := cx + lf * strike_hw
			var ry := strike_y - _fret_pop[l] * 18.0
			var lane_w := strike_hw * 2.0 / 5.0
			var gw := lane_w * 0.88
			var gh := gw * 0.64
			var scol: Color = t["star_power"] if (_sp_active or bool(sn["sp"])) else ThemeManager.LANE_COLORS[l]
			var grind_pulse := 0.86 + 0.24 * sin(_song_time * 54.0 + float(l) * 1.9)
			# High-frequency friction micro-vibration on the clamped round gem
			var vib_x := sin(_song_time * 78.0 + float(l)) * (3.8 if _whammy_active else 2.2)
			var vib_y := cos(_song_time * 66.0 + float(l)) * 1.4

			# 8a. Keep the Round 3D Jewel Note Gem ("not bulat") visibly locked & vibrating on the fret!
			var held_tex: Texture2D = null
			if _sp_active or bool(sn["sp"]):
				held_tex = HDAssets.gem_star_hopo if (bool(sn["hopo"]) or bool(sn["tap"])) else HDAssets.gem_star
			elif l >= 0 and l < HDAssets.gem_strum.size():
				if bool(sn["tap"]):
					held_tex = HDAssets.gem_tap[l]
				elif bool(sn["hopo"]):
					held_tex = HDAssets.gem_hopo[l]
				else:
					held_tex = HDAssets.gem_strum[l]
			if held_tex != null:
				_highway_canvas.draw_texture_rect(
					held_tex,
					Rect2(rx + vib_x - gw * 0.5, ry + vib_y - gh * 0.52, gw, gh),
					false,
					Color(1.12, 1.12, 1.12, 1.0)
				)

			# 8b. Vivid Friction / Grinding Contact Effect right at the seam between Round Gem & Long Ribbon!
			var seam_y := ry - gh * 0.28
			if HDAssets.radial_glow_tex != null:
				_highway_canvas.draw_texture_rect(
					HDAssets.radial_glow_tex,
					Rect2(rx - gw * 0.58, seam_y - gh * 0.45, gw * 1.16, gh * 0.90),
					false,
					Color(scol.r, scol.g, scol.b, 0.65 * grind_pulse)
				)
			# White-hot friction pinch seam across the upper rim of the round gem
			var seam_w := gw * (0.34 + 0.08 * sin(_song_time * 62.0))
			_highway_canvas.draw_line(
				Vector2(rx - seam_w, seam_y),
				Vector2(rx + seam_w, seam_y),
				Color(1.0, 0.96, 0.80, 0.96),
				5.2
			)
			# Sideways friction glare flares shooting left & right along the contact boundary
			var flare_w := gw * (0.48 + 0.14 * absf(sin(_song_time * 48.0 + float(l))))
			_highway_canvas.draw_line(
				Vector2(rx - flare_w, seam_y - 2.0),
				Vector2(rx + flare_w, seam_y - 2.0),
				Color(1.0, 0.78, 0.22, 0.78) if not _sp_active else Color(0.6, 0.98, 1.0, 0.85),
				2.8
			)
			# Bright hot friction core + vibrating shock ring at contact point
			_draw_ellipse(Vector2(rx + vib_x * 0.5, seam_y), gw * 0.22 * grind_pulse, gh * 0.16 * grind_pulse, Color(1.0, 0.98, 0.90, 0.96))
			_draw_ellipse_arc(Vector2(rx, seam_y), gw * 0.34 * grind_pulse, gh * 0.24 * grind_pulse, Color.WHITE, 2.8)

	# 9. Expanding Hit Shockwave Rings, Small Crisp Hit Flames, & Flying Friction Sparks
	for l in range(5):
		var lf := ((float(l) + 0.5) / 5.0) * 2.0 - 1.0
		var rx := cx + lf * strike_hw
		var rw := (strike_hw * 2.0 / 5.0) * 0.43
		var rh := rw * 0.50
		var base_y := strike_y - _fret_pop[l] * 18.0

		# Hit Shockwave Ring
		var sh := _hit_shock[l]
		if sh > 0.04 and HDAssets.ring_shock_tex != null:
			var expand := 1.0 + (1.0 - sh) * 0.85
			var sr_w := rw * 1.35 * expand
			var sr_h := rh * 1.35 * expand
			var scol: Color = t["star_power"] if _sp_active else ThemeManager.LANE_COLORS[l].lightened(0.35)
			_highway_canvas.draw_texture_rect(
				HDAssets.ring_shock_tex,
				Rect2(rx - sr_w, base_y - sr_h, sr_w * 2.0, sr_h * 2.0),
				false,
				Color(scol.r, scol.g, scol.b, sh * 0.78)
			)

		# Compact Crisp Hit Flame Lick (blue-white plasma in Star Power, warm gold-orange normally)
		var fl := _hit_flames[l]
		if fl > 0.04:
			var fy := base_y - rh * 0.22
			var fh := 32.0 * fl
			var fw := 14.0 * fl
			var outer_c := Color(0.18, 0.78, 1.0, 0.88 * fl) if _sp_active else Color(1.0, 0.42, 0.06, 0.88 * fl)
			var mid_c := Color(0.65, 0.96, 1.0, 0.94 * fl) if _sp_active else Color(1.0, 0.78, 0.18, 0.94 * fl)

			_quad_pts[0] = Vector2(rx, fy - fh)
			_quad_pts[1] = Vector2(rx + fw, fy - fh * 0.22)
			_quad_pts[2] = Vector2(rx, fy + 4.0 * fl)
			_quad_pts[3] = Vector2(rx - fw, fy - fh * 0.22)
			_quad_cols[0] = Color(outer_c.r, outer_c.g, outer_c.b, 0.0)
			_quad_cols[1] = outer_c
			_quad_cols[2] = mid_c
			_quad_cols[3] = outer_c
			_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

			_quad_pts[0] = Vector2(rx, fy - fh * 0.62)
			_quad_pts[1] = Vector2(rx + fw * 0.50, fy - fh * 0.12)
			_quad_pts[2] = Vector2(rx, fy + 2.0 * fl)
			_quad_pts[3] = Vector2(rx - fw * 0.50, fy - fh * 0.12)
			_quad_cols[0] = Color(1.0, 1.0, 0.85, 0.18 * fl)
			_quad_cols[1] = mid_c
			_quad_cols[2] = Color(1.0, 1.0, 0.96, 0.98 * fl)
			_quad_cols[3] = mid_c
			_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

	# Draw flying spark streaks (both note-hit sparks & continuous sustain grinding sparks!)
	for idx in range(MAX_SPARKS):
		var lf_rem := _spark_life[idx]
		if lf_rem > 0.0:
			var a := clampf(lf_rem / maxf(0.01, _spark_max[idx]), 0.0, 1.0)
			var p_now := Vector2(_spark_x[idx], _spark_y[idx])
			var p_tail := p_now - Vector2(_spark_vx[idx], _spark_vy[idx]) * 0.032
			var c := _spark_col[idx]
			_highway_canvas.draw_line(p_tail, p_now, Color(c.r, c.g, c.b, a * 0.92), 3.2)
			_highway_canvas.draw_circle(p_now, 2.6 * a + 1.0, Color(1.0, 1.0, 0.95, a))

	# 10. HD Judgement Callout Above Highway Center
	if _judge_timer > 0.01 and ThemeManager.font_display:
		var ja := clampf(_judge_timer * 2.6, 0.0, 1.0)
		var fsize := 36
		var jpos := Vector2(cx - 240.0, sz.y * 0.42 - (1.0 - ja) * 16.0)
		_highway_canvas.draw_string(
			ThemeManager.font_display,
			jpos + Vector2(0, 3),
			_judge_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			480.0,
			fsize,
			Color(0, 0, 0, ja * 0.72)
		)
		_highway_canvas.draw_string(
			ThemeManager.font_display,
			jpos,
			_judge_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			480.0,
			fsize,
			Color(_judge_col.r, _judge_col.g, _judge_col.b, ja)
		)

func _draw_fret_3d(l: int, cx: float, strike_y: float, strike_hw: float) -> void:
	var lf := ((float(l) + 0.5) / 5.0) * 2.0 - 1.0
	var rx := cx + lf * strike_hw
	var rw := (strike_hw * 2.0 / 5.0) * 0.43
	var rh := rw * 0.48
	var lcol := ThemeManager.LANE_COLORS[l]
	var pop := _fret_pop[l]
	var lift := pop * 18.0
	var sc := 1.0 + pop * 0.13
	var w := rw * sc
	var h := rh * sc

	# Outer metallic socket housing flush on fretboard
	_draw_ellipse(Vector2(rx, strike_y), rw * 1.06, rh * 1.06, Color(0.14, 0.15, 0.20, 0.96))
	_draw_ellipse(Vector2(rx, strike_y), rw * 0.96, rh * 0.96, Color(0.04, 0.04, 0.08, 0.98))

	if pop > 0.02:
		# Grounded 3D drop shadow
		_draw_ellipse(Vector2(rx, strike_y + 6.5 * pop), w * 1.08, h * 1.08, Color(0.0, 0.0, 0.0, 0.58 * pop))

		# 3D extruded metallic/colored piston cylinder rising upward
		var side_dark := lcol.darkened(0.50)
		var side_mid := lcol.darkened(0.22)
		_draw_ellipse(Vector2(rx, strike_y), w, h, side_dark)
		_quad_pts[0] = Vector2(rx - w, strike_y - lift)
		_quad_pts[1] = Vector2(rx + w, strike_y - lift)
		_quad_pts[2] = Vector2(rx + w, strike_y)
		_quad_pts[3] = Vector2(rx - w, strike_y)
		_quad_cols[0] = side_mid
		_quad_cols[1] = side_dark
		_quad_cols[2] = side_dark
		_quad_cols[3] = side_mid
		_highway_canvas.draw_polygon(_quad_pts, _quad_cols)
		_highway_canvas.draw_line(Vector2(rx - w, strike_y - lift), Vector2(rx - w, strike_y), lcol.lightened(0.30), 2.6)
		_highway_canvas.draw_line(Vector2(rx + w, strike_y - lift), Vector2(rx + w, strike_y), lcol.darkened(0.15), 2.6)

	# Top Fret Cap
	var top_c := Vector2(rx, strike_y - lift)
	var face_col := lcol.lightened(0.14) if pop > 0.25 else lcol.darkened(0.68)
	var rim_col := Color.WHITE.lerp(lcol, 0.45) if pop > 0.25 else lcol
	_draw_ellipse(top_c, w, h, face_col)
	_draw_ellipse_arc(top_c, w * 0.98, h * 0.98, rim_col, 5.0 if pop > 0.25 else 3.6)
	_draw_ellipse(top_c - Vector2(0.0, h * 0.20), w * 0.52, h * 0.40, Color(1.0, 1.0, 1.0, 0.18 + 0.65 * pop))

func _draw_upper_side_meters(_cx: float, _top_y: float, _strike_y: float, _top_hw: float, _strike_hw: float, t: Dictionary) -> void:
	# Tucked neatly along upper left & right screen edges below Star Power / Whammy buttons
	var sz := size
	var y_hi := 298.0
	var y_lo := minf(sz.y * 0.46, 620.0)
	var bar_h := maxf(120.0, y_lo - y_hi)

	# Upper-Left Segmented Rock Meter
	var rmx := 26.0
	_highway_canvas.draw_rect(Rect2(rmx - 10, y_hi, 20, bar_h), Color(0.04, 0.04, 0.08, 0.90), true)
	var segs := 14
	var rm_active := int(round((_rock_meter / 100.0) * float(segs)))
	var seg_h := (bar_h - 6.0) / float(segs)
	for s in range(segs):
		var sy := y_lo - 3.0 - float(s + 1) * seg_h
		var scol := Color(1.0, 0.22, 0.28) if s < 4 else (Color(1.0, 0.85, 0.18) if s < 9 else Color(0.14, 0.98, 0.50))
		var alpha := 0.95 if s < rm_active else 0.14
		_highway_canvas.draw_rect(Rect2(rmx - 7, sy + 1.5, 14, seg_h - 3.0), Color(scol.r, scol.g, scol.b, alpha), true)
	_highway_canvas.draw_rect(Rect2(rmx - 10, y_hi, 20, bar_h), Color(1, 1, 1, 0.35), false, 2.0)

	# Upper-Right Segmented Star Power Meter
	var spx := sz.x - 26.0
	_highway_canvas.draw_rect(Rect2(spx - 10, y_hi, 20, bar_h), Color(0.04, 0.04, 0.08, 0.90), true)
	var sp_c: Color = t["star_power"]
	var sp_active_segs := int(round((_star_power / 100.0) * float(segs)))
	for s in range(segs):
		var sy := y_lo - 3.0 - float(s + 1) * seg_h
		var ready := (_star_power >= 50.0 or _sp_active)
		var col := sp_c.lightened(0.2) if ready else sp_c.darkened(0.25)
		var alpha := 0.95 if s < sp_active_segs else 0.14
		_highway_canvas.draw_rect(Rect2(spx - 7, sy + 1.5, 14, seg_h - 3.0), Color(col.r, col.g, col.b, alpha), true)
	_highway_canvas.draw_line(Vector2(spx - 13, y_hi + bar_h * 0.5), Vector2(spx + 13, y_hi + bar_h * 0.5), Color.WHITE, 2.4)
	_highway_canvas.draw_rect(Rect2(spx - 10, y_hi, 20, bar_h), Color(1, 1, 1, 0.35), false, 2.0)

func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	_highway_canvas.draw_set_transform(center, 0.0, Vector2(1.0, ry / maxf(0.01, rx)))
	_highway_canvas.draw_circle(Vector2.ZERO, rx, col)
	_highway_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ellipse_arc(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	_highway_canvas.draw_set_transform(center, 0.0, Vector2(1.0, ry / maxf(0.01, rx)))
	_highway_canvas.draw_arc(Vector2.ZERO, rx, 0.0, TAU, 36, col, width)
	_highway_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
