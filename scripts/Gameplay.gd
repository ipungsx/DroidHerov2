extends Control

# DroidHeroV2 Full Guitar Hero Gameplay Engine (60fps Batched Canvas + Multi-touch + Keyboard)

const HIT_WINDOW_PERFECT := 0.045
const HIT_WINDOW_GREAT := 0.090
const HIT_WINDOW_GOOD := 0.140

var _stage: ConcertStage
var _highway_canvas: Control
var _hud_layer: Control
var _pause_panel: PanelContainer
var _fail_panel: PanelContainer

# Audio players (supports single stream or synchronized multi-stem Clone Hero songs)
var _players: Array[AudioStreamPlayer] = []
var _song_duration: float = 30.0

# Chart & Note runtime state
var _chart: Dictionary = {}
var _notes: Array = []
var _beat_lines: Array = []
var _drums: Array = []
var _sections: Array = []

var _note_cursor: int = 0      # Earliest un-resolved note index
var _beat_cursor: int = 0
var _drum_cursor: int = 0
var _section_cursor: int = 0

# Timing
var _song_time: float = -2.5
var _started_audio: bool = false
var _paused: bool = false
var _finished: bool = false
var _failed: bool = false
var _speed_scale: float = 1.0
var _visible_ahead_sec: float = 1.45
var _audio_offset_sec: float = 0.0

# Guitar Hero Scoring, Combo, Rock Meter & Star Power
var _score: int = 0
var _combo: int = 0
var _max_streak: int = 0
var _rock_meter: float = 55.0   # 0..100 (fails at 0 unless No-Fail)
var _star_power: float = 0.0    # 0..100 (deployable at >= 50%)
var _sp_active: bool = false
var _whammy_active: bool = false
var _whammy_key: bool = false
var _whammy_phase: float = 0.0

var _hits_perfect: int = 0
var _hits_great: int = 0
var _hits_good: int = 0
var _misses: int = 0
var _total_notes: int = 0

# Per-lane state (5 lanes: G, R, Y, B, O)
var _lane_pressed: Array[bool] = [false, false, false, false, false]
var _key_pressed: Array[bool] = [false, false, false, false, false]
var _fret_pop: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _lane_flash: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _hit_flames: Array[float] = [0.0, 0.0, 0.0, 0.0, 0.0]
var _active_sustains: Array = [null, null, null, null, null]
var _touch_to_lane: Dictionary = {} # finger index -> lane (0..4) or -1 (SP) or -2 (Whammy)

# Judgement banner feedback
var _judge_text: String = "GET READY!"
var _judge_col: Color = Color.CYAN
var _judge_timer: float = 1.5
var _current_section: String = "Intro"

# HUD Labels & Buttons
var _lbl_score: Label
var _lbl_combo: Label
var _lbl_mult: Label
var _lbl_section: Label
var _lbl_fps: Label
var _pause_btn: Button
var _sp_btn: Button
var _whammy_btn: Button
var _progress_bar: ProgressBar

# Preallocated draw polygon arrays for zero-GC 60fps rendering
var _quad_pts: PackedVector2Array = PackedVector2Array()
var _quad_cols: PackedColorArray = PackedColorArray()

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_quad_pts.resize(4)
	_quad_cols.resize(4)
	_speed_scale = clampf(float(GameState.practice_speed), 0.5, 1.5)
	var note_spd := clampf(float(GameState.settings.get("note_speed", 1.0)), 0.6, 2.0)
	_visible_ahead_sec = 1.42 / note_spd
	_audio_offset_sec = float(GameState.settings.get("audio_offset_ms", 0.0)) / 1000.0

	_build_scene_tree()
	_load_active_song()

func _build_scene_tree() -> void:
	# 1. Concert Arena Lighting & Drum Visualizer Background
	_stage = ConcertStage.new()
	_stage.music_playing = false
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	# 2. Custom 3D-Perspective Guitar Highway Canvas
	_highway_canvas = Control.new()
	_highway_canvas.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_highway_canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_highway_canvas.draw.connect(_draw_highway)
	add_child(_highway_canvas)

	# 3. HUD Overlay (MOUSE_FILTER_IGNORE so multi-touch fret taps never get swallowed)
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
	_progress_bar.offset_bottom = 6
	var pb_bg := StyleBoxFlat.new()
	pb_bg.bg_color = Color(0, 0, 0, 0.55)
	var pb_fg := StyleBoxFlat.new()
	pb_fg.bg_color = t["accent"]
	_progress_bar.add_theme_stylebox_override("background", pb_bg)
	_progress_bar.add_theme_stylebox_override("fill", pb_fg)
	_hud_layer.add_child(_progress_bar)

	# Top-Left Score & Song Card
	var score_card := PanelContainer.new()
	score_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	score_card.position = Vector2(12, 12)
	score_card.custom_minimum_size = Vector2(215, 86)
	score_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 12, 2, 8))
	_hud_layer.add_child(score_card)

	var sc_vbox := VBoxContainer.new()
	sc_vbox.mouse_filter = Control.MOUSE_FILTER_IGNORE
	sc_vbox.add_theme_constant_override("separation", 1)
	score_card.add_child(sc_vbox)

	var song_title := Label.new()
	song_title.text = str(GameState.current_song.get("name", "Neon Overdrive")).left(26)
	if ThemeManager.font_semi:
		song_title.add_theme_font_override("font", ThemeManager.font_semi)
	song_title.add_theme_font_size_override("font_size", 14)
	song_title.add_theme_color_override("font_color", t["text_dim"])
	sc_vbox.add_child(song_title)

	_lbl_score = Label.new()
	_lbl_score.text = "0"
	if ThemeManager.font_display:
		_lbl_score.add_theme_font_override("font", ThemeManager.font_display)
	_lbl_score.add_theme_font_size_override("font_size", 28)
	_lbl_score.add_theme_color_override("font_color", t["text"])
	sc_vbox.add_child(_lbl_score)

	_lbl_section = Label.new()
	_lbl_section.text = GameState.current_difficulty.to_upper() + (_speed_tag())
	if ThemeManager.font_body:
		_lbl_section.add_theme_font_override("font", ThemeManager.font_body)
	_lbl_section.add_theme_font_size_override("font_size", 14)
	_lbl_section.add_theme_color_override("font_color", t["accent"])
	sc_vbox.add_child(_lbl_section)

	# Top-Right Multiplier, Streak & Pause
	var right_card := PanelContainer.new()
	right_card.mouse_filter = Control.MOUSE_FILTER_PASS
	right_card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	right_card.offset_left = -250
	right_card.offset_top = 12
	right_card.offset_right = -12
	right_card.offset_bottom = 100
	right_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["accent_2"], 12, 2, 8))
	_hud_layer.add_child(right_card)

	var rc_hbox := HBoxContainer.new()
	rc_hbox.add_theme_constant_override("separation", 10)
	right_card.add_child(rc_hbox)

	_lbl_mult = Label.new()
	_lbl_mult.text = "1x"
	if ThemeManager.font_display:
		_lbl_mult.add_theme_font_override("font", ThemeManager.font_display)
	_lbl_mult.add_theme_font_size_override("font_size", 34)
	_lbl_mult.add_theme_color_override("font_color", t["accent"])
	_lbl_mult.custom_minimum_size = Vector2(68, 0)
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
	_lbl_combo.add_theme_font_size_override("font_size", 19)
	_lbl_combo.add_theme_color_override("font_color", t["text"])
	st_vbox.add_child(_lbl_combo)

	_lbl_fps = Label.new()
	_lbl_fps.text = "60 FPS"
	if ThemeManager.font_semi:
		_lbl_fps.add_theme_font_override("font", ThemeManager.font_semi)
	_lbl_fps.add_theme_font_size_override("font_size", 14)
	_lbl_fps.add_theme_color_override("font_color", t["text_dim"])
	_lbl_fps.visible = bool(GameState.settings.get("show_fps", true))
	st_vbox.add_child(_lbl_fps)

	_pause_btn = Button.new()
	_pause_btn.text = "II"
	_pause_btn.custom_minimum_size = Vector2(48, 48)
	ThemeManager.style_button(_pause_btn, false)
	_pause_btn.pressed.connect(_toggle_pause)
	rc_hbox.add_child(_pause_btn)

	# Left Interactive Star Power Overdrive Trigger Button (positioned above bottom thumb zone)
	_sp_btn = Button.new()
	_sp_btn.text = "STAR\n0%"
	_sp_btn.set_anchors_preset(Control.PRESET_TOP_LEFT)
	_sp_btn.offset_left = 12
	_sp_btn.offset_top = 112
	_sp_btn.offset_right = 120
	_sp_btn.offset_bottom = 186
	ThemeManager.style_button(_sp_btn, true, t["star_power"])
	_sp_btn.add_theme_font_size_override("font_size", 16)
	_sp_btn.pressed.connect(_try_activate_star_power)
	_hud_layer.add_child(_sp_btn)

	# Right Interactive Whammy Bar Button (positioned above bottom thumb zone)
	_whammy_btn = Button.new()
	_whammy_btn.text = "WHAMMY"
	_whammy_btn.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	_whammy_btn.offset_left = -120
	_whammy_btn.offset_top = 112
	_whammy_btn.offset_right = -12
	_whammy_btn.offset_bottom = 186
	ThemeManager.style_button(_whammy_btn, false, t["accent_2"])
	_whammy_btn.add_theme_font_size_override("font_size", 16)
	_whammy_btn.button_down.connect(func(): _whammy_active = true)
	_whammy_btn.button_up.connect(func(): _whammy_active = false)
	_hud_layer.add_child(_whammy_btn)

	_build_overlays(t)

func _build_overlays(t: Dictionary) -> void:
	# Pause Modal
	_pause_panel = PanelContainer.new()
	_pause_panel.visible = false
	_pause_panel.set_anchors_preset(Control.PRESET_CENTER)
	_pause_panel.offset_left = -195
	_pause_panel.offset_top = -145
	_pause_panel.offset_right = 195
	_pause_panel.offset_bottom = 145
	_pause_panel.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.04, 0.04, 0.09, 0.96), t["accent"], 18, 3, 16))
	add_child(_pause_panel)

	var pv := VBoxContainer.new()
	pv.add_theme_constant_override("separation", 10)
	pv.alignment = BoxContainer.ALIGNMENT_CENTER
	_pause_panel.add_child(pv)

	var ptitle := Label.new()
	ptitle.text = "STAGE PAUSED"
	ptitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		ptitle.add_theme_font_override("font", ThemeManager.font_display)
	ptitle.add_theme_font_size_override("font_size", 24)
	ptitle.add_theme_color_override("font_color", t["accent"])
	pv.add_child(ptitle)

	var btn_resume := Button.new()
	btn_resume.text = "RESUME SHOW"
	btn_resume.custom_minimum_size = Vector2(0, 48)
	ThemeManager.style_button(btn_resume, true)
	btn_resume.pressed.connect(_toggle_pause)
	pv.add_child(btn_resume)

	var btn_restart := Button.new()
	btn_restart.text = "RESTART SONG"
	btn_restart.custom_minimum_size = Vector2(0, 48)
	ThemeManager.style_button(btn_restart, false)
	btn_restart.pressed.connect(func(): get_tree().reload_current_scene())
	pv.add_child(btn_restart)

	var btn_quit := Button.new()
	btn_quit.text = "BACK TO SONG LIST"
	btn_quit.custom_minimum_size = Vector2(0, 48)
	ThemeManager.style_button(btn_quit, false, t["accent_2"])
	btn_quit.pressed.connect(func():
		GameState.practice_speed = 1.0
		GameState.practice_start_sec = 0.0
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	pv.add_child(btn_quit)

	# Rocked Out Fail Modal
	_fail_panel = PanelContainer.new()
	_fail_panel.visible = false
	_fail_panel.set_anchors_preset(Control.PRESET_CENTER)
	_fail_panel.offset_left = -210
	_fail_panel.offset_top = -145
	_fail_panel.offset_right = 210
	_fail_panel.offset_bottom = 145
	_fail_panel.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.09, 0.02, 0.04, 0.97), Color(1.0, 0.2, 0.28), 18, 3, 18))
	add_child(_fail_panel)

	var fv := VBoxContainer.new()
	fv.add_theme_constant_override("separation", 10)
	fv.alignment = BoxContainer.ALIGNMENT_CENTER
	_fail_panel.add_child(fv)

	var ftitle := Label.new()
	ftitle.text = "SONG FAILED!"
	ftitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		ftitle.add_theme_font_override("font", ThemeManager.font_display)
	ftitle.add_theme_font_size_override("font_size", 26)
	ftitle.add_theme_color_override("font_color", Color(1.0, 0.25, 0.32))
	fv.add_child(ftitle)

	var fsub := Label.new()
	fsub.text = "Rock Meter depleted! Try No-Fail or Practice 75%."
	fsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	fsub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		fsub.add_theme_font_override("font", ThemeManager.font_body)
	fsub.add_theme_font_size_override("font_size", 18)
	fv.add_child(fsub)

	var btn_retry := Button.new()
	btn_retry.text = "TRY AGAIN"
	btn_retry.custom_minimum_size = Vector2(0, 48)
	ThemeManager.style_button(btn_retry, true, Color(1.0, 0.28, 0.35))
	btn_retry.pressed.connect(func(): get_tree().reload_current_scene())
	fv.add_child(btn_retry)

	var btn_fquit := Button.new()
	btn_fquit.text = "EXIT TO MENU"
	btn_fquit.custom_minimum_size = Vector2(0, 46)
	ThemeManager.style_button(btn_fquit, false)
	btn_fquit.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/MainMenu.tscn"))
	fv.add_child(btn_fquit)

func _speed_tag() -> String:
	if absf(_speed_scale - 1.0) > 0.02:
		return " • PRACTICE " + str(int(round(_speed_scale * 100.0))) + "%"
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

	#Ensure duration covers final note + 2s
	if not _notes.is_empty():
		var last_end := float(_notes[_notes.size() - 1]["end_time"]) + 2.2
		if last_end > _song_duration:
			_song_duration = last_end

	var start_s := maxf(0.0, GameState.practice_start_sec)
	_song_time = start_s - 2.2 * _speed_scale
	# Advance cursors if starting mid-song in Practice Mode
	if start_s > 0.1:
		while _note_cursor < _notes.size() and float(_notes[_note_cursor]["time"]) < start_s:
			_notes[_note_cursor]["hit"] = true
			_note_cursor += 1
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

func _process(delta: float) -> void:
	if _paused or _failed or _finished:
		_stage.music_playing = false
		return

	# Advance clock with hardware latency-compensated audio sync
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
			if absf(target_t - _song_time) > 0.085:
				_song_time = target_t
			else:
				_song_time = lerpf(_song_time + delta * _speed_scale, target_t, 0.25)
		else:
			_song_time += delta * _speed_scale

	_stage.music_playing = _is_music_audible()

	# Update progress & FPS
	_progress_bar.value = clampf((_song_time / maxf(1.0, _song_duration)) * 100.0, 0.0, 100.0)
	if _lbl_fps.visible:
		_lbl_fps.text = str(Engine.get_frames_per_second()) + " FPS"

	# Trigger chart drum lighting cues only when music is actively playing
	while _drum_cursor < _drums.size() and float(_drums[_drum_cursor]["time"]) <= _song_time + 0.015:
		var dr: Dictionary = _drums[_drum_cursor]
		if _stage.music_playing:
			_stage.trigger_drum(int(dr["type"]), 1.05)
		_drum_cursor += 1

	# Advance section display
	while _section_cursor < _sections.size() and float(_sections[_section_cursor]["time"]) <= _song_time:
		_current_section = str(_sections[_section_cursor]["name"])
		_lbl_section.text = GameState.current_difficulty.to_upper() + " • " + _current_section.to_upper() + _speed_tag()
		_section_cursor += 1

	# Star Power drain & stage state
	if _sp_active:
		_star_power -= delta * 12.5
		if _star_power <= 0.0:
			_star_power = 0.0
			_sp_active = false
	_stage.star_power_active = _sp_active
	_stage.combo_level = _base_multiplier()
	_update_sp_button()

	# Animate 3D pop-up frets, small hit flames, & Whammy pitch bend
	_whammy_phase += delta * 18.0
	var any_sustain := false
	for l in range(5):
		if _lane_pressed[l]:
			_fret_pop[l] = 1.0
		else:
			_fret_pop[l] = maxf(0.0, _fret_pop[l] - delta * 11.0)
		_lane_flash[l] = maxf(0.0, _lane_flash[l] - delta * 6.5)
		_hit_flames[l] = maxf(0.0, _hit_flames[l] - delta * 5.6)
		var sn = _active_sustains[l]
		if sn != null:
			if not _lane_pressed[l]:
				_active_sustains[l] = null
			elif _song_time >= float(sn["end_time"]):
				sn["sustain_done"] = true
				_active_sustains[l] = null
			else:
				any_sustain = true
				var mult := _effective_multiplier()
				_score += int(round(delta * 120.0 * float(mult)))
				_hit_flames[l] = maxf(_hit_flames[l], 0.30)
				if _whammy_active:
					_star_power = minf(100.0, _star_power + delta * 11.0)
				elif bool(sn["sp"]):
					_star_power = minf(100.0, _star_power + delta * 6.0)

	if not _players.is_empty():
		var bend := 1.0 + (sin(_whammy_phase) * 0.022 if (_whammy_active and any_sustain) else 0.0)
		for p in _players:
			p.pitch_scale = _speed_scale * bend

	# Check HOPO / Tap auto-catch if finger is already holding the target lane when note crosses hit line
	_process_hopo_holds()

	# Miss notes that scrolled past GOOD window
	while _note_cursor < _notes.size():
		var n: Dictionary = _notes[_note_cursor]
		if bool(n["hit"]) or bool(n["missed"]):
			_note_cursor += 1
			continue
		if _song_time - float(n["time"]) > HIT_WINDOW_GOOD * _speed_scale:
			n["missed"] = true
			_on_note_missed()
			_note_cursor += 1
		else:
			break

	if _judge_timer > 0.0:
		_judge_timer = maxf(0.0, _judge_timer - delta)

	_update_hud_numbers()
	_highway_canvas.queue_redraw()

	# Check song completion
	if _started_audio and _song_time >= _song_duration:
		_complete_song()

func _process_hopo_holds() -> void:
	if _combo <= 0:
		return
	var win := 0.042 * _speed_scale
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
					_register_hit(n, 0.0)

func _input(event: InputEvent) -> void:
	if _paused or _failed or _finished:
		if event.is_action_pressed("ui_cancel"):
			_toggle_pause()
			get_viewport().set_input_as_handled()
		return

	if event is InputEventScreenTouch:
		var te := event as InputEventScreenTouch
		if te.pressed:
			if _pause_btn and _pause_btn.get_global_rect().grow(6.0).has_point(te.position):
				return
			if _sp_btn and _sp_btn.get_global_rect().grow(4.0).has_point(te.position):
				_touch_to_lane[te.index] = -1
				_try_activate_star_power()
				get_viewport().set_input_as_handled()
				return
			if _whammy_btn and _whammy_btn.get_global_rect().grow(4.0).has_point(te.position):
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
	if pos.y < sz.y * 0.45:
		return -1
	var top_y := sz.y * 0.10
	var strike_y := sz.y * 0.80
	var bot_y := sz.y * 0.995
	var top_hw := sz.x * 0.135
	var strike_hw := sz.x * 0.375
	var bot_hw := sz.x * 0.44
	var cx := sz.x * 0.5
	var hw_y := strike_hw
	if pos.y <= strike_y:
		var ty := clampf((pos.y - top_y) / maxf(1.0, strike_y - top_y), 0.0, 1.0)
		hw_y = lerpf(top_hw, strike_hw, ty)
	else:
		var ty := clampf((pos.y - strike_y) / maxf(1.0, bot_y - strike_y), 0.0, 1.0)
		hw_y = lerpf(strike_hw, bot_hw, ty)
	var pad_x := sz.x * 0.055
	if pos.x < (cx - hw_y - pad_x) or pos.x > (cx + hw_y + pad_x):
		return -1
	var norm := (pos.x - (cx - hw_y)) / maxf(1.0, hw_y * 2.0)
	return clampi(int(floor(norm * 5.0)), 0, 4)

func _press_lane(lane: int) -> void:
	_lane_pressed[lane] = true
	_fret_pop[lane] = 1.0
	_lane_flash[lane] = 1.0

	# Search closest unhit note in this lane within GOOD hit window
	var best_note = null
	var best_err := 999.0
	var max_w := HIT_WINDOW_GOOD * _speed_scale
	for i in range(_note_cursor, _notes.size()):
		var n: Dictionary = _notes[i]
		var dt := float(n["time"]) - _song_time
		if dt > max_w:
			break
		if bool(n["hit"]) or bool(n["missed"]):
			continue
		if int(n["lane"]) == lane and absf(dt) <= max_w:
			if absf(dt) < best_err:
				best_err = absf(dt)
				best_note = n
			break

	if best_note != null:
		_register_hit(best_note, best_err / _speed_scale)
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
	_active_sustains[lane] = null

func _register_hit(note: Dictionary, abs_err_sec: float) -> void:
	note["hit"] = true
	var lane := int(note["lane"])
	_combo += 1
	if _combo > _max_streak:
		_max_streak = _combo

	var mult := _effective_multiplier()
	var base_pts := 50
	if abs_err_sec <= HIT_WINDOW_PERFECT:
		_hits_perfect += 1
		base_pts = 100
		_hit_flames[lane] = 1.0
		_judge_text = "PERFECT!"
		_judge_col = Color(0.15, 1.0, 0.85)
	elif abs_err_sec <= HIT_WINDOW_GREAT:
		_hits_great += 1
		base_pts = 75
		_hit_flames[lane] = 0.80
		_judge_text = "GREAT!"
		_judge_col = Color(0.35, 1.0, 0.35)
	else:
		_hits_good += 1
		base_pts = 50
		_hit_flames[lane] = 0.45
		_judge_text = "GOOD"
		_judge_col = Color(1.0, 0.86, 0.22)
	_judge_timer = 0.55

	_score += base_pts * mult
	_rock_meter = minf(100.0, _rock_meter + (2.4 if _sp_active else 1.6))

	if bool(note["sp"]):
		_star_power = minf(100.0, _star_power + 8.5)
	elif _combo % 10 == 0:
		_star_power = minf(100.0, _star_power + 5.0)

	if float(note["dur"]) > 0.08:
		_active_sustains[lane] = note

func _on_note_missed() -> void:
	_misses += 1
	if _combo >= 10:
		GameState.play_miss()
	_combo = 0
	_judge_text = "MISS"
	_judge_col = Color(1.0, 0.22, 0.30)
	_judge_timer = 0.55
	_rock_meter -= 6.5
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
		_stage.trigger_drum(0, 1.45)
		_stage.trigger_drum(1, 1.45)
		_judge_text = "STAR POWER! 2X"
		_judge_col = ThemeManager.get_theme_data()["star_power"]
		_judge_timer = 1.1

func _update_sp_button() -> void:
	var pct := int(round(_star_power))
	if _sp_active:
		_sp_btn.text = "2X ON!\n" + str(pct) + "%"
		_sp_btn.modulate = Color(1.2, 1.2, 1.2, 1.0)
	elif _star_power >= 50.0:
		var pulse := 0.88 + 0.18 * sin(_song_time * 9.0)
		_sp_btn.text = "DEPLOY!\n" + str(pct) + "%"
		_sp_btn.modulate = Color(pulse, 1.0, 1.0, 1.0)
	else:
		_sp_btn.text = "STAR\n" + str(pct) + "%"
		_sp_btn.modulate = Color(0.75, 0.78, 0.85, 0.85)

func _update_hud_numbers() -> void:
	_lbl_score.text = _format_commas(_score)
	_lbl_combo.text = str(_combo) + " STREAK"
	var m := _effective_multiplier()
	_lbl_mult.text = str(m) + "x"
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
	for p in _players:
		p.stop()
	_fail_panel.visible = true

func _complete_song() -> void:
	_finished = true
	_stage.music_playing = false
	for p in _players:
		p.stop()
	var hit_total := _hits_perfect + _hits_great + _hits_good
	var denom := maxi(1, hit_total + _misses)
	var acc := (float(hit_total) / float(denom)) * 100.0
	var stars := 1
	if acc >= 98.0: stars = 5
	elif acc >= 92.0: stars = 5
	elif acc >= 82.0: stars = 4
	elif acc >= 70.0: stars = 3
	elif acc >= 55.0: stars = 2
	var is_fc := (_misses == 0 and hit_total > 0 and GameState.practice_start_sec <= 0.01)

	var res := {
		"score": _score,
		"stars": stars,
		"accuracy": acc,
		"max_streak": _max_streak,
		"perfect": _hits_perfect,
		"great": _hits_great,
		"good": _hits_good,
		"missed": _misses,
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
# 60FPS PERSPECTIVE 3D-PROJECTION HIGHWAY RENDERER
# ============================================================================

func _project_depth(norm_ahead: float) -> float:
	var d := 1.0 - norm_ahead
	return pow(maxf(0.0, d), 1.82) if d >= 0.0 else - ( -d ) * 1.4

func _draw_highway() -> void:
	var sz := size
	var t := ThemeManager.get_theme_data()
	var top_y := sz.y * 0.10
	var strike_y := sz.y * 0.80
	var bot_y := sz.y * 0.995
	var top_hw := sz.x * 0.135
	var strike_hw := sz.x * 0.375
	var bot_hw := sz.x * 0.44
	var cx := sz.x * 0.5

	# 1. Perspective Fretboard Deck
	var hw_col: Color = t["highway"]
	var edge_col: Color = t["star_power"] if _sp_active else t["highway_edge"]
	_quad_pts[0] = Vector2(cx - top_hw, top_y)
	_quad_pts[1] = Vector2(cx + top_hw, top_y)
	_quad_pts[2] = Vector2(cx + bot_hw, bot_y)
	_quad_pts[3] = Vector2(cx - bot_hw, bot_y)
	_quad_cols[0] = Color(hw_col.r, hw_col.g, hw_col.b, 0.78)
	_quad_cols[1] = Color(hw_col.r, hw_col.g, hw_col.b, 0.78)
	_quad_cols[2] = Color(hw_col.r, hw_col.g, hw_col.b, 0.97)
	_quad_cols[3] = Color(hw_col.r, hw_col.g, hw_col.b, 0.97)
	_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

	# Pressed lane beam highlight + lower tactile touch-pad glow
	for l in range(5):
		var lcol := ThemeManager.LANE_COLORS[l]
		if _sp_active:
			lcol = lcol.lerp(t["star_power"], 0.45)
		var f0 := float(l) / 5.0 * 2.0 - 1.0
		var f1 := float(l + 1) / 5.0 * 2.0 - 1.0

		# Lower Fret Touch Zone Pad (between strike_y and bot_y)
		var pad_alpha := 0.28 if _lane_pressed[l] else 0.08
		_quad_pts[0] = Vector2(cx + f0 * strike_hw, strike_y)
		_quad_pts[1] = Vector2(cx + f1 * strike_hw, strike_y)
		_quad_pts[2] = Vector2(cx + f1 * bot_hw, bot_y)
		_quad_pts[3] = Vector2(cx + f0 * bot_hw, bot_y)
		_quad_cols[0] = Color(lcol.r, lcol.g, lcol.b, pad_alpha * 0.5)
		_quad_cols[1] = Color(lcol.r, lcol.g, lcol.b, pad_alpha * 0.5)
		_quad_cols[2] = Color(lcol.r, lcol.g, lcol.b, pad_alpha)
		_quad_cols[3] = Color(lcol.r, lcol.g, lcol.b, pad_alpha)
		_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

		var energy := maxf(1.0 if _lane_pressed[l] else 0.0, _lane_flash[l] * 0.55)
		if energy > 0.02:
			_quad_pts[0] = Vector2(cx + f0 * top_hw, top_y)
			_quad_pts[1] = Vector2(cx + f1 * top_hw, top_y)
			_quad_pts[2] = Vector2(cx + f1 * strike_hw, strike_y)
			_quad_pts[3] = Vector2(cx + f0 * strike_hw, strike_y)
			_quad_cols[0] = Color(lcol.r, lcol.g, lcol.b, 0.03 * energy)
			_quad_cols[1] = Color(lcol.r, lcol.g, lcol.b, 0.03 * energy)
			_quad_cols[2] = Color(lcol.r, lcol.g, lcol.b, 0.24 * energy)
			_quad_cols[3] = Color(lcol.r, lcol.g, lcol.b, 0.24 * energy)
			_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

	# 2. Scrolling Measure & Beat Fret Lines
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
		var a := clampf(p * (0.55 if major else 0.24), 0.04, 0.65)
		_highway_canvas.draw_line(Vector2(cx - hw, y), Vector2(cx + hw, y), Color(0.85, 0.92, 1.0, a), 2.6 if major else 1.3)

	# 3. Lane Divider Strings & Glowing Neon Rails
	for s in range(1, 5):
		var fn := float(s) / 5.0 * 2.0 - 1.0
		_highway_canvas.draw_line(
			Vector2(cx + fn * top_hw, top_y),
			Vector2(cx + fn * bot_hw, bot_y),
			Color(1.0, 1.0, 1.0, 0.20),
			1.6
		)
	var rail_pulse := 3.5 + _stage.kick_pulse * 2.5
	_highway_canvas.draw_line(Vector2(cx - top_hw, top_y), Vector2(cx - bot_hw, bot_y), edge_col, rail_pulse)
	_highway_canvas.draw_line(Vector2(cx + top_hw, top_y), Vector2(cx + bot_hw, bot_y), edge_col, rail_pulse)

	# 4. Rock Meter Bar & Star Power Bar flanking the Highway
	_draw_side_meters(cx, top_y, strike_y, top_hw, strike_hw, t)

	# 5. Strike Bar Line & Base Fret Sockets (for unpressed frets)
	_highway_canvas.draw_line(Vector2(cx - strike_hw, strike_y), Vector2(cx + strike_hw, strike_y), Color(1, 1, 1, 0.58), 3.0)
	for l in range(5):
		if _fret_pop[l] <= 0.02:
			_draw_fret_3d(l, cx, strike_y, strike_hw)

	# 6. Sustain Tails (drawn behind 3D note gems)
	for i in range(_note_cursor, _notes.size()):
		var n: Dictionary = _notes[i]
		var head_norm := (float(n["time"]) - _song_time) / _visible_ahead_sec
		if head_norm > 1.02:
			break
		if float(n["dur"]) <= 0.05 or bool(n["missed"]) or bool(n["sustain_done"]):
			continue
		var tail_norm := (float(n["end_time"]) - _song_time) / _visible_ahead_sec
		if tail_norm < -0.05:
			continue
		var n0 := clampf(head_norm, 0.0 if bool(n["hit"]) else -0.15, 1.0)
		var n1 := clampf(tail_norm, 0.0, 1.0)
		if n1 <= n0:
			continue
		var p0 := _project_depth(n0)
		var p1 := _project_depth(n1)
		var y0 := lerpf(top_y, strike_y, p0)
		var y1 := lerpf(top_y, strike_y, p1)
		var hw0 := lerpf(top_hw, strike_hw, p0)
		var hw1 := lerpf(top_hw, strike_hw, p1)
		var lane := int(n["lane"])
		var lf := ((float(lane) + 0.5) / 5.0) * 2.0 - 1.0
		var x0 := cx + lf * hw0
		var x1 := cx + lf * hw1
		var w0 := (hw0 * 2.0 / 5.0) * 0.27
		var w1 := (hw1 * 2.0 / 5.0) * 0.27
		var scol: Color = t["star_power"] if (_sp_active or bool(n["sp"])) else ThemeManager.LANE_COLORS[lane]
		var held: bool = (_active_sustains[lane] == n)
		if held and _whammy_active:
			var wave := sin(_whammy_phase + y0 * 0.05) * 7.0
			x0 += wave * 0.35
			w0 *= 1.4
		_quad_pts[0] = Vector2(x1 - w1, y1)
		_quad_pts[1] = Vector2(x1 + w1, y1)
		_quad_pts[2] = Vector2(x0 + w0, y0)
		_quad_pts[3] = Vector2(x0 - w0, y0)
		var sa := 0.94 if held else 0.72
		_quad_cols[0] = Color(scol.r, scol.g, scol.b, sa * 0.65)
		_quad_cols[1] = Color(scol.r, scol.g, scol.b, sa * 0.65)
		_quad_cols[2] = Color(scol.r, scol.g, scol.b, sa)
		_quad_cols[3] = Color(scol.r, scol.g, scol.b, sa)
		_highway_canvas.draw_polygon(_quad_pts, _quad_cols)
		_highway_canvas.draw_line(Vector2(x1, y1), Vector2(x0, y0), Color(1, 1, 1, 0.80 if held else 0.38), 2.4)

	# 7. Scrolling 3D Note Gems (Back-to-Front Painter's Order)
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
		var gw := (nhw * 2.0 / 5.0) * 0.43
		var gh := gw * 0.50
		var gcol: Color = t["star_power"] if (_sp_active or bool(n["sp"])) else ThemeManager.LANE_COLORS[lane]
		if bool(n["missed"]):
			gcol = Color(0.35, 0.35, 0.38, 0.55)

		_draw_ellipse(Vector2(nx, ny + gh * 0.22), gw * 1.05, gh * 1.05, Color(0, 0, 0, 0.58))
		_draw_ellipse(Vector2(nx, ny), gw, gh, gcol)
		if bool(n["sp"]) and not bool(n["missed"]):
			_draw_ellipse_arc(Vector2(nx, ny), gw * 1.16, gh * 1.16, Color(1.0, 1.0, 1.0, 0.88), 2.2)
		if bool(n["tap"]):
			_draw_ellipse(Vector2(nx, ny - gh * 0.1), gw * 0.66, gh * 0.66, Color(0.05, 0.05, 0.08, 0.88))
			_draw_ellipse_arc(Vector2(nx, ny - gh * 0.1), gw * 0.68, gh * 0.68, Color(1, 1, 1, 0.98), 2.4)
		elif bool(n["hopo"]):
			_draw_ellipse(Vector2(nx, ny - gh * 0.12), gw * 0.62, gh * 0.62, Color(1.0, 1.0, 1.0, 0.98))
		else:
			_draw_ellipse(Vector2(nx, ny - gh * 0.12), gw * 0.45, gh * 0.40, gcol.lightened(0.55))
			_draw_ellipse_arc(Vector2(nx, ny), gw * 0.95, gh * 0.95, Color(1, 1, 1, 0.48), 1.6)

	# 8. Popped-Up ("Timbul") 3D Raised Frets when Tapped (drawn in foreground!)
	for l in range(5):
		if _fret_pop[l] > 0.02:
			_draw_fret_3d(l, cx, strike_y, strike_hw)

	# 9. Small Neat Flame Effect on Good/Tight Note Hit Timing
	for l in range(5):
		var fl := _hit_flames[l]
		if fl > 0.04:
			var lf := ((float(l) + 0.5) / 5.0) * 2.0 - 1.0
			var rx := cx + lf * strike_hw
			var rw := (strike_hw * 2.0 / 5.0) * 0.43
			var rh := rw * 0.50
			var base_y := strike_y - _fret_pop[l] * 14.0 - rh * 0.22
			var fh := 20.0 * fl
			var fw := 8.5 * fl

			# Outer warm orange mini flame tongue
			_quad_pts[0] = Vector2(rx, base_y - fh)
			_quad_pts[1] = Vector2(rx + fw, base_y - fh * 0.22)
			_quad_pts[2] = Vector2(rx, base_y + 3.0 * fl)
			_quad_pts[3] = Vector2(rx - fw, base_y - fh * 0.22)
			_quad_cols[0] = Color(1.0, 0.35, 0.05, 0.0)
			_quad_cols[1] = Color(1.0, 0.45, 0.08, 0.86 * fl)
			_quad_cols[2] = Color(1.0, 0.72, 0.18, 0.92 * fl)
			_quad_cols[3] = Color(1.0, 0.45, 0.08, 0.86 * fl)
			_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

			# Inner bright golden-yellow mini core
			_quad_pts[0] = Vector2(rx, base_y - fh * 0.62)
			_quad_pts[1] = Vector2(rx + fw * 0.52, base_y - fh * 0.12)
			_quad_pts[2] = Vector2(rx, base_y + 1.5 * fl)
			_quad_pts[3] = Vector2(rx - fw * 0.52, base_y - fh * 0.12)
			_quad_cols[0] = Color(1.0, 0.95, 0.55, 0.15 * fl)
			_quad_cols[1] = Color(1.0, 0.92, 0.35, 0.92 * fl)
			_quad_cols[2] = Color(1.0, 1.0, 0.92, 0.96 * fl)
			_quad_cols[3] = Color(1.0, 0.92, 0.35, 0.92 * fl)
			_highway_canvas.draw_polygon(_quad_pts, _quad_cols)

	# 10. Judgement Pop Text Above Highway Center
	if _judge_timer > 0.01 and ThemeManager.font_display:
		var ja := clampf(_judge_timer * 2.5, 0.0, 1.0)
		var fsize := 22
		var jpos := Vector2(cx - 150.0, sz.y * 0.40 - (1.0 - ja) * 10.0)
		_highway_canvas.draw_string(
			ThemeManager.font_display,
			jpos,
			_judge_text,
			HORIZONTAL_ALIGNMENT_CENTER,
			300.0,
			fsize,
			Color(_judge_col.r, _judge_col.g, _judge_col.b, ja)
		)

func _draw_fret_3d(l: int, cx: float, strike_y: float, strike_hw: float) -> void:
	var lf := ((float(l) + 0.5) / 5.0) * 2.0 - 1.0
	var rx := cx + lf * strike_hw
	var rw := (strike_hw * 2.0 / 5.0) * 0.43
	var rh := rw * 0.50
	var lcol := ThemeManager.LANE_COLORS[l]
	var pop := _fret_pop[l]
	var lift := pop * 14.0
	var sc := 1.0 + pop * 0.14
	var w := rw * sc
	var h := rh * sc

	# Base socket rim on fretboard
	_draw_ellipse(Vector2(rx, strike_y), rw * 1.04, rh * 1.04, Color(0.04, 0.04, 0.08, 0.95))

	if pop > 0.02:
		# 3D drop shadow cast onto fretboard
		_draw_ellipse(Vector2(rx, strike_y + 4.5 * pop), w * 1.08, h * 1.08, Color(0.0, 0.0, 0.0, 0.55 * pop))

		# Extruded 3D piston cylinder side-wall rising up from strike_y to strike_y - lift
		var side_dark := lcol.darkened(0.48)
		var side_mid := lcol.darkened(0.24)
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
		_highway_canvas.draw_line(Vector2(rx - w, strike_y - lift), Vector2(rx - w, strike_y), lcol.lightened(0.25), 2.0)
		_highway_canvas.draw_line(Vector2(rx + w, strike_y - lift), Vector2(rx + w, strike_y), lcol.darkened(0.15), 2.0)

	# Top Fret Button Cap at strike_y - lift
	var top_c := Vector2(rx, strike_y - lift)
	var face_col := lcol.lightened(0.12) if pop > 0.25 else lcol.darkened(0.62)
	var rim_col := lcol.lightened(0.42) if pop > 0.25 else lcol
	_draw_ellipse(top_c, w, h, face_col)
	_draw_ellipse_arc(top_c, w, h, rim_col, 3.8 if pop > 0.25 else 2.8)
	# Glossy 3D bevel highlight dome on top cap
	_draw_ellipse(top_c - Vector2(0.0, h * 0.20), w * 0.52, h * 0.42, Color(1.0, 1.0, 1.0, 0.20 + 0.65 * pop))

func _draw_side_meters(cx: float, top_y: float, strike_y: float, _top_hw: float, strike_hw: float, t: Dictionary) -> void:
	var bar_h := (strike_y - top_y) * 0.58
	var bar_y := strike_y - bar_h
	# Left side of highway: Rock Meter (Red -> Yellow -> Green)
	var rmx := cx - strike_hw - 16.0
	_highway_canvas.draw_rect(Rect2(rmx - 6, bar_y, 12, bar_h), Color(0.05, 0.05, 0.08, 0.88), true)
	var rm_frac := clampf(_rock_meter / 100.0, 0.0, 1.0)
	var rm_col := Color(0.12, 0.98, 0.48) if _rock_meter >= 60.0 else (Color(1.0, 0.84, 0.15) if _rock_meter >= 30.0 else Color(1.0, 0.20, 0.25))
	var rm_fill := bar_h * rm_frac
	_highway_canvas.draw_rect(Rect2(rmx - 4, bar_y + bar_h - rm_fill, 8, rm_fill), rm_col, true)
	_highway_canvas.draw_rect(Rect2(rmx - 6, bar_y, 12, bar_h), Color(1, 1, 1, 0.38), false, 1.5)

	# Right side of highway: Star Power Charge Meter
	var spx := cx + strike_hw + 16.0
	_highway_canvas.draw_rect(Rect2(spx - 6, bar_y, 12, bar_h), Color(0.05, 0.05, 0.08, 0.88), true)
	var sp_frac := clampf(_star_power / 100.0, 0.0, 1.0)
	var sp_fill := bar_h * sp_frac
	var sp_c: Color = t["star_power"]
	_highway_canvas.draw_rect(Rect2(spx - 4, bar_y + bar_h - sp_fill, 8, sp_fill), sp_c if _star_power >= 50.0 or _sp_active else sp_c.darkened(0.35), true)
	_highway_canvas.draw_line(Vector2(spx - 8, bar_y + bar_h * 0.5), Vector2(spx + 8, bar_y + bar_h * 0.5), Color.WHITE, 2.0)
	_highway_canvas.draw_rect(Rect2(spx - 6, bar_y, 12, bar_h), Color(1, 1, 1, 0.38), false, 1.5)

func _draw_ellipse(center: Vector2, rx: float, ry: float, col: Color) -> void:
	_highway_canvas.draw_set_transform(center, 0.0, Vector2(1.0, ry / maxf(0.01, rx)))
	_highway_canvas.draw_circle(Vector2.ZERO, rx, col)
	_highway_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _draw_ellipse_arc(center: Vector2, rx: float, ry: float, col: Color, width: float) -> void:
	_highway_canvas.draw_set_transform(center, 0.0, Vector2(1.0, ry / maxf(0.01, rx)))
	_highway_canvas.draw_arc(Vector2.ZERO, rx, 0.0, TAU, 24, col, width)
	_highway_canvas.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
