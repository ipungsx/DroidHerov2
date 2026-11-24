extends Control

# Fancy Glassmorphic Main Hub for DroidHeroV2:
# - Tab 0: PLAY LIBRARY (Song cards, Difficulty picker, Practice Mode speed & section, Highscores)
# - Tab 1: ENCHOR.US STORE (Live search on api.enchor.us, cover art, 1-tap .sng download & play, local .sng/.zip import)
# - Tab 2: THEMES (Live 5-theme visual switcher with instant preview)
# - Tab 3: SETTINGS & CALIBRATION (Audio/Video latency tap calibrator, Highway speed, No-Fail, Light intensity)

var _stage: ConcertStage
var _root_panel: MarginContainer
var _content_stack: Control
var _tab_buttons: Array[Button] = []
var _active_tab: int = 0

# Library tab refs
var _lib_list_vbox: VBoxContainer
var _detail_title: Label
var _detail_meta: Label
var _detail_best: Label
var _diff_buttons: Dictionary = {}
var _practice_spd_opt: OptionButton

# Enchor.us tab refs
var _search_input: LineEdit
var _enchor_status: Label
var _enchor_list_vbox: VBoxContainer
var _enchor_page: int = 1
var _enchor_last_query: String = "*"
var _dl_modal: PanelContainer
var _dl_label: Label
var _dl_bar: ProgressBar
var _cover_rects: Dictionary = {} # art_md5 -> Array[TextureRect]
var _play_after_dl: bool = false
var _file_dialog: FileDialog

# Calibration tap state
var _cal_taps: Array[float] = []
var _cal_beat_timer: float = 0.0
var _cal_test_active: bool = false
var _cal_lbl: Label
var _fps_badge: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ThemeManager.theme_changed.connect(_on_theme_changed)
	EnchorClient.search_completed.connect(_on_enchor_results)
	EnchorClient.download_progress.connect(_on_dl_progress)
	EnchorClient.download_completed.connect(_on_dl_completed)
	EnchorClient.cover_loaded.connect(_on_cover_loaded)

	if GameState.current_song.is_empty() and not GameState.library.is_empty():
		GameState.current_song = GameState.library[0]

	_rebuild_ui()

func _process(delta: float) -> void:
	if _fps_badge:
		_fps_badge.text = str(Engine.get_frames_per_second()) + " FPS"
	if _active_tab == 3 and _cal_test_active:
		_cal_beat_timer += delta
		if _cal_beat_timer >= 0.5:
			_cal_beat_timer -= 0.5
			GameState.play_click()
			if _stage:
				_stage.music_playing = true
				_stage.trigger_drum(0, 0.75)
	elif _stage:
		_stage.music_playing = false

func _on_theme_changed(_id: String) -> void:
	var keep_tab := _active_tab
	_rebuild_ui()
	_switch_tab(keep_tab)

func _rebuild_ui() -> void:
	for c in get_children():
		c.queue_free()
	_tab_buttons.clear()
	_diff_buttons.clear()
	_cover_rects.clear()
	_cal_test_active = false

	var t := ThemeManager.get_theme_data()

	# 1. Concert Stage Background (static when no music is playing)
	_stage = ConcertStage.new()
	_stage.menu_idle_mode = true
	_stage.music_playing = false
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	# 2. Main Layout Container
	_root_panel = MarginContainer.new()
	_root_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_root_panel.add_theme_constant_override("margin_left", 14)
	_root_panel.add_theme_constant_override("margin_right", 14)
	_root_panel.add_theme_constant_override("margin_top", 10)
	_root_panel.add_theme_constant_override("margin_bottom", 10)
	add_child(_root_panel)

	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 10)
	_root_panel.add_child(main_vbox)

	# Top Header Bar
	var header := PanelContainer.new()
	header.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 14, 2, 10))
	main_vbox.add_child(header)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 10)
	header.add_child(hbox)

	var brand_vbox := VBoxContainer.new()
	brand_vbox.add_theme_constant_override("separation", 0)
	brand_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	hbox.add_child(brand_vbox)

	var logo := Label.new()
	logo.text = "DROIDHERO V2"
	if ThemeManager.font_display:
		logo.add_theme_font_override("font", ThemeManager.font_display)
	logo.add_theme_font_size_override("font_size", 23)
	logo.add_theme_color_override("font_color", t["accent"])
	brand_vbox.add_child(logo)

	var sub := Label.new()
	sub.text = "ENCHOR.US RHYTHM ARENA"
	if ThemeManager.font_semi:
		sub.add_theme_font_override("font", ThemeManager.font_semi)
	sub.add_theme_font_size_override("font_size", 13)
	sub.add_theme_color_override("font_color", t["text_dim"])
	brand_vbox.add_child(sub)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(spacer)

	var nav_names := ["PLAY", "ENCHOR.US", "THEMES", "SETTINGS"]
	for i in range(nav_names.size()):
		var b := Button.new()
		b.text = nav_names[i]
		b.custom_minimum_size = Vector2(130, 44)
		ThemeManager.style_button(b, i == _active_tab)
		var idx := i
		b.pressed.connect(func():
			GameState.play_click()
			_switch_tab(idx)
		)
		hbox.add_child(b)
		_tab_buttons.append(b)

	_fps_badge = Label.new()
	_fps_badge.text = "60 FPS"
	if ThemeManager.font_semi:
		_fps_badge.add_theme_font_override("font", ThemeManager.font_semi)
	_fps_badge.add_theme_font_size_override("font_size", 15)
	_fps_badge.add_theme_color_override("font_color", t["accent_2"])
	hbox.add_child(_fps_badge)

	# Content Stack
	_content_stack = Control.new()
	_content_stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_vbox.add_child(_content_stack)

	_build_library_tab(t)
	_build_enchor_tab(t)
	_build_themes_tab(t)
	_build_settings_tab(t)
	_build_download_modal(t)
	_build_file_importer()

	_switch_tab(_active_tab)

func _switch_tab(idx: int) -> void:
	_active_tab = idx
	if idx != 3:
		_cal_test_active = false
	for i in range(_content_stack.get_child_count()):
		var ch := _content_stack.get_child(i) as Control
		ch.visible = (i == idx)
	for i in range(_tab_buttons.size()):
		ThemeManager.style_button(_tab_buttons[i], i == idx)
	if idx == 0:
		GameState.scan_library()
		_populate_library_list()
	elif idx == 1 and _enchor_list_vbox.get_child_count() == 0:
		_trigger_enchor_search("*", 1)

# ============================================================================
# TAB 0: SONG LIBRARY & STAGE LAUNCHER
# ============================================================================
func _build_library_tab(t: Dictionary) -> void:
	var split := HBoxContainer.new()
	split.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	split.add_theme_constant_override("separation", 12)
	_content_stack.add_child(split)

	# Left: Installed Songs Scroll List
	var left_card := PanelContainer.new()
	left_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_card.size_flags_stretch_ratio = 1.15
	left_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 14, 2, 6))
	split.add_child(left_card)

	var lv := VBoxContainer.new()
	lv.add_theme_constant_override("separation", 8)
	left_card.add_child(lv)

	var lh := HBoxContainer.new()
	lh.add_theme_constant_override("separation", 8)
	lv.add_child(lh)

	var ltitle := Label.new()
	ltitle.text = "SONG LIST"
	if ThemeManager.font_display:
		ltitle.add_theme_font_override("font", ThemeManager.font_display)
	ltitle.add_theme_font_size_override("font_size", 19)
	ltitle.add_theme_color_override("font_color", t["accent"])
	ltitle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lh.add_child(ltitle)

	var btn_import := Button.new()
	btn_import.text = "+ IMPORT .SNG/.ZIP"
	btn_import.custom_minimum_size = Vector2(165, 40)
	ThemeManager.style_button(btn_import, false)
	btn_import.pressed.connect(func():
		GameState.play_click()
		_file_dialog.popup_centered_ratio(0.85)
	)
	lh.add_child(btn_import)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	lv.add_child(scroll)

	_lib_list_vbox = VBoxContainer.new()
	_lib_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_lib_list_vbox)

	# Right: Selected Song Stage Setup, Difficulty, Highscore & Launch
	var right_card := PanelContainer.new()
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_card.size_flags_stretch_ratio = 1.0
	right_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["accent_2"], 14, 2, 10))
	split.add_child(right_card)

	var rv := VBoxContainer.new()
	rv.add_theme_constant_override("separation", 7)
	right_card.add_child(rv)

	_detail_title = Label.new()
	_detail_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_title.max_lines_visible = 2
	if ThemeManager.font_display:
		_detail_title.add_theme_font_override("font", ThemeManager.font_display)
	_detail_title.add_theme_font_size_override("font_size", 21)
	_detail_title.add_theme_color_override("font_color", t["text"])
	rv.add_child(_detail_title)

	_detail_meta = Label.new()
	_detail_meta.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		_detail_meta.add_theme_font_override("font", ThemeManager.font_body)
	_detail_meta.add_theme_font_size_override("font_size", 17)
	_detail_meta.add_theme_color_override("font_color", t["text_dim"])
	rv.add_child(_detail_meta)

	_detail_best = Label.new()
	if ThemeManager.font_body:
		_detail_best.add_theme_font_override("font", ThemeManager.font_body)
	_detail_best.add_theme_font_size_override("font_size", 17)
	_detail_best.add_theme_color_override("font_color", Color(1.0, 0.86, 0.24))
	rv.add_child(_detail_best)

	var diff_row := HBoxContainer.new()
	diff_row.add_theme_constant_override("separation", 6)
	rv.add_child(diff_row)

	for d: String in ["Easy", "Medium", "Hard", "Expert"]:
		var db := Button.new()
		db.text = d.to_upper()
		db.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		db.custom_minimum_size = Vector2(0, 42)
		var d_name: String = d
		db.pressed.connect(func():
			GameState.play_click()
			GameState.current_difficulty = d_name
			_refresh_detail_panel()
		)
		diff_row.add_child(db)
		_diff_buttons[d] = db

	# Practice Speed Selector
	var prac_row := HBoxContainer.new()
	prac_row.add_theme_constant_override("separation", 8)
	rv.add_child(prac_row)

	var plbl := Label.new()
	plbl.text = "SPEED:"
	if ThemeManager.font_body:
		plbl.add_theme_font_override("font", ThemeManager.font_body)
	plbl.add_theme_font_size_override("font_size", 18)
	prac_row.add_child(plbl)

	_practice_spd_opt = OptionButton.new()
	_practice_spd_opt.add_item("NORMAL 100% (RANKED)", 0)
	_practice_spd_opt.add_item("PRACTICE 75% (SLOW)", 1)
	_practice_spd_opt.add_item("PRACTICE 50% (LEARN)", 2)
	_practice_spd_opt.add_item("HYPERSPEED 125%", 3)
	_practice_spd_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_practice_spd_opt.custom_minimum_size = Vector2(0, 40)
	if ThemeManager.font_body:
		_practice_spd_opt.add_theme_font_override("font", ThemeManager.font_body)
	_practice_spd_opt.add_theme_font_size_override("font_size", 17)
	prac_row.add_child(_practice_spd_opt)

	var r_spacer := Control.new()
	r_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rv.add_child(r_spacer)

	var act_row := HBoxContainer.new()
	act_row.add_theme_constant_override("separation", 8)
	rv.add_child(act_row)

	var btn_get_more := Button.new()
	btn_get_more.text = "+ ENCHOR.US"
	btn_get_more.custom_minimum_size = Vector2(138, 52)
	ThemeManager.style_button(btn_get_more, false)
	btn_get_more.pressed.connect(func():
		GameState.play_click()
		_switch_tab(1)
	)
	act_row.add_child(btn_get_more)

	var btn_play := Button.new()
	btn_play.text = "★ PLAY NOW! ★"
	btn_play.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_play.custom_minimum_size = Vector2(0, 52)
	ThemeManager.style_button(btn_play, true, t["accent"])
	btn_play.add_theme_font_size_override("font_size", 22)
	btn_play.pressed.connect(_launch_selected_song)
	act_row.add_child(btn_play)

	_populate_library_list()

func _populate_library_list() -> void:
	if not _lib_list_vbox:
		return
	for c in _lib_list_vbox.get_children():
		c.queue_free()
	var t := ThemeManager.get_theme_data()
	if GameState.current_song.is_empty() and not GameState.library.is_empty():
		GameState.current_song = GameState.library[0]

	for song in GameState.library:
		var is_sel := str(song.get("id", "")) == str(GameState.current_song.get("id", ""))
		var row := PanelContainer.new()
		row.add_theme_stylebox_override(
			"panel",
			ThemeManager.make_card_style(
				t["panel_alt"] if is_sel else Color(0.05, 0.05, 0.11, 0.78),
				t["accent"] if is_sel else Color(1, 1, 1, 0.16),
				10,
				2 if is_sel else 1,
				6 if is_sel else 0
			)
		)
		_lib_list_vbox.add_child(row)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 10)
		row.add_child(hb)

		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)

		var nt := Label.new()
		nt.text = str(song.get("name", "Song"))
		nt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if ThemeManager.font_body:
			nt.add_theme_font_override("font", ThemeManager.font_body)
		nt.add_theme_font_size_override("font_size", 19)
		nt.add_theme_color_override("font_color", t["text"])
		vb.add_child(nt)

		var dur_s := int(song.get("song_length", 180000)) / 1000
		var sub := Label.new()
		sub.text = "%s • %d:%02d" % [str(song.get("artist", "Artist")), dur_s / 60, dur_s % 60]
		if ThemeManager.font_semi:
			sub.add_theme_font_override("font", ThemeManager.font_semi)
		sub.add_theme_font_size_override("font_size", 15)
		sub.add_theme_color_override("font_color", t["text_dim"])
		vb.add_child(sub)

		var sel_btn := Button.new()
		sel_btn.text = "✓ READY" if is_sel else "SELECT"
		sel_btn.custom_minimum_size = Vector2(106, 44)
		ThemeManager.style_button(sel_btn, is_sel)
		var s_copy: Dictionary = song
		sel_btn.pressed.connect(func():
			GameState.play_click()
			GameState.current_song = s_copy
			_populate_library_list()
			_refresh_detail_panel()
		)
		hb.add_child(sel_btn)

	_refresh_detail_panel()

func _refresh_detail_panel() -> void:
	if not _detail_title:
		return
	var s := GameState.current_song
	_detail_title.text = str(s.get("name", "No Song Selected"))
	var dur_s := int(s.get("song_length", 180000)) / 1000
	_detail_meta.text = "%s  •  Charter: %s  •  %d:%02d" % [
		str(s.get("artist", "-")),
		str(s.get("charter", "-")),
		dur_s / 60,
		dur_s % 60
	]
	var best := GameState.get_best(str(s.get("id", "")), GameState.current_difficulty)
	if best.is_empty():
		_detail_best.text = "BEST (" + GameState.current_difficulty.to_upper() + "): No record yet"
	else:
		var st_str := "★".repeat(int(best.get("stars", 1)))
		var fc_str := " [FC]" if bool(best.get("fc", false)) else ""
		_detail_best.text = "BEST: %d PTS  %s  (%.1f%%)%s" % [
			int(best.get("score", 0)),
			st_str,
			float(best.get("accuracy", 0.0)),
			fc_str
		]
	for d in _diff_buttons.keys():
		ThemeManager.style_button(_diff_buttons[d], d == GameState.current_difficulty)

func _launch_selected_song() -> void:
	if GameState.current_song.is_empty():
		return
	GameState.play_star_sfx()
	var spd_idx := _practice_spd_opt.selected if _practice_spd_opt else 0
	match spd_idx:
		1: GameState.practice_speed = 0.75
		2: GameState.practice_speed = 0.50
		3: GameState.practice_speed = 1.25
		_: GameState.practice_speed = 1.0
	GameState.practice_start_sec = 0.0
	get_tree().change_scene_to_file("res://scenes/Gameplay.tscn")

# ============================================================================
# TAB 1: LIVE ENCHOR.US CHART BROWSER & DIRECT DOWNLOADER
# ============================================================================
func _build_enchor_tab(t: Dictionary) -> void:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 16, 2, 10))
	_content_stack.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	# Search Bar Row
	var srow := HBoxContainer.new()
	srow.add_theme_constant_override("separation", 10)
	vbox.add_child(srow)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search 85,000+ Guitar Hero / Clone Hero charts on enchor.us (song, artist, charter)..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.custom_minimum_size = Vector2(0, 48)
	_search_input.add_theme_stylebox_override("normal", ThemeManager.make_card_style(Color(0.03, 0.03, 0.08, 0.95), t["border"], 12, 2, 0))
	if ThemeManager.font_body:
		_search_input.add_theme_font_override("font", ThemeManager.font_body)
	_search_input.add_theme_font_size_override("font_size", 19)
	_search_input.text_submitted.connect(func(q: String): _trigger_enchor_search(q, 1))
	srow.add_child(_search_input)

	var btn_search := Button.new()
	btn_search.text = "SEARCH ENCHOR.US"
	btn_search.custom_minimum_size = Vector2(185, 48)
	ThemeManager.style_button(btn_search, true)
	btn_search.pressed.connect(func():
		GameState.play_click()
		_trigger_enchor_search(_search_input.text, 1)
	)
	srow.add_child(btn_search)

	var btn_latest := Button.new()
	btn_latest.text = "TOP / LATEST"
	btn_latest.custom_minimum_size = Vector2(145, 48)
	ThemeManager.style_button(btn_latest, false)
	btn_latest.pressed.connect(func():
		GameState.play_click()
		_search_input.text = ""
		_trigger_enchor_search("*", 1)
	)
	srow.add_child(btn_latest)

	# Status & Pagination Row
	var prow := HBoxContainer.new()
	vbox.add_child(prow)

	_enchor_status = Label.new()
	_enchor_status.text = "Ready to search api.enchor.us..."
	_enchor_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_semi:
		_enchor_status.add_theme_font_override("font", ThemeManager.font_semi)
	_enchor_status.add_theme_font_size_override("font_size", 16)
	_enchor_status.add_theme_color_override("font_color", t["text_dim"])
	prow.add_child(_enchor_status)

	var btn_prev := Button.new()
	btn_prev.text = "◀ PREV"
	ThemeManager.style_button(btn_prev, false)
	btn_prev.pressed.connect(func():
		if _enchor_page > 1:
			_trigger_enchor_search(_enchor_last_query, _enchor_page - 1)
	)
	prow.add_child(btn_prev)

	var btn_next := Button.new()
	btn_next.text = "NEXT ▶"
	ThemeManager.style_button(btn_next, false)
	btn_next.pressed.connect(func():
		_trigger_enchor_search(_enchor_last_query, _enchor_page + 1)
	)
	prow.add_child(btn_next)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	_enchor_list_vbox = VBoxContainer.new()
	_enchor_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enchor_list_vbox.add_theme_constant_override("separation", 8)
	scroll.add_child(_enchor_list_vbox)

func _trigger_enchor_search(query: String, page: int) -> void:
	_enchor_last_query = query if query.strip_edges() != "" else "*"
	_enchor_page = maxi(1, page)
	_enchor_status.text = "Searching enchor.us (Page " + str(_enchor_page) + ")..."
	EnchorClient.search_charts(_enchor_last_query, _enchor_page)

func _on_enchor_results(results: Array, total_found: int, page: int, error_msg: String) -> void:
	if not _enchor_list_vbox:
		return
	for c in _enchor_list_vbox.get_children():
		c.queue_free()
	_cover_rects.clear()

	if error_msg != "":
		_enchor_status.text = "⚠ " + error_msg
		return

	_enchor_status.text = "Found %d guitar charts on enchor.us • Showing page %d" % [total_found, page]
	var t := ThemeManager.get_theme_data()

	for item in results:
		var md5 := str(item.get("md5", ""))
		var downloaded := EnchorClient.is_downloaded(md5)

		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["accent"] if downloaded else Color(1, 1, 1, 0.14), 12, 1, 0))
		_enchor_list_vbox.add_child(row)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 14)
		row.add_child(hb)

		# Album Art Thumbnail
		var art_box := TextureRect.new()
		art_box.custom_minimum_size = Vector2(64, 64)
		art_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		hb.add_child(art_box)
		var art_md5 := str(item.get("albumArtMd5", ""))
		if art_md5 != "" and art_md5 != "null":
			if not _cover_rects.has(art_md5):
				_cover_rects[art_md5] = []
			_cover_rects[art_md5].append(art_box)
			EnchorClient.request_cover(art_md5)

		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(vb)

		var title := Label.new()
		title.text = str(item.get("name", "Song")) + " — " + str(item.get("artist", "Artist"))
		if ThemeManager.font_body:
			title.add_theme_font_override("font", ThemeManager.font_body)
		title.add_theme_font_size_override("font_size", 20)
		title.add_theme_color_override("font_color", t["text"])
		vb.add_child(title)

		var dur_s := int(item.get("song_length", 180000)) / 1000
		var diff_g := maxi(0, int(item.get("diff_guitar", 3)))
		var drum_tag := " • 🥁 Drum Track" if int(item.get("diff_drums", -1)) >= 0 else " • 🥁 Auto Beat-Sync"
		var meta_lbl := Label.new()
		meta_lbl.text = "Charter: %s  •  Genre: %s  •  Intensity: %d/6  •  %d:%02d%s" % [
			str(item.get("charter", "Community")),
			str(item.get("genre", "Rock")),
			diff_g,
			dur_s / 60,
			dur_s % 60,
			drum_tag
		]
		if ThemeManager.font_semi:
			meta_lbl.add_theme_font_override("font", ThemeManager.font_semi)
		meta_lbl.add_theme_font_size_override("font_size", 15)
		meta_lbl.add_theme_color_override("font_color", t["text_dim"])
		vb.add_child(meta_lbl)

		var item_copy: Dictionary = item
		if downloaded:
			var btn_play := Button.new()
			btn_play.text = "PLAY NOW ▶"
			btn_play.custom_minimum_size = Vector2(150, 46)
			ThemeManager.style_button(btn_play, true)
			btn_play.pressed.connect(func():
				GameState.play_click()
				GameState.scan_library()
				for s in GameState.library:
					if str(s.get("md5", "")) == md5 or str(s.get("id", "")) == md5:
						GameState.current_song = s
						break
				_switch_tab(0)
			)
			hb.add_child(btn_play)
		else:
			var btn_dl := Button.new()
			btn_dl.text = "⬇ DOWNLOAD & PLAY"
			btn_dl.custom_minimum_size = Vector2(185, 46)
			ThemeManager.style_button(btn_dl, true, t["accent_2"])
			btn_dl.pressed.connect(func():
				GameState.play_click()
				_start_song_download(item_copy, true)
			)
			hb.add_child(btn_dl)

func _on_cover_loaded(art_md5: String, tex: Texture2D) -> void:
	if _cover_rects.has(art_md5):
		for rect in _cover_rects[art_md5]:
			if is_instance_valid(rect):
				rect.texture = tex

func _build_download_modal(t: Dictionary) -> void:
	_dl_modal = PanelContainer.new()
	_dl_modal.visible = false
	_dl_modal.set_anchors_preset(Control.PRESET_CENTER)
	_dl_modal.offset_left = -250
	_dl_modal.offset_top = -105
	_dl_modal.offset_right = 250
	_dl_modal.offset_bottom = 105
	_dl_modal.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.03, 0.03, 0.09, 0.97), t["accent"], 18, 3, 20))
	add_child(_dl_modal)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_dl_modal.add_child(vb)

	_dl_label = Label.new()
	_dl_label.text = "Downloading .sng from files.enchor.us..."
	_dl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dl_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		_dl_label.add_theme_font_override("font", ThemeManager.font_body)
	_dl_label.add_theme_font_size_override("font_size", 19)
	vb.add_child(_dl_label)

	_dl_bar = ProgressBar.new()
	_dl_bar.custom_minimum_size = Vector2(0, 24)
	vb.add_child(_dl_bar)

	var btn_cancel := Button.new()
	btn_cancel.text = "CANCEL"
	ThemeManager.style_button(btn_cancel, false)
	btn_cancel.pressed.connect(func():
		EnchorClient.cancel_download()
		_dl_modal.visible = false
	)
	vb.add_child(btn_cancel)

func _start_song_download(meta: Dictionary, auto_select: bool) -> void:
	_play_after_dl = auto_select
	_dl_modal.visible = true
	_dl_bar.value = 0.0
	_dl_label.text = "Downloading: " + str(meta.get("name", "Chart")) + "..."
	EnchorClient.download_chart(meta)

func _on_dl_progress(_md5: String, dl_bytes: int, total_bytes: int) -> void:
	if not _dl_modal or not _dl_modal.visible:
		return
	var mb := float(dl_bytes) / 1048576.0
	if total_bytes > 0:
		var tmb := float(total_bytes) / 1048576.0
		_dl_bar.value = (float(dl_bytes) / float(total_bytes)) * 100.0
		_dl_label.text = "Downloading from enchor.us... %.1f / %.1f MB" % [mb, tmb]
	else:
		_dl_bar.value = fmod(mb * 20.0, 95.0)
		_dl_label.text = "Downloading from enchor.us... %.1f MB" % mb

func _on_dl_completed(md5: String, _sng_path: String, error_msg: String) -> void:
	_dl_modal.visible = false
	if error_msg != "":
		_enchor_status.text = "⚠ " + error_msg
		return
	GameState.play_star_sfx()
	GameState.scan_library()
	for s in GameState.library:
		if str(s.get("md5", "")) == md5 or str(s.get("id", "")) == md5:
			GameState.current_song = s
			break
	if _play_after_dl:
		_switch_tab(0)
	else:
		_trigger_enchor_search(_enchor_last_query, _enchor_page)

func _build_file_importer() -> void:
	_file_dialog = FileDialog.new()
	_file_dialog.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = FileDialog.ACCESS_FILESYSTEM
	_file_dialog.filters = PackedStringArray(["*.sng ; Clone Hero SNG Package", "*.zip ; Song Archive ZIP"])
	_file_dialog.file_selected.connect(func(path: String):
		if path.to_lower().ends_with(".sng"):
			var dest := GameState.SONGS_DIR + "/" + path.get_file()
			DirAccess.copy_absolute(path, ProjectSettings.globalize_path(dest))
			GameState.scan_library()
			_populate_library_list()
		elif path.to_lower().ends_with(".zip"):
			SngParser.import_zip_to_folder(path)
			_populate_library_list()
	)
	add_child(_file_dialog)

# ============================================================================
# TAB 2: FANCY THEME GALLERY (5 CONCERT ARENA THEMES)
# ============================================================================
func _build_themes_tab(t: Dictionary) -> void:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 14, 2, 8))
	_content_stack.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	card.add_child(vbox)

	var title := Label.new()
	title.text = "CHOOSE ARENA VISUAL THEME"
	if ThemeManager.font_display:
		title.add_theme_font_override("font", ThemeManager.font_display)
	title.add_theme_font_size_override("font_size", 19)
	title.add_theme_color_override("font_color", t["accent"])
	vbox.add_child(title)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	scroll.add_child(grid)

	for tid in ThemeManager.THEMES.keys():
		var td: Dictionary = ThemeManager.THEMES[tid]
		var active: bool = (str(tid) == ThemeManager.current_theme_id)
		var tc := PanelContainer.new()
		tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tc.add_theme_stylebox_override("panel", ThemeManager.make_card_style(td["panel_alt"], td["accent"], 12, 3 if active else 1, 10 if active else 0))
		grid.add_child(tc)

		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 6)
		tc.add_child(tv)

		var tname := Label.new()
		tname.text = str(td["name"])
		if ThemeManager.font_display:
			tname.add_theme_font_override("font", ThemeManager.font_display)
		tname.add_theme_font_size_override("font_size", 17)
		tname.add_theme_color_override("font_color", td["accent"])
		tv.add_child(tname)

		var tsub := Label.new()
		tsub.text = str(td["subtitle"])
		tsub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if ThemeManager.font_semi:
			tsub.add_theme_font_override("font", ThemeManager.font_semi)
		tsub.add_theme_font_size_override("font_size", 15)
		tsub.add_theme_color_override("font_color", td["text_dim"])
		tv.add_child(tsub)

		var sw_row := HBoxContainer.new()
		sw_row.add_theme_constant_override("separation", 6)
		tv.add_child(sw_row)
		for sc in td["spotlights"]:
			var sw := ColorRect.new()
			sw.color = sc
			sw.custom_minimum_size = Vector2(30, 16)
			sw_row.add_child(sw)

		var btn := Button.new()
		btn.text = "✓ ACTIVE" if active else "APPLY"
		btn.custom_minimum_size = Vector2(0, 42)
		ThemeManager.style_button(btn, active, td["accent"])
		var target_id := str(tid)
		btn.pressed.connect(func():
			GameState.play_star_sfx()
			ThemeManager.set_theme(target_id)
		)
		tv.add_child(btn)

# ============================================================================
# TAB 3: SETTINGS, 60FPS CONTROLS & LATENCY CALIBRATION
# ============================================================================
func _build_settings_tab(t: Dictionary) -> void:
	var card := PanelContainer.new()
	card.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 14, 2, 8))
	_content_stack.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)

	var hsplit := HBoxContainer.new()
	hsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 20)
	scroll.add_child(hsplit)

	# Left column: Gameplay & Visual Sliders
	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 10)
	hsplit.add_child(left_v)

	var stitle := Label.new()
	stitle.text = "GAMEPLAY & STAGE"
	if ThemeManager.font_display:
		stitle.add_theme_font_override("font", ThemeManager.font_display)
	stitle.add_theme_font_size_override("font_size", 19)
	stitle.add_theme_color_override("font_color", t["accent"])
	left_v.add_child(stitle)

	_add_slider_row(left_v, "Highway Note Speed", 0.7, 1.8, 0.05, float(GameState.settings.get("note_speed", 1.0)), func(v: float):
		GameState.settings["note_speed"] = v
		GameState.save_data()
	)
	_add_slider_row(left_v, "Stage Drum Light Intensity", 0.4, 1.5, 0.05, float(GameState.settings.get("light_intensity", 1.0)), func(v: float):
		GameState.settings["light_intensity"] = v
		GameState.save_data()
	)
	_add_slider_row(left_v, "Music Volume", 0.1, 1.0, 0.05, float(GameState.settings.get("music_volume", 1.0)), func(v: float):
		GameState.settings["music_volume"] = v
		GameState.save_data()
	)
	_add_slider_row(left_v, "SFX Volume", 0.0, 1.0, 0.05, float(GameState.settings.get("sfx_volume", 0.85)), func(v: float):
		GameState.settings["sfx_volume"] = v
		GameState.save_data()
	)

	var chk_nofail := CheckButton.new()
	chk_nofail.text = "No-Fail Mode"
	if ThemeManager.font_body:
		chk_nofail.add_theme_font_override("font", ThemeManager.font_body)
	chk_nofail.add_theme_font_size_override("font_size", 18)
	chk_nofail.button_pressed = bool(GameState.settings.get("no_fail", false))
	chk_nofail.toggled.connect(func(on: bool):
		GameState.settings["no_fail"] = on
		GameState.save_data()
	)
	left_v.add_child(chk_nofail)

	var chk_fps := CheckButton.new()
	chk_fps.text = "Show FPS Counter in HUD"
	if ThemeManager.font_body:
		chk_fps.add_theme_font_override("font", ThemeManager.font_body)
	chk_fps.add_theme_font_size_override("font_size", 18)
	chk_fps.button_pressed = bool(GameState.settings.get("show_fps", true))
	chk_fps.toggled.connect(func(on: bool):
		GameState.settings["show_fps"] = on
		GameState.save_data()
	)
	left_v.add_child(chk_fps)

	# Right column: Audio / Touch Latency Calibration
	var right_v := VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.add_theme_constant_override("separation", 10)
	hsplit.add_child(right_v)

	var ctitle := Label.new()
	ctitle.text = "LATENCY CALIBRATION"
	if ThemeManager.font_display:
		ctitle.add_theme_font_override("font", ThemeManager.font_display)
	ctitle.add_theme_font_size_override("font_size", 19)
	ctitle.add_theme_color_override("font_color", t["accent_2"])
	right_v.add_child(ctitle)

	_cal_lbl = Label.new()
	_cal_lbl.text = "Audio Offset: %d ms" % int(round(float(GameState.settings.get("audio_offset_ms", 0.0))))
	if ThemeManager.font_body:
		_cal_lbl.add_theme_font_override("font", ThemeManager.font_body)
	_cal_lbl.add_theme_font_size_override("font_size", 20)
	right_v.add_child(_cal_lbl)

	var cal_slider := HSlider.new()
	cal_slider.min_value = -150.0
	cal_slider.max_value = 150.0
	cal_slider.step = 5.0
	cal_slider.custom_minimum_size = Vector2(0, 30)
	cal_slider.value = float(GameState.settings.get("audio_offset_ms", 0.0))
	cal_slider.value_changed.connect(func(v: float):
		GameState.settings["audio_offset_ms"] = v
		GameState.save_data()
		_cal_lbl.text = "Audio Offset: %d ms" % int(round(v))
	)
	right_v.add_child(cal_slider)

	var btn_toggle_beat := Button.new()
	btn_toggle_beat.text = "▶ START BEAT SOUND TEST"
	btn_toggle_beat.custom_minimum_size = Vector2(0, 44)
	ThemeManager.style_button(btn_toggle_beat, false)
	btn_toggle_beat.pressed.connect(func():
		_cal_test_active = not _cal_test_active
		_cal_beat_timer = 0.0
		_cal_taps.clear()
		btn_toggle_beat.text = "■ STOP BEAT SOUND TEST" if _cal_test_active else "▶ START BEAT SOUND TEST"
	)
	right_v.add_child(btn_toggle_beat)

	var btn_tap := Button.new()
	btn_tap.text = "🥁 TAP ON BEAT TO CALIBRATE"
	btn_tap.custom_minimum_size = Vector2(0, 52)
	ThemeManager.style_button(btn_tap, true, t["accent_2"])
	btn_tap.pressed.connect(func():
		if not _cal_test_active:
			_cal_test_active = true
			_cal_beat_timer = 0.0
			btn_toggle_beat.text = "■ STOP BEAT SOUND TEST"
			return
		var signed_err := _cal_beat_timer if _cal_beat_timer <= 0.25 else (_cal_beat_timer - 0.5)
		_cal_taps.append(signed_err * 1000.0)
		if _cal_taps.size() > 6:
			_cal_taps.pop_front()
		var sum := 0.0
		for x in _cal_taps:
			sum += x
		var avg_ms := clampf(round((sum / float(_cal_taps.size())) / 5.0) * 5.0, -150.0, 150.0)
		cal_slider.value = avg_ms
	)
	right_v.add_child(btn_tap)

func _add_slider_row(parent: Control, label_txt: String, min_v: float, max_v: float, step_v: float, init_v: float, cb: Callable) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 2)
	parent.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var l := Label.new()
	l.text = label_txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_body:
		l.add_theme_font_override("font", ThemeManager.font_body)
	l.add_theme_font_size_override("font_size", 18)
	hb.add_child(l)
	var vl := Label.new()
	vl.text = "%.2f" % init_v
	if ThemeManager.font_body:
		vl.add_theme_font_override("font", ThemeManager.font_body)
	vl.add_theme_font_size_override("font_size", 18)
	hb.add_child(vl)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = init_v
	sl.custom_minimum_size = Vector2(0, 28)
	sl.value_changed.connect(func(val: float):
		vl.text = "%.2f" % val
		cb.call(val)
	)
	vb.add_child(sl)
