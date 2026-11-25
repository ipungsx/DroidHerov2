# Copyright (c) 2026 ipungsx (https://github.com/ipungsx)
extends Control

# Native Portrait HD Smartphone Game Menu for DroidHeroV2 (720x1600):
# Full-screen single-column mobile game navigation:
# - SCREEN 0: HOME (Hero logo, stats pill, active song vinyl card, 4 huge full-width buttons, EN/ID & About)
# - SCREEN 1: SONG SELECT (Big vertical song cards, page_size=10, sort/import/preview controls)
# - SCREEN 2: DIFFICULTY (2x2 huge difficulty cards matching real chart diffs, No-Fail, giant PLAY button)
# - SCREEN 3: ENCHOR.US STORE (Full-width search bar, diff filter, page_size=10, mobile chart cards)
# - SCREEN 4: CUSTOMIZE (6 Background Visualizers, 3 HD Fretboard decks & 5 Arena Themes)
# - SCREEN 5: SETTINGS (Single-column scrollable sliders, flashing lights toggle, hit window, calibration)
# - SCREEN 6: ABOUT (Credits, Copyright, Open-Source Licenses & Legal Notice)
# - SCREEN 7: INTRO SPLASH (By ipungsx / github.com/ipungsx)

enum Screen {
	HOME = 0,
	SONGS = 1,
	DIFFICULTY = 2,
	ENCHOR = 3,
	CUSTOMIZE = 4,
	SETTINGS = 5,
	ABOUT = 6,
	INTRO = 7
}

class VinylDisc extends Control:
	var accent: Color = Color(0.0, 0.94, 1.0)
	var accent2: Color = Color(1.0, 0.2, 0.75)
	var spinning: bool = false
	var angle: float = 0.0

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _process(delta: float) -> void:
		if spinning:
			angle = fmod(angle + delta * 1.8, TAU)
			queue_redraw()

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.46
		if r <= 8.0:
			return
		draw_circle(c + Vector2(0, 6), r * 1.03, Color(0, 0, 0, 0.48))
		draw_circle(c, r, Color(0.06, 0.06, 0.10, 0.98))
		draw_arc(c, r, 0.0, TAU, 64, accent, 3.5)
		for g in range(1, 6):
			var gr := r * (0.38 + float(g) * 0.095)
			draw_arc(c, gr, 0.0, TAU, 48, Color(1, 1, 1, 0.07), 1.4)
		for s in range(2):
			var a0 := angle + float(s) * PI
			draw_arc(c, r * 0.68, a0, a0 + 0.55, 20, Color(accent.r, accent.g, accent.b, 0.28), r * 0.36)
			draw_arc(c, r * 0.68, a0 + 0.6, a0 + 0.95, 16, Color(accent2.r, accent2.g, accent2.b, 0.22), r * 0.36)
		draw_circle(c, r * 0.31, accent2.darkened(0.22))
		draw_arc(c, r * 0.31, 0.0, TAU, 40, Color.WHITE, 2.2)
		draw_circle(c, r * 0.09, Color(0.03, 0.03, 0.06, 1.0))

const PAGE_SIZE := 10

var _stage: ConcertStage
var _screen_holder: Control
var _current_screen: int = Screen.HOME
var _sort_mode: int = 0
var _local_page: int = 1
var _local_total_pages: int = 1

# Song Select refs
var _lib_list_vbox: VBoxContainer
var _lib_scroll: ScrollContainer
var _lib_page_lbl: Label
var _lib_btn_prev: Button
var _lib_btn_next: Button
var _sel_banner_lbl: Label
var _vinyl: VinylDisc
var _preview_player: AudioStreamPlayer
var _preview_active: bool = false
var _btn_preview: Button

# Enchor.us refs
var _search_input: LineEdit
var _enchor_status: Label
var _enchor_list_vbox: VBoxContainer
var _enchor_scroll: ScrollContainer
var _enchor_page: int = 1
var _enchor_total_pages: int = 1
var _enchor_last_query: String = "*"
var _enchor_diff_filter: String = ""
var _enchor_page_lbl: Label
var _enchor_btn_prev: Button
var _enchor_btn_next: Button
var _dl_modal: PanelContainer
var _dl_label: Label
var _dl_bar: ProgressBar
var _cover_rects: Dictionary = {}
var _file_dialog: FileDialog

# Settings refs
var _cal_taps: Array[float] = []
var _cal_beat_timer: float = 0.0
var _cal_test_active: bool = false
var _cal_lbl: Label
var _fps_lbl: Label

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ThemeManager.theme_changed.connect(_on_theme_changed)
	I18n.language_changed.connect(_on_language_changed)
	EnchorClient.search_completed.connect(_on_enchor_results)
	EnchorClient.download_progress.connect(_on_dl_progress)
	EnchorClient.download_completed.connect(_on_dl_completed)
	EnchorClient.cover_loaded.connect(_on_cover_loaded)

	GameState.scan_library()
	if GameState.current_song.is_empty() and not GameState.library.is_empty():
		GameState.current_song = GameState.library[0]

	var start_scr := GameState.open_screen_on_menu
	GameState.open_screen_on_menu = Screen.HOME
	_build_base()
	if not GameState.intro_shown and start_scr == Screen.HOME:
		GameState.intro_shown = true
		_show_screen(Screen.INTRO, false)
	else:
		_show_screen(start_scr, false)

func _process(delta: float) -> void:
	if _fps_lbl and is_instance_valid(_fps_lbl):
		_fps_lbl.text = str(Engine.get_frames_per_second()) + " FPS"

	if _current_screen == Screen.SETTINGS and _cal_test_active:
		_cal_beat_timer += delta
		if _cal_beat_timer >= 0.5:
			_cal_beat_timer -= 0.5
			GameState.play_click()
			if _stage:
				_stage.music_playing = true
				_stage.trigger_drum(0, 0.78)
	elif _preview_active and _preview_player and _preview_player.playing:
		if _stage:
			_stage.music_playing = true
	else:
		if _stage:
			_stage.music_playing = false

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if _dl_modal and _dl_modal.visible:
			EnchorClient.cancel_download()
			_dl_modal.visible = false
			get_viewport().set_input_as_handled()
			return
		if _current_screen == Screen.DIFFICULTY:
			GameState.play_click()
			_show_screen(Screen.SONGS)
			get_viewport().set_input_as_handled()
		elif _current_screen != Screen.HOME:
			GameState.play_click()
			_show_screen(Screen.HOME)
			get_viewport().set_input_as_handled()

func _on_theme_changed(_id: String) -> void:
	var keep := _current_screen
	_stop_preview()
	_build_base()
	_show_screen(keep, false)

func _on_language_changed(_lang: String) -> void:
	var keep := _current_screen
	_stop_preview()
	_build_base()
	_show_screen(keep, false)

func _make_touch_scroll() -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = false
	scroll.scroll_deadzone = 12
	return scroll

func _make_scroll_pass(ctrl: Control) -> void:
	if ctrl is HSlider:
		return
	if ctrl is BaseButton:
		ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
		(ctrl as BaseButton).action_mode = BaseButton.ACTION_MODE_BUTTON_RELEASE
	elif ctrl is Label or ctrl is TextureRect or ctrl is ColorRect:
		ctrl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	else:
		ctrl.mouse_filter = Control.MOUSE_FILTER_PASS
	for child in ctrl.get_children():
		if child is Control:
			_make_scroll_pass(child as Control)

func _build_base() -> void:
	for c in get_children():
		c.queue_free()
	_cover_rects.clear()

	_stage = ConcertStage.new()
	_stage.menu_idle_mode = true
	_stage.music_playing = false
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	_preview_player = AudioStreamPlayer.new()
	_preview_player.bus = "Music"
	add_child(_preview_player)

	_screen_holder = Control.new()
	_screen_holder.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_screen_holder)

	var t := ThemeManager.get_theme_data()
	_build_download_modal(t)
	_build_file_importer()

func _stop_preview() -> void:
	_preview_active = false
	if _preview_player and is_instance_valid(_preview_player):
		_preview_player.stop()
	if _vinyl and is_instance_valid(_vinyl):
		_vinyl.spinning = false
	if _btn_preview and is_instance_valid(_btn_preview):
		_btn_preview.text = I18n.t("preview")

func _toggle_song_preview() -> void:
	if _preview_active:
		_stop_preview()
		return
	var pkg := SngParser.load_song_package(GameState.current_song)
	var streams: Array = pkg.get("streams", [])
	if streams.is_empty():
		return
	_preview_player.stream = streams[0]
	_preview_player.volume_db = linear_to_db(clampf(float(GameState.settings.get("music_volume", 1.0)) * 0.85, 0.05, 1.0))
	_preview_player.play(maxf(0.0, streams[0].get_length() * 0.22))
	_preview_active = true
	if _vinyl and is_instance_valid(_vinyl):
		_vinyl.spinning = true
	if _btn_preview and is_instance_valid(_btn_preview):
		_btn_preview.text = I18n.t("stop_preview")

func _show_screen(scr: int, animate: bool = true) -> void:
	if scr != Screen.SONGS:
		_stop_preview()
	if scr != Screen.SETTINGS:
		_cal_test_active = false
	_current_screen = scr

	for c in _screen_holder.get_children():
		c.queue_free()

	var t := ThemeManager.get_theme_data()
	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 28)
	page.add_theme_constant_override("margin_right", 28)
	page.add_theme_constant_override("margin_top", 46)
	page.add_theme_constant_override("margin_bottom", 34)
	_screen_holder.add_child(page)

	match scr:
		Screen.HOME:
			_build_home_screen(page, t)
		Screen.SONGS:
			_build_songs_screen(page, t)
		Screen.DIFFICULTY:
			_build_difficulty_screen(page, t)
		Screen.ENCHOR:
			_build_enchor_screen(page, t)
		Screen.CUSTOMIZE:
			_build_customize_screen(page, t)
		Screen.SETTINGS:
			_build_settings_screen(page, t)
		Screen.ABOUT:
			_build_about_screen(page, t)
		Screen.INTRO:
			_build_intro_screen(page, t)

	if animate:
		page.modulate.a = 0.0
		page.position.y = 26.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(page, "modulate:a", 1.0, 0.16)
		tw.tween_property(page, "position:y", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _make_top_bar(parent: VBoxContainer, title_txt: String, back_target: int, t: Dictionary) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 16)
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	parent.add_child(bar)

	var btn_back := Button.new()
	btn_back.text = "◀"
	btn_back.custom_minimum_size = Vector2(88, 76)
	ThemeManager.style_button(btn_back, false)
	btn_back.add_theme_font_size_override("font_size", 32)
	btn_back.pressed.connect(func():
		GameState.play_click()
		_show_screen(back_target)
	)
	bar.add_child(btn_back)

	var title := Label.new()
	title.text = title_txt
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.clip_text = true
	if ThemeManager.font_display:
		title.add_theme_font_override("font", ThemeManager.font_display)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", t["accent"])
	bar.add_child(title)
	return bar

# ============================================================================
# SCREEN 0: PORTRAIT SMARTPHONE HOME HUB (720x1600)
# ============================================================================
func _build_home_screen(parent: MarginContainer, t: Dictionary) -> void:
	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 22)
	parent.add_child(root_vb)

	# 0. Top Utility Row (About button on left + English/Indonesia toggle on right)
	var top_row := HBoxContainer.new()
	top_row.add_theme_constant_override("separation", 12)
	root_vb.add_child(top_row)

	var about_btn := Button.new()
	about_btn.text = I18n.t("menu_about")
	about_btn.custom_minimum_size = Vector2(180, 58)
	ThemeManager.style_button(about_btn, false, t["accent_2"])
	about_btn.add_theme_font_size_override("font_size", 22)
	about_btn.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.ABOUT)
	)
	top_row.add_child(about_btn)

	var top_sp := Control.new()
	top_sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(top_sp)

	var lang_btn := Button.new()
	lang_btn.text = "🌐  EN / ID  •  " + ("INDONESIA" if I18n.current_lang == "id" else "ENGLISH")
	lang_btn.custom_minimum_size = Vector2(280, 58)
	ThemeManager.style_button(lang_btn, false, t["accent"])
	lang_btn.add_theme_font_size_override("font_size", 22)
	lang_btn.pressed.connect(func():
		GameState.play_click()
		I18n.toggle_language()
	)
	top_row.add_child(lang_btn)

	# 1. Centered Hero Logo Header
	var hero_vb := VBoxContainer.new()
	hero_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_vb.add_theme_constant_override("separation", 4)
	root_vb.add_child(hero_vb)

	var logo := Label.new()
	logo.text = "DROIDHERO"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		logo.add_theme_font_override("font", ThemeManager.font_display)
	logo.add_theme_font_size_override("font_size", 72)
	logo.add_theme_color_override("font_color", t["accent"])
	hero_vb.add_child(logo)

	var sub := Label.new()
	sub.text = I18n.t("subtitle")
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		sub.add_theme_font_override("font", ThemeManager.font_display)
	sub.add_theme_font_size_override("font_size", 23)
	sub.add_theme_color_override("font_color", t["accent_2"])
	hero_vb.add_child(sub)

	# 2. Compact Stats Pill
	var stats_pill := PanelContainer.new()
	stats_pill.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], Color(1, 1, 1, 0.22), 20, 1, 0))
	root_vb.add_child(stats_pill)

	var stats_lbl := Label.new()
	stats_lbl.text = I18n.t("stats_pill") % [GameState.library.size(), GameState.get_total_stars()]
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_body:
		stats_lbl.add_theme_font_override("font", ThemeManager.font_body)
	stats_lbl.add_theme_font_size_override("font_size", 25)
	stats_lbl.add_theme_color_override("font_color", t["text"])
	stats_pill.add_child(stats_lbl)

	# 3. Active Song Showcase Card with Vinyl Disc
	var now_card := PanelContainer.new()
	now_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["border"], 26, 2, 16))
	root_vb.add_child(now_card)

	var now_vb := VBoxContainer.new()
	now_vb.add_theme_constant_override("separation", 16)
	now_card.add_child(now_vb)

	var now_hb := HBoxContainer.new()
	now_hb.add_theme_constant_override("separation", 22)
	now_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	now_vb.add_child(now_hb)

	var home_vinyl := VinylDisc.new()
	home_vinyl.accent = t["accent"]
	home_vinyl.accent2 = t["accent_2"]
	home_vinyl.custom_minimum_size = Vector2(140, 140)
	now_hb.add_child(home_vinyl)

	var info_vb := VBoxContainer.new()
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vb.add_theme_constant_override("separation", 6)
	now_hb.add_child(info_vb)

	var tag_lbl := Label.new()
	tag_lbl.text = I18n.t("ready_to_play")
	if ThemeManager.font_semi:
		tag_lbl.add_theme_font_override("font", ThemeManager.font_semi)
	tag_lbl.add_theme_font_size_override("font_size", 22)
	tag_lbl.add_theme_color_override("font_color", t["accent"])
	info_vb.add_child(tag_lbl)

	var s_name := Label.new()
	s_name.text = str(GameState.current_song.get("name", "Neon Overdrive"))
	s_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s_name.max_lines_visible = 2
	if ThemeManager.font_display:
		s_name.add_theme_font_override("font", ThemeManager.font_display)
	s_name.add_theme_font_size_override("font_size", 27)
	s_name.add_theme_color_override("font_color", t["text"])
	info_vb.add_child(s_name)

	var s_art := Label.new()
	s_art.text = str(GameState.current_song.get("artist", "DroidHero Studio")) + " • " + GameState.current_difficulty.to_upper()
	if ThemeManager.font_body:
		s_art.add_theme_font_override("font", ThemeManager.font_body)
	s_art.add_theme_font_size_override("font_size", 23)
	s_art.add_theme_color_override("font_color", t["text_dim"])
	info_vb.add_child(s_art)

	var btn_quick := Button.new()
	btn_quick.text = I18n.t("quick_play")
	btn_quick.custom_minimum_size = Vector2(0, 84)
	ThemeManager.style_button(btn_quick, true, t["accent_2"])
	btn_quick.add_theme_font_size_override("font_size", 28)
	btn_quick.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.DIFFICULTY)
	)
	now_vb.add_child(btn_quick)

	# 4. Flexible Spacer to push main menu buttons comfortably into thumb reach
	var mid_sp := Control.new()
	mid_sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(mid_sp)

	# 5. Four Huge Full-Width Smartphone Game Buttons
	var btn_play := _make_mobile_menu_btn(I18n.t("menu_play"), I18n.t("menu_play_sub"), true, t["accent"], 124)
	btn_play.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.SONGS)
	)
	root_vb.add_child(btn_play)

	var btn_store := _make_mobile_menu_btn(I18n.t("menu_store"), I18n.t("menu_store_sub"), false, t["accent_2"], 114)
	btn_store.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.ENCHOR)
	)
	root_vb.add_child(btn_store)

	var btn_cust := _make_mobile_menu_btn(I18n.t("menu_customize"), I18n.t("menu_customize_sub"), false, t["accent_3"], 114)
	btn_cust.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.CUSTOMIZE)
	)
	root_vb.add_child(btn_cust)

	var btn_set := _make_mobile_menu_btn(I18n.t("menu_settings"), I18n.t("menu_settings_sub"), false, t["border"], 114)
	btn_set.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.SETTINGS)
	)
	root_vb.add_child(btn_set)

func _make_mobile_menu_btn(title_txt: String, sub_txt: String, primary: bool, col: Color, min_h: int) -> Button:
	var t := ThemeManager.get_theme_data()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, min_h)
	btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ThemeManager.style_button(btn, primary, col)

	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 28)
	pad.add_theme_constant_override("margin_right", 28)
	btn.add_child(pad)

	var vb := VBoxContainer.new()
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 4)
	pad.add_child(vb)

	var tl := Label.new()
	tl.text = title_txt
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_display:
		tl.add_theme_font_override("font", ThemeManager.font_display)
	tl.add_theme_font_size_override("font_size", 35 if primary else 29)
	tl.add_theme_color_override("font_color", Color.WHITE if primary else t["text"])
	vb.add_child(tl)

	var sl := Label.new()
	sl.text = sub_txt
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_body:
		sl.add_theme_font_override("font", ThemeManager.font_body)
	sl.add_theme_font_size_override("font_size", 22)
	sl.add_theme_color_override("font_color", t["text_dim"])
	vb.add_child(sl)
	return btn

# ============================================================================
# SCREEN 1: PORTRAIT SONG SELECT (page_size = 10 + Smooth Touch Scroll)
# ============================================================================
func _build_songs_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	parent.add_child(vbox)

	_make_top_bar(vbox, I18n.t("select_song"), Screen.HOME, t)

	# Action Pill Row (Sort + Preview + Import)
	var tools_hb := HBoxContainer.new()
	tools_hb.add_theme_constant_override("separation", 12)
	vbox.add_child(tools_hb)

	var sort_names := [I18n.t("sort_title"), I18n.t("sort_artist"), I18n.t("sort_stars")]
	var btn_sort := Button.new()
	btn_sort.text = sort_names[_sort_mode]
	btn_sort.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_sort.custom_minimum_size = Vector2(0, 70)
	ThemeManager.style_button(btn_sort, false)
	btn_sort.add_theme_font_size_override("font_size", 23)
	btn_sort.pressed.connect(func():
		GameState.play_click()
		_sort_mode = (_sort_mode + 1) % 3
		_local_page = 1
		btn_sort.text = sort_names[_sort_mode]
		_populate_song_cards()
	)
	tools_hb.add_child(btn_sort)

	_btn_preview = Button.new()
	_btn_preview.text = I18n.t("preview")
	_btn_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_preview.custom_minimum_size = Vector2(0, 70)
	ThemeManager.style_button(_btn_preview, false)
	_btn_preview.add_theme_font_size_override("font_size", 23)
	_btn_preview.pressed.connect(func():
		GameState.play_click()
		_toggle_song_preview()
	)
	tools_hb.add_child(_btn_preview)

	var btn_imp := Button.new()
	btn_imp.text = I18n.t("import_btn")
	btn_imp.custom_minimum_size = Vector2(175, 70)
	ThemeManager.style_button(btn_imp, false, t["accent_2"])
	btn_imp.add_theme_font_size_override("font_size", 23)
	btn_imp.pressed.connect(func():
		GameState.play_click()
		_file_dialog.popup_centered_ratio(0.92)
	)
	tools_hb.add_child(btn_imp)

	# Scrollable Vertical Song List (touch-friendly)
	var list_panel := PanelContainer.new()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	vbox.add_child(list_panel)

	_lib_scroll = _make_touch_scroll()
	list_panel.add_child(_lib_scroll)

	_lib_list_vbox = VBoxContainer.new()
	_lib_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_list_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_lib_list_vbox.add_theme_constant_override("separation", 14)
	_lib_scroll.add_child(_lib_list_vbox)

	# Local Library Pagination Row (page_size = 10)
	var page_hb := HBoxContainer.new()
	page_hb.add_theme_constant_override("separation", 12)
	page_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(page_hb)

	_lib_btn_prev = Button.new()
	_lib_btn_prev.text = I18n.t("prev_btn")
	_lib_btn_prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_btn_prev.custom_minimum_size = Vector2(0, 64)
	ThemeManager.style_button(_lib_btn_prev, false)
	_lib_btn_prev.add_theme_font_size_override("font_size", 22)
	_lib_btn_prev.pressed.connect(func():
		if _local_page > 1:
			GameState.play_click()
			_local_page -= 1
			_populate_song_cards()
	)
	page_hb.add_child(_lib_btn_prev)

	_lib_page_lbl = Label.new()
	_lib_page_lbl.text = I18n.t("page_indicator") % [1, 1]
	_lib_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lib_page_lbl.custom_minimum_size = Vector2(150, 0)
	if ThemeManager.font_display:
		_lib_page_lbl.add_theme_font_override("font", ThemeManager.font_display)
	_lib_page_lbl.add_theme_font_size_override("font_size", 22)
	_lib_page_lbl.add_theme_color_override("font_color", t["accent"])
	page_hb.add_child(_lib_page_lbl)

	_lib_btn_next = Button.new()
	_lib_btn_next.text = I18n.t("next_btn")
	_lib_btn_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_btn_next.custom_minimum_size = Vector2(0, 64)
	ThemeManager.style_button(_lib_btn_next, false)
	_lib_btn_next.add_theme_font_size_override("font_size", 22)
	_lib_btn_next.pressed.connect(func():
		if _local_page < _local_total_pages:
			GameState.play_click()
			_local_page += 1
			_populate_song_cards()
	)
	page_hb.add_child(_lib_btn_next)

	# Sticky Bottom Selected Song & Next Step Card
	var bot_card := PanelContainer.new()
	bot_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["accent_2"], 22, 2, 12))
	vbox.add_child(bot_card)

	var bot_vb := VBoxContainer.new()
	bot_vb.add_theme_constant_override("separation", 12)
	bot_card.add_child(bot_vb)

	var sel_hb := HBoxContainer.new()
	sel_hb.add_theme_constant_override("separation", 16)
	sel_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_vb.add_child(sel_hb)

	_vinyl = VinylDisc.new()
	_vinyl.accent = t["accent"]
	_vinyl.accent2 = t["accent_2"]
	_vinyl.custom_minimum_size = Vector2(86, 86)
	sel_hb.add_child(_vinyl)

	_sel_banner_lbl = Label.new()
	_sel_banner_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_banner_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		_sel_banner_lbl.add_theme_font_override("font", ThemeManager.font_body)
	_sel_banner_lbl.add_theme_font_size_override("font_size", 24)
	_sel_banner_lbl.add_theme_color_override("font_color", t["text"])
	sel_hb.add_child(_sel_banner_lbl)

	var btn_next := Button.new()
	btn_next.text = I18n.t("select_diff_btn")
	btn_next.custom_minimum_size = Vector2(0, 88)
	ThemeManager.style_button(btn_next, true, t["accent"])
	btn_next.add_theme_font_size_override("font_size", 30)
	btn_next.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.DIFFICULTY)
	)
	bot_vb.add_child(btn_next)

	GameState.scan_library()
	_populate_song_cards()

func _get_best_stars_any_diff(song_id: String) -> int:
	var best_s := 0
	for d in ["Easy", "Medium", "Hard", "Expert"]:
		var rec := GameState.get_best(song_id, d)
		best_s = maxi(best_s, int(rec.get("stars", 0)))
	return best_s

func _populate_song_cards() -> void:
	if not _lib_list_vbox:
		return
	for c in _lib_list_vbox.get_children():
		c.queue_free()
	var t := ThemeManager.get_theme_data()

	var songs := GameState.library.duplicate()
	songs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if _sort_mode == 1:
			return str(a.get("artist", "")).nocasecmp_to(str(b.get("artist", ""))) < 0
		elif _sort_mode == 2:
			var sa := _get_best_stars_any_diff(str(a.get("id", "")))
			var sb := _get_best_stars_any_diff(str(b.get("id", "")))
			if sa != sb:
				return sa > sb
		return str(a.get("name", "")).nocasecmp_to(str(b.get("name", ""))) < 0
	)

	_local_total_pages = maxi(1, int(ceil(float(songs.size()) / float(PAGE_SIZE))))
	_local_page = clampi(_local_page, 1, _local_total_pages)
	var start_idx := (_local_page - 1) * PAGE_SIZE
	var end_idx := mini(start_idx + PAGE_SIZE, songs.size())

	if _lib_page_lbl:
		_lib_page_lbl.text = I18n.t("page_indicator") % [_local_page, _local_total_pages]
	if _lib_btn_prev:
		_lib_btn_prev.disabled = (_local_page <= 1)
	if _lib_btn_next:
		_lib_btn_next.disabled = (_local_page >= _local_total_pages)
	if _lib_scroll:
		_lib_scroll.scroll_vertical = 0

	for idx in range(start_idx, end_idx):
		var song: Dictionary = songs[idx]
		var is_sel := str(song.get("id", "")) == str(GameState.current_song.get("id", ""))
		var card_btn := Button.new()
		card_btn.custom_minimum_size = Vector2(0, 122)
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeManager.style_button(card_btn, is_sel, t["accent"] if is_sel else Color(1, 1, 1, 0.22))

		var pad := MarginContainer.new()
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override("margin_left", 22)
		pad.add_theme_constant_override("margin_right", 22)
		card_btn.add_child(pad)

		var vb := VBoxContainer.new()
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_theme_constant_override("separation", 4)
		pad.add_child(vb)

		var nt := Label.new()
		nt.text = ("▶  " if is_sel else "") + str(song.get("name", "Song"))
		nt.clip_text = true
		nt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ThemeManager.font_display:
			nt.add_theme_font_override("font", ThemeManager.font_display)
		nt.add_theme_font_size_override("font_size", 26)
		nt.add_theme_color_override("font_color", Color.WHITE if is_sel else t["text"])
		vb.add_child(nt)

		var bot_hb := HBoxContainer.new()
		bot_hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		vb.add_child(bot_hb)

		var dur_s := int(song.get("song_length", 180000)) / 1000
		var sub := Label.new()
		sub.text = "%s • %d:%02d" % [str(song.get("artist", "Artist")), dur_s / 60, dur_s % 60]
		sub.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sub.clip_text = true
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ThemeManager.font_body:
			sub.add_theme_font_override("font", ThemeManager.font_body)
		sub.add_theme_font_size_override("font_size", 23)
		sub.add_theme_color_override("font_color", t["text_dim"])
		bot_hb.add_child(sub)

		var best_st := _get_best_stars_any_diff(str(song.get("id", "")))
		var st_lbl := Label.new()
		st_lbl.text = ("★".repeat(best_st) + "☆".repeat(5 - best_st)) if best_st > 0 else I18n.t("new_badge")
		st_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ThemeManager.font_body:
			st_lbl.add_theme_font_override("font", ThemeManager.font_body)
		st_lbl.add_theme_font_size_override("font_size", 24)
		st_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22) if best_st > 0 else t["accent"])
		bot_hb.add_child(st_lbl)

		var s_copy: Dictionary = song
		card_btn.pressed.connect(func():
			GameState.play_click()
			if str(GameState.current_song.get("id", "")) == str(s_copy.get("id", "")):
				_show_screen(Screen.DIFFICULTY)
				return
			_stop_preview()
			GameState.current_song = s_copy
			_populate_song_cards()
		)
		_make_scroll_pass(card_btn)
		_lib_list_vbox.add_child(card_btn)

	if _sel_banner_lbl:
		var s := GameState.current_song
		_sel_banner_lbl.text = "%s\n%s" % [str(s.get("name", "Neon Overdrive")), str(s.get("artist", "-"))]

# ============================================================================
# SCREEN 2: PORTRAIT DIFFICULTY & LAUNCHER (2x2 HUGE GRID)
# ============================================================================
func _build_difficulty_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 22)
	parent.add_child(vbox)

	_make_top_bar(vbox, I18n.t("difficulty_title"), Screen.SONGS, t)

	# Determine real available difficulties charted for this song (matching enchor.us / chart)
	var avail_diffs: Array[String] = SngParser.get_available_difficulties(GameState.current_song)
	if avail_diffs.is_empty():
		avail_diffs = ["Expert"]
	if not avail_diffs.has(GameState.current_difficulty):
		GameState.current_difficulty = avail_diffs[avail_diffs.size() - 1]

	# Selected Song Header Card
	var scard := PanelContainer.new()
	scard.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 20, 2, 8))
	vbox.add_child(scard)

	var slbl := Label.new()
	slbl.text = "%s\n%s" % [str(GameState.current_song.get("name", "Song")), str(GameState.current_song.get("artist", "-"))]
	slbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	slbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_display:
		slbl.add_theme_font_override("font", ThemeManager.font_display)
	slbl.add_theme_font_size_override("font_size", 28)
	slbl.add_theme_color_override("font_color", t["text"])
	scard.add_child(slbl)

	# 2x2 Big Smartphone Difficulty Cards
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	vbox.add_child(grid)

	var diff_defs := [
		{"id": "Easy", "title": "EASY", "desc": I18n.t("diff_easy_desc"), "col": Color(0.12, 0.96, 0.48)},
		{"id": "Medium", "title": "MEDIUM", "desc": I18n.t("diff_med_desc"), "col": Color(1.0, 0.84, 0.16)},
		{"id": "Hard", "title": "HARD", "desc": I18n.t("diff_hard_desc"), "col": Color(1.0, 0.52, 0.12)},
		{"id": "Expert", "title": "EXPERT", "desc": I18n.t("diff_exp_desc"), "col": Color(1.0, 0.20, 0.34)}
	]

	for dd in diff_defs:
		var d_id: String = dd["id"]
		var is_avail := avail_diffs.has(d_id)
		var is_sel := is_avail and (GameState.current_difficulty == d_id)
		var dcol: Color = dd["col"]

		var dbtn := Button.new()
		dbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dbtn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		dbtn.disabled = not is_avail
		ThemeManager.style_button(dbtn, is_sel, dcol if is_avail else Color(0.4, 0.4, 0.45))
		if not is_avail:
			dbtn.modulate = Color(0.48, 0.48, 0.54, 0.62)

		var cv := VBoxContainer.new()
		cv.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		cv.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cv.alignment = BoxContainer.ALIGNMENT_CENTER
		cv.add_theme_constant_override("separation", 12)
		dbtn.add_child(cv)

		var dlbl := Label.new()
		dlbl.text = dd["title"]
		dlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_display:
			dlbl.add_theme_font_override("font", ThemeManager.font_display)
		dlbl.add_theme_font_size_override("font_size", 40)
		dlbl.add_theme_color_override("font_color", Color.WHITE if is_sel else (dcol if is_avail else t["text_dim"]))
		cv.add_child(dlbl)

		var dsub := Label.new()
		dsub.text = dd["desc"] if is_avail else I18n.t("not_available")
		dsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_body:
			dsub.add_theme_font_override("font", ThemeManager.font_body)
		dsub.add_theme_font_size_override("font_size", 24)
		dsub.add_theme_color_override("font_color", t["text_dim"])
		cv.add_child(dsub)

		var rec := GameState.get_best(str(GameState.current_song.get("id", "")), d_id)
		var st_cnt := int(rec.get("stars", 0))
		var st_lbl := Label.new()
		st_lbl.text = (("★".repeat(st_cnt) + "☆".repeat(5 - st_cnt)) if st_cnt > 0 else "☆☆☆☆☆") if is_avail else "—"
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_lbl.add_theme_font_size_override("font_size", 34)
		st_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22) if (is_avail and st_cnt > 0) else Color(1, 1, 1, 0.22))
		cv.add_child(st_lbl)

		var best_txt := Label.new()
		best_txt.text = (("%d PTS" % int(rec.get("score", 0))) if not rec.is_empty() else I18n.t("not_played")) if is_avail else ""
		best_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_body:
			best_txt.add_theme_font_override("font", ThemeManager.font_body)
		best_txt.add_theme_font_size_override("font_size", 24)
		best_txt.add_theme_color_override("font_color", t["text"])
		cv.add_child(best_txt)

		if is_avail:
			dbtn.pressed.connect(func():
				GameState.play_click()
				GameState.current_difficulty = d_id
				_show_screen(Screen.DIFFICULTY, false)
			)
		grid.add_child(dbtn)

	# Full-Width No-Fail Toggle (music speed feature removed)
	var nf_on := bool(GameState.settings.get("no_fail", false))
	var btn_nf := Button.new()
	btn_nf.text = I18n.t("nofail_on") if nf_on else I18n.t("nofail_off")
	btn_nf.custom_minimum_size = Vector2(0, 82)
	ThemeManager.style_button(btn_nf, nf_on, Color(0.15, 0.95, 0.55))
	btn_nf.add_theme_font_size_override("font_size", 26)
	btn_nf.pressed.connect(func():
		GameState.play_click()
		GameState.settings["no_fail"] = not nf_on
		GameState.save_data()
		_show_screen(Screen.DIFFICULTY, false)
	)
	vbox.add_child(btn_nf)

	# Giant Bottom Launch Button
	var btn_go := Button.new()
	btn_go.text = I18n.t("start_concert")
	btn_go.custom_minimum_size = Vector2(0, 114)
	ThemeManager.style_button(btn_go, true, t["accent"])
	btn_go.add_theme_font_size_override("font_size", 36)
	btn_go.pressed.connect(func():
		GameState.play_star_sfx()
		GameState.trigger_haptic(30)
		GameState.practice_start_sec = 0.0
		get_tree().change_scene_to_file("res://scenes/Gameplay.tscn")
	)
	vbox.add_child(btn_go)

# ============================================================================
# SCREEN 3: PORTRAIT ENCHOR.US MOBILE STORE (page_size = 10 + Diff Filter + Touch Scroll)
# ============================================================================
func _build_enchor_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	parent.add_child(vbox)

	_make_top_bar(vbox, I18n.t("store_title"), Screen.HOME, t)

	# Full-width Search Box + Buttons
	_search_input = LineEdit.new()
	_search_input.placeholder_text = I18n.t("search_hint")
	_search_input.text = "" if _enchor_last_query == "*" else _enchor_last_query
	_search_input.custom_minimum_size = Vector2(0, 74)
	_search_input.add_theme_stylebox_override("normal", ThemeManager.make_card_style(Color(0.03, 0.03, 0.08, 0.96), t["border"], 18, 2, 0))
	if ThemeManager.font_body:
		_search_input.add_theme_font_override("font", ThemeManager.font_body)
	_search_input.add_theme_font_size_override("font_size", 26)
	_search_input.text_submitted.connect(func(q: String): _trigger_enchor_search(q, 1))
	vbox.add_child(_search_input)

	var s_hb := HBoxContainer.new()
	s_hb.add_theme_constant_override("separation", 12)
	vbox.add_child(s_hb)

	var btn_search := Button.new()
	btn_search.text = I18n.t("search_btn")
	btn_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_search.custom_minimum_size = Vector2(0, 68)
	ThemeManager.style_button(btn_search, true)
	btn_search.add_theme_font_size_override("font_size", 24)
	btn_search.pressed.connect(func():
		GameState.play_click()
		_trigger_enchor_search(_search_input.text, 1)
	)
	s_hb.add_child(btn_search)

	var btn_top := Button.new()
	btn_top.text = I18n.t("popular_btn")
	btn_top.custom_minimum_size = Vector2(180, 68)
	ThemeManager.style_button(btn_top, false)
	btn_top.add_theme_font_size_override("font_size", 23)
	btn_top.pressed.connect(func():
		GameState.play_click()
		_search_input.text = ""
		_trigger_enchor_search("*", 1)
	)
	s_hb.add_child(btn_top)

	# Difficulty Filter Pill Row matching enchor.us API
	var df_hb := HBoxContainer.new()
	df_hb.add_theme_constant_override("separation", 8)
	vbox.add_child(df_hb)

	var filter_opts := [
		{"key": "", "lbl": I18n.t("filter_all"), "col": t["accent"]},
		{"key": "easy", "lbl": "EASY", "col": Color(0.12, 0.96, 0.48)},
		{"key": "medium", "lbl": "MED", "col": Color(1.0, 0.84, 0.16)},
		{"key": "hard", "lbl": "HARD", "col": Color(1.0, 0.52, 0.12)},
		{"key": "expert", "lbl": "EXP", "col": Color(1.0, 0.20, 0.34)}
	]
	for fo in filter_opts:
		var fkey: String = fo["key"]
		var is_act := (_enchor_diff_filter == fkey)
		var fb := Button.new()
		fb.text = fo["lbl"]
		fb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fb.custom_minimum_size = Vector2(0, 56)
		ThemeManager.style_button(fb, is_act, fo["col"])
		fb.add_theme_font_size_override("font_size", 20)
		fb.pressed.connect(func():
			GameState.play_click()
			_enchor_diff_filter = fkey
			_enchor_page = 1
			_show_screen(Screen.ENCHOR, false)
		)
		df_hb.add_child(fb)

	_enchor_status = Label.new()
	_enchor_status.text = I18n.t("loading_charts")
	if ThemeManager.font_body:
		_enchor_status.add_theme_font_override("font", ThemeManager.font_body)
	_enchor_status.add_theme_font_size_override("font_size", 22)
	_enchor_status.add_theme_color_override("font_color", t["text_dim"])
	vbox.add_child(_enchor_status)

	var list_card := PanelContainer.new()
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	vbox.add_child(list_card)

	_enchor_scroll = _make_touch_scroll()
	list_card.add_child(_enchor_scroll)

	_enchor_list_vbox = VBoxContainer.new()
	_enchor_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enchor_list_vbox.mouse_filter = Control.MOUSE_FILTER_PASS
	_enchor_list_vbox.add_theme_constant_override("separation", 14)
	_enchor_scroll.add_child(_enchor_list_vbox)

	# Pagination Row (page_size = 10)
	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 12)
	prow.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_child(prow)

	_enchor_btn_prev = Button.new()
	_enchor_btn_prev.text = I18n.t("prev_btn")
	_enchor_btn_prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enchor_btn_prev.custom_minimum_size = Vector2(0, 68)
	ThemeManager.style_button(_enchor_btn_prev, false)
	_enchor_btn_prev.add_theme_font_size_override("font_size", 22)
	_enchor_btn_prev.pressed.connect(func():
		if _enchor_page > 1:
			GameState.play_click()
			_trigger_enchor_search(_enchor_last_query, _enchor_page - 1)
	)
	prow.add_child(_enchor_btn_prev)

	_enchor_page_lbl = Label.new()
	_enchor_page_lbl.text = I18n.t("page_indicator") % [_enchor_page, _enchor_total_pages]
	_enchor_page_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_enchor_page_lbl.custom_minimum_size = Vector2(150, 0)
	if ThemeManager.font_display:
		_enchor_page_lbl.add_theme_font_override("font", ThemeManager.font_display)
	_enchor_page_lbl.add_theme_font_size_override("font_size", 22)
	_enchor_page_lbl.add_theme_color_override("font_color", t["accent"])
	prow.add_child(_enchor_page_lbl)

	_enchor_btn_next = Button.new()
	_enchor_btn_next.text = I18n.t("next_btn")
	_enchor_btn_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enchor_btn_next.custom_minimum_size = Vector2(0, 68)
	ThemeManager.style_button(_enchor_btn_next, false)
	_enchor_btn_next.add_theme_font_size_override("font_size", 22)
	_enchor_btn_next.pressed.connect(func():
		if _enchor_page < _enchor_total_pages:
			GameState.play_click()
			_trigger_enchor_search(_enchor_last_query, _enchor_page + 1)
	)
	prow.add_child(_enchor_btn_next)

	_trigger_enchor_search(_enchor_last_query, _enchor_page)

func _trigger_enchor_search(query: String, page: int) -> void:
	_enchor_last_query = query if query.strip_edges() != "" else "*"
	_enchor_page = maxi(1, page)
	if _enchor_status:
		_enchor_status.text = I18n.t("searching_page") % _enchor_page
	if _enchor_scroll:
		_enchor_scroll.scroll_vertical = 0
	var diff_arg = null if _enchor_diff_filter == "" else _enchor_diff_filter
	EnchorClient.search_charts(_enchor_last_query, _enchor_page, diff_arg, PAGE_SIZE)

func _on_enchor_results(results: Array, total_found: int, page: int, error_msg: String) -> void:
	if _current_screen != Screen.ENCHOR or not _enchor_list_vbox or not is_instance_valid(_enchor_list_vbox):
		return
	for c in _enchor_list_vbox.get_children():
		c.queue_free()
	_cover_rects.clear()

	if error_msg != "":
		_enchor_status.text = "⚠ " + error_msg
		return

	_enchor_total_pages = maxi(1, int(ceil(float(total_found) / float(PAGE_SIZE))))
	_enchor_status.text = I18n.t("charts_found") % [total_found, page, _enchor_total_pages]
	if _enchor_page_lbl:
		_enchor_page_lbl.text = I18n.t("page_indicator") % [page, _enchor_total_pages]
	if _enchor_btn_prev:
		_enchor_btn_prev.disabled = (page <= 1)
	if _enchor_btn_next:
		_enchor_btn_next.disabled = (page >= _enchor_total_pages)
	if _enchor_scroll:
		_enchor_scroll.scroll_vertical = 0

	var t := ThemeManager.get_theme_data()
	var diff_badge_defs := [
		{"id": "Easy", "short": "E", "col": Color(0.12, 0.96, 0.48)},
		{"id": "Medium", "short": "M", "col": Color(1.0, 0.84, 0.16)},
		{"id": "Hard", "short": "H", "col": Color(1.0, 0.52, 0.12)},
		{"id": "Expert", "short": "X", "col": Color(1.0, 0.20, 0.34)}
	]

	for item in results:
		var md5 := str(item.get("md5", ""))
		var downloaded := EnchorClient.is_downloaded(md5)

		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["accent"] if downloaded else Color(1, 1, 1, 0.16), 18, 2 if downloaded else 1, 0))
		_enchor_list_vbox.add_child(row)

		var row_vb := VBoxContainer.new()
		row_vb.add_theme_constant_override("separation", 12)
		row.add_child(row_vb)

		var top_hb := HBoxContainer.new()
		top_hb.add_theme_constant_override("separation", 16)
		top_hb.alignment = BoxContainer.ALIGNMENT_CENTER
		row_vb.add_child(top_hb)

		var art_box := TextureRect.new()
		art_box.custom_minimum_size = Vector2(92, 92)
		art_box.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art_box.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		top_hb.add_child(art_box)
		var art_md5 := str(item.get("albumArtMd5", ""))
		if art_md5 != "" and art_md5 != "null":
			if not _cover_rects.has(art_md5):
				_cover_rects[art_md5] = []
			_cover_rects[art_md5].append(art_box)
			EnchorClient.request_cover(art_md5)

		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.add_theme_constant_override("separation", 4)
		top_hb.add_child(vb)

		var title := Label.new()
		title.text = str(item.get("name", "Song"))
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.max_lines_visible = 2
		if ThemeManager.font_display:
			title.add_theme_font_override("font", ThemeManager.font_display)
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", t["text"])
		vb.add_child(title)

		var dur_s := int(item.get("song_length", 180000)) / 1000
		var meta_lbl := Label.new()
		meta_lbl.text = "%s • %d:%02d • %s" % [
			str(item.get("artist", "Artist")),
			dur_s / 60,
			dur_s % 60,
			str(item.get("charter", "Community"))
		]
		meta_lbl.clip_text = true
		if ThemeManager.font_body:
			meta_lbl.add_theme_font_override("font", ThemeManager.font_body)
		meta_lbl.add_theme_font_size_override("font_size", 21)
		meta_lbl.add_theme_color_override("font_color", t["text_dim"])
		vb.add_child(meta_lbl)

		# Available Difficulties Badges (E M H X) from enchor.us notesData
		var avail_raw = item.get("available_diffs", ["Expert"])
		var badge_hb := HBoxContainer.new()
		badge_hb.add_theme_constant_override("separation", 8)
		vb.add_child(badge_hb)
		for bd in diff_badge_defs:
			var has_d: bool = (avail_raw is Array and avail_raw.has(bd["id"]))
			var bl := Label.new()
			bl.text = " " + str(bd["short"]) + " "
			if ThemeManager.font_display:
				bl.add_theme_font_override("font", ThemeManager.font_display)
			bl.add_theme_font_size_override("font_size", 18)
			bl.add_theme_color_override("font_color", bd["col"] if has_d else Color(1, 1, 1, 0.16))
			badge_hb.add_child(bl)

		var item_copy: Dictionary = item
		if downloaded:
			var btn_play := Button.new()
			btn_play.text = I18n.t("play_now")
			btn_play.custom_minimum_size = Vector2(0, 68)
			ThemeManager.style_button(btn_play, true)
			btn_play.pressed.connect(func():
				GameState.play_click()
				GameState.scan_library()
				for s in GameState.library:
					if str(s.get("md5", "")) == md5 or str(s.get("id", "")) == md5:
						GameState.current_song = s
						break
				_show_screen(Screen.DIFFICULTY)
			)
			row_vb.add_child(btn_play)
		else:
			var btn_dl := Button.new()
			btn_dl.text = I18n.t("dl_and_play")
			btn_dl.custom_minimum_size = Vector2(0, 68)
			ThemeManager.style_button(btn_dl, true, t["accent_2"])
			btn_dl.pressed.connect(func():
				GameState.play_click()
				_start_song_download(item_copy)
			)
			row_vb.add_child(btn_dl)

		_make_scroll_pass(row)

func _on_cover_loaded(art_md5: String, tex: Texture2D) -> void:
	if _cover_rects.has(art_md5):
		for rect in _cover_rects[art_md5]:
			if is_instance_valid(rect):
				rect.texture = tex

# ============================================================================
# SCREEN 4: PORTRAIT CUSTOMIZE (VISUALIZERS, HD FRETBOARD & THEMES)
# ============================================================================
func _build_customize_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	_make_top_bar(vbox, I18n.t("customize_title"), Screen.HOME, t)

	var scroll := _make_touch_scroll()
	vbox.add_child(scroll)

	var content_vb := VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.mouse_filter = Control.MOUSE_FILTER_PASS
	content_vb.add_theme_constant_override("separation", 18)
	scroll.add_child(content_vb)

	# 1. Background Music Visualizer Selector (6 distinct 60fps visualizers)
	var viz_card := PanelContainer.new()
	viz_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["accent"], 22, 2, 8))
	content_vb.add_child(viz_card)

	var vvb := VBoxContainer.new()
	vvb.add_theme_constant_override("separation", 14)
	viz_card.add_child(vvb)

	var vlbl := Label.new()
	vlbl.text = I18n.t("viz_header")
	if ThemeManager.font_display:
		vlbl.add_theme_font_override("font", ThemeManager.font_display)
	vlbl.add_theme_font_size_override("font_size", 26)
	vlbl.add_theme_color_override("font_color", t["accent"])
	vvb.add_child(vlbl)

	var vgrid := GridContainer.new()
	vgrid.columns = 2
	vgrid.add_theme_constant_override("h_separation", 10)
	vgrid.add_theme_constant_override("v_separation", 10)
	vvb.add_child(vgrid)

	var cur_viz := str(GameState.settings.get("visualizer", "concert_arena"))
	for vid in ConcertStage.VISUALIZER_IDS:
		var active := (cur_viz == vid)
		var vb_btn := Button.new()
		vb_btn.text = ("✓ " if active else "") + str(ConcertStage.VISUALIZER_NAMES.get(vid, vid))
		vb_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb_btn.custom_minimum_size = Vector2(0, 70)
		ThemeManager.style_button(vb_btn, active, t["accent"])
		vb_btn.add_theme_font_size_override("font_size", 21)
		var target_vid: String = vid
		vb_btn.pressed.connect(func():
			GameState.play_click()
			GameState.settings["visualizer"] = target_vid
			GameState.save_data()
			if _stage:
				_stage.queue_redraw()
			_show_screen(Screen.CUSTOMIZE, false)
		)
		vgrid.add_child(vb_btn)
	_make_scroll_pass(viz_card)

	# 2. Fretboard Surface Card
	var board_card := PanelContainer.new()
	board_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	content_vb.add_child(board_card)

	var bvb := VBoxContainer.new()
	bvb.add_theme_constant_override("separation", 14)
	board_card.add_child(bvb)

	var blbl := Label.new()
	blbl.text = I18n.t("board_header")
	if ThemeManager.font_display:
		blbl.add_theme_font_override("font", ThemeManager.font_display)
	blbl.add_theme_font_size_override("font_size", 26)
	blbl.add_theme_color_override("font_color", t["accent"])
	bvb.add_child(blbl)

	var bhb := HBoxContainer.new()
	bhb.add_theme_constant_override("separation", 10)
	bvb.add_child(bhb)

	var cur_board := str(GameState.settings.get("board_style", "carbon"))
	for b in [
		{"id": "carbon", "name": "CARBON"},
		{"id": "rosewood", "name": "ROSEWOOD"},
		{"id": "obsidian", "name": "OBSIDIAN"}
	]:
		var bid: String = b["id"]
		var active := (cur_board == bid)
		var bb := Button.new()
		bb.text = ("✓ " if active else "") + str(b["name"])
		bb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		bb.custom_minimum_size = Vector2(0, 72)
		ThemeManager.style_button(bb, active, t["accent_2"])
		bb.add_theme_font_size_override("font_size", 24)
		bb.pressed.connect(func():
			GameState.play_click()
			GameState.settings["board_style"] = bid
			GameState.save_data()
			_show_screen(Screen.CUSTOMIZE, false)
		)
		bhb.add_child(bb)
	_make_scroll_pass(board_card)

	# 3. 5 Full-Width Vertical Theme Cards
	var th_hdr := Label.new()
	th_hdr.text = I18n.t("theme_header")
	if ThemeManager.font_display:
		th_hdr.add_theme_font_override("font", ThemeManager.font_display)
	th_hdr.add_theme_font_size_override("font_size", 24)
	th_hdr.add_theme_color_override("font_color", t["text_dim"])
	th_hdr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content_vb.add_child(th_hdr)

	for tid in ThemeManager.THEMES.keys():
		var td: Dictionary = ThemeManager.THEMES[tid]
		var active: bool = (str(tid) == ThemeManager.current_theme_id)
		var tc := PanelContainer.new()
		tc.add_theme_stylebox_override("panel", ThemeManager.make_card_style(td["panel_alt"], td["accent"], 22, 3 if active else 1, 14 if active else 0))
		content_vb.add_child(tc)

		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 12)
		tc.add_child(tv)

		var tname := Label.new()
		tname.text = str(td["name"])
		if ThemeManager.font_display:
			tname.add_theme_font_override("font", ThemeManager.font_display)
		tname.add_theme_font_size_override("font_size", 28)
		tname.add_theme_color_override("font_color", td["accent"])
		tv.add_child(tname)

		var tsub := Label.new()
		tsub.text = str(td["subtitle"])
		if ThemeManager.font_body:
			tsub.add_theme_font_override("font", ThemeManager.font_body)
		tsub.add_theme_font_size_override("font_size", 23)
		tsub.add_theme_color_override("font_color", td["text_dim"])
		tv.add_child(tsub)

		var sw_row := HBoxContainer.new()
		sw_row.add_theme_constant_override("separation", 12)
		tv.add_child(sw_row)
		for sc in td["spotlights"]:
			var sw := ColorRect.new()
			sw.color = sc
			sw.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sw.custom_minimum_size = Vector2(0, 26)
			sw_row.add_child(sw)

		var btn := Button.new()
		btn.text = I18n.t("theme_active") if active else I18n.t("theme_apply")
		btn.custom_minimum_size = Vector2(0, 74)
		ThemeManager.style_button(btn, active, td["accent"])
		var target_id := str(tid)
		btn.pressed.connect(func():
			GameState.play_star_sfx()
			ThemeManager.set_theme(target_id)
		)
		tv.add_child(btn)
		_make_scroll_pass(tc)

# ============================================================================
# SCREEN 5: PORTRAIT SINGLE-COLUMN SMARTPHONE SETTINGS
# ============================================================================
func _build_settings_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	var bar := _make_top_bar(vbox, I18n.t("settings_title"), Screen.HOME, t)

	_fps_lbl = Label.new()
	_fps_lbl.text = "60 FPS"
	if ThemeManager.font_display:
		_fps_lbl.add_theme_font_override("font", ThemeManager.font_display)
	_fps_lbl.add_theme_font_size_override("font_size", 24)
	_fps_lbl.add_theme_color_override("font_color", t["accent_2"])
	bar.add_child(_fps_lbl)

	var scroll := _make_touch_scroll()
	vbox.add_child(scroll)

	var content_vb := VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.mouse_filter = Control.MOUSE_FILTER_PASS
	content_vb.add_theme_constant_override("separation", 20)
	scroll.add_child(content_vb)

	# Card 1: Gameplay & Audio Sliders
	var card1 := PanelContainer.new()
	card1.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	content_vb.add_child(card1)

	var c1_vb := VBoxContainer.new()
	c1_vb.add_theme_constant_override("separation", 18)
	card1.add_child(c1_vb)

	_add_slider_row(c1_vb, I18n.t("note_speed"), 0.7, 1.8, 0.05, float(GameState.settings.get("note_speed", 1.0)), func(v: float):
		GameState.settings["note_speed"] = v
		GameState.save_data()
	)
	_add_slider_row(c1_vb, I18n.t("music_vol"), 0.1, 1.0, 0.05, float(GameState.settings.get("music_volume", 1.0)), func(v: float):
		GameState.settings["music_volume"] = v
		GameState.save_data()
	)
	_add_slider_row(c1_vb, I18n.t("sfx_vol"), 0.0, 1.0, 0.05, float(GameState.settings.get("sfx_volume", 0.85)), func(v: float):
		GameState.settings["sfx_volume"] = v
		GameState.save_data()
	)
	_add_slider_row(c1_vb, I18n.t("light_int"), 0.4, 1.5, 0.05, float(GameState.settings.get("light_intensity", 1.0)), func(v: float):
		GameState.settings["light_intensity"] = v
		GameState.save_data()
	)

	# Flashing Stage Lights ON/OFF Toggle (great for slow songs!)
	var flash_on := bool(GameState.settings.get("stage_lights_flash", true))
	var btn_flash := Button.new()
	btn_flash.text = I18n.t("flash_on") if flash_on else I18n.t("flash_off")
	btn_flash.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_flash, flash_on, t["accent_2"])
	btn_flash.add_theme_font_size_override("font_size", 23)
	btn_flash.pressed.connect(func():
		GameState.play_click()
		GameState.settings["stage_lights_flash"] = not flash_on
		GameState.save_data()
		_show_screen(Screen.SETTINGS, false)
	)
	c1_vb.add_child(btn_flash)

	var hw_lbl := Label.new()
	hw_lbl.text = I18n.t("hit_window")
	if ThemeManager.font_display:
		hw_lbl.add_theme_font_override("font", ThemeManager.font_display)
	hw_lbl.add_theme_font_size_override("font_size", 24)
	hw_lbl.add_theme_color_override("font_color", t["accent"])
	c1_vb.add_child(hw_lbl)

	var hw_row := HBoxContainer.new()
	hw_row.add_theme_constant_override("separation", 12)
	c1_vb.add_child(hw_row)

	var cur_hw := str(GameState.settings.get("hit_window", "normal"))
	for w_opt in ["strict", "normal", "lenient"]:
		var wb := Button.new()
		wb.text = w_opt.to_upper()
		wb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		wb.custom_minimum_size = Vector2(0, 72)
		ThemeManager.style_button(wb, cur_hw == w_opt, t["accent"])
		var w_val: String = w_opt
		wb.pressed.connect(func():
			GameState.play_click()
			GameState.settings["hit_window"] = w_val
			GameState.save_data()
			_show_screen(Screen.SETTINGS, false)
		)
		hw_row.add_child(wb)

	var tog_row := HBoxContainer.new()
	tog_row.add_theme_constant_override("separation", 12)
	c1_vb.add_child(tog_row)

	var hap_on := bool(GameState.settings.get("haptics", true))
	var btn_hap := Button.new()
	btn_hap.text = I18n.t("haptics_on") if hap_on else I18n.t("haptics_off")
	btn_hap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_hap.custom_minimum_size = Vector2(0, 72)
	ThemeManager.style_button(btn_hap, hap_on)
	btn_hap.pressed.connect(func():
		GameState.settings["haptics"] = not hap_on
		GameState.save_data()
		GameState.trigger_haptic(25)
		_show_screen(Screen.SETTINGS, false)
	)
	tog_row.add_child(btn_hap)

	var fps_on := bool(GameState.settings.get("show_fps", true))
	var btn_fps := Button.new()
	btn_fps.text = I18n.t("fps_on") if fps_on else I18n.t("fps_off")
	btn_fps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_fps.custom_minimum_size = Vector2(0, 72)
	ThemeManager.style_button(btn_fps, fps_on)
	btn_fps.pressed.connect(func():
		GameState.settings["show_fps"] = not fps_on
		GameState.save_data()
		_show_screen(Screen.SETTINGS, false)
	)
	tog_row.add_child(btn_fps)
	_make_scroll_pass(card1)

	# Card 2: Audio / Bluetooth Calibration
	var card2 := PanelContainer.new()
	card2.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["accent_2"], 22, 2, 10))
	content_vb.add_child(card2)

	var c2_vb := VBoxContainer.new()
	c2_vb.add_theme_constant_override("separation", 16)
	card2.add_child(c2_vb)

	_cal_lbl = Label.new()
	_cal_lbl.text = I18n.t("audio_offset") % int(round(float(GameState.settings.get("audio_offset_ms", 0.0))))
	if ThemeManager.font_display:
		_cal_lbl.add_theme_font_override("font", ThemeManager.font_display)
	_cal_lbl.add_theme_font_size_override("font_size", 26)
	_cal_lbl.add_theme_color_override("font_color", t["accent_2"])
	c2_vb.add_child(_cal_lbl)

	var cal_slider := HSlider.new()
	cal_slider.min_value = -150.0
	cal_slider.max_value = 150.0
	cal_slider.step = 5.0
	cal_slider.custom_minimum_size = Vector2(0, 52)
	cal_slider.value = float(GameState.settings.get("audio_offset_ms", 0.0))
	cal_slider.value_changed.connect(func(v: float):
		GameState.settings["audio_offset_ms"] = v
		GameState.save_data()
		_cal_lbl.text = I18n.t("audio_offset") % int(round(v))
	)
	c2_vb.add_child(cal_slider)

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 12)
	c2_vb.add_child(step_row)

	for step_ms in [-10.0, 0.0, 10.0]:
		var sb := Button.new()
		sb.text = I18n.t("reset_0") if step_ms == 0.0 else ("%+d ms" % int(step_ms))
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.custom_minimum_size = Vector2(0, 68)
		ThemeManager.style_button(sb, false)
		var delta_ms: float = step_ms
		sb.pressed.connect(func():
			GameState.play_click()
			cal_slider.value = 0.0 if delta_ms == 0.0 else clampf(cal_slider.value + delta_ms, -150.0, 150.0)
		)
		step_row.add_child(sb)

	var btn_toggle_beat := Button.new()
	btn_toggle_beat.text = I18n.t("start_beat")
	btn_toggle_beat.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_toggle_beat, false)
	btn_toggle_beat.pressed.connect(func():
		_cal_test_active = not _cal_test_active
		_cal_beat_timer = 0.0
		_cal_taps.clear()
		btn_toggle_beat.text = I18n.t("stop_beat") if _cal_test_active else I18n.t("start_beat")
	)
	c2_vb.add_child(btn_toggle_beat)

	var btn_tap := Button.new()
	btn_tap.text = I18n.t("tap_beat")
	btn_tap.custom_minimum_size = Vector2(0, 88)
	ThemeManager.style_button(btn_tap, true, t["accent_2"])
	btn_tap.pressed.connect(func():
		if not _cal_test_active:
			_cal_test_active = true
			_cal_beat_timer = 0.0
			btn_toggle_beat.text = I18n.t("stop_beat")
			return
		var signed_err := _cal_beat_timer if _cal_beat_timer <= 0.25 else (_cal_beat_timer - 0.5)
		_cal_taps.append(signed_err * 1000.0)
		if _cal_taps.size() > 6:
			_cal_taps.pop_front()
		var sum := 0.0
		for x in _cal_taps:
			sum += x
		cal_slider.value = clampf(round((sum / float(_cal_taps.size())) / 5.0) * 5.0, -150.0, 150.0)
	)
	c2_vb.add_child(btn_tap)
	_make_scroll_pass(card2)

func _add_slider_row(parent: Control, label_txt: String, min_v: float, max_v: float, step_v: float, init_v: float, cb: Callable) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	parent.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var l := Label.new()
	l.text = label_txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_body:
		l.add_theme_font_override("font", ThemeManager.font_body)
	l.add_theme_font_size_override("font_size", 27)
	hb.add_child(l)
	var vl := Label.new()
	vl.text = "%.2f" % init_v
	if ThemeManager.font_display:
		vl.add_theme_font_override("font", ThemeManager.font_display)
	vl.add_theme_font_size_override("font_size", 25)
	hb.add_child(vl)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = init_v
	sl.custom_minimum_size = Vector2(0, 48)
	sl.value_changed.connect(func(val: float):
		vl.text = "%.2f" % val
		cb.call(val)
	)
	vb.add_child(sl)

# ============================================================================
# DOWNLOAD MODAL & LOCAL FILE IMPORTER
# ============================================================================
func _build_download_modal(t: Dictionary) -> void:
	_dl_modal = PanelContainer.new()
	_dl_modal.visible = false
	_dl_modal.set_anchors_preset(Control.PRESET_CENTER)
	_dl_modal.offset_left = -310
	_dl_modal.offset_top = -170
	_dl_modal.offset_right = 310
	_dl_modal.offset_bottom = 170
	_dl_modal.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.03, 0.03, 0.09, 0.98), t["accent"], 26, 3, 24))
	add_child(_dl_modal)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_dl_modal.add_child(vb)

	_dl_label = Label.new()
	_dl_label.text = I18n.t("downloading_pkg")
	_dl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dl_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		_dl_label.add_theme_font_override("font", ThemeManager.font_body)
	_dl_label.add_theme_font_size_override("font_size", 28)
	vb.add_child(_dl_label)

	_dl_bar = ProgressBar.new()
	_dl_bar.custom_minimum_size = Vector2(0, 38)
	vb.add_child(_dl_bar)

	var btn_cancel := Button.new()
	btn_cancel.text = I18n.t("cancel")
	btn_cancel.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_cancel, false)
	btn_cancel.pressed.connect(func():
		EnchorClient.cancel_download()
		_dl_modal.visible = false
	)
	vb.add_child(btn_cancel)

func _start_song_download(meta: Dictionary) -> void:
	_dl_modal.visible = true
	_dl_bar.value = 0.0
	_dl_label.text = I18n.t("downloading_name") % str(meta.get("name", "Chart"))
	EnchorClient.download_chart(meta)

func _on_dl_progress(_md5: String, dl_bytes: int, total_bytes: int) -> void:
	if not _dl_modal or not _dl_modal.visible:
		return
	var mb := float(dl_bytes) / 1048576.0
	if total_bytes > 0:
		var tmb := float(total_bytes) / 1048576.0
		_dl_bar.value = (float(dl_bytes) / float(total_bytes)) * 100.0
		_dl_label.text = I18n.t("downloading_mb") % [mb, tmb]
	else:
		_dl_bar.value = fmod(mb * 20.0, 95.0)
		_dl_label.text = I18n.t("downloading_mb_only") % mb

func _on_dl_completed(md5: String, _sng_path: String, error_msg: String) -> void:
	_dl_modal.visible = false
	if error_msg != "":
		if _enchor_status and is_instance_valid(_enchor_status):
			_enchor_status.text = "⚠ " + error_msg
		return
	GameState.play_star_sfx()
	GameState.scan_library()
	for s in GameState.library:
		if str(s.get("md5", "")) == md5 or str(s.get("id", "")) == md5:
			GameState.current_song = s
			break
	_show_screen(Screen.DIFFICULTY)

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
		elif path.to_lower().ends_with(".zip"):
			SngParser.import_zip_to_folder(path)
		if _current_screen == Screen.SONGS:
			_populate_song_cards()
	)
	add_child(_file_dialog)

# ============================================================================
# SCREEN 6: ABOUT, CREDITS, COPYRIGHT & LEGAL NOTICE
# ============================================================================
func _build_about_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	_make_top_bar(vbox, I18n.t("about_title"), Screen.HOME, t)

	var scroll := _make_touch_scroll()
	vbox.add_child(scroll)

	var content_vb := VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.mouse_filter = Control.MOUSE_FILTER_PASS
	content_vb.add_theme_constant_override("separation", 18)
	scroll.add_child(content_vb)

	# 1. Creator & Copyright Card + Direct GitHub Links
	var dev_vb := _add_about_card(content_vb, I18n.t("about_dev_hdr"), I18n.t("about_dev_body"), t["accent"], t)

	var btn_gh := Button.new()
	btn_gh.text = I18n.t("about_open_github")
	btn_gh.custom_minimum_size = Vector2(0, 72)
	ThemeManager.style_button(btn_gh, true, t["accent"])
	btn_gh.add_theme_font_size_override("font_size", 23)
	btn_gh.pressed.connect(func():
		GameState.play_click()
		OS.shell_open("https://github.com/ipungsx")
	)
	dev_vb.add_child(btn_gh)

	var btn_repo := Button.new()
	btn_repo.text = I18n.t("about_open_repo")
	btn_repo.custom_minimum_size = Vector2(0, 70)
	ThemeManager.style_button(btn_repo, false, t["accent_2"])
	btn_repo.add_theme_font_size_override("font_size", 22)
	btn_repo.pressed.connect(func():
		GameState.play_click()
		OS.shell_open("https://github.com/ipungsx/DroidHerov2")
	)
	dev_vb.add_child(btn_repo)
	_make_scroll_pass(dev_vb.get_parent())

	# 2. Credits Card
	var cred_vb := _add_about_card(content_vb, I18n.t("about_credits_hdr"), I18n.t("about_credits_body"), t["accent_2"], t)
	_make_scroll_pass(cred_vb.get_parent())

	# 3. Third-Party & Open-Source Licenses Card
	var oss_vb := _add_about_card(content_vb, I18n.t("about_oss_hdr"), I18n.t("about_oss_body"), t["accent_3"], t)
	_make_scroll_pass(oss_vb.get_parent())

	# 4. Legal Notice & Disclaimer Card
	var leg_vb := _add_about_card(content_vb, I18n.t("about_legal_hdr"), I18n.t("about_legal_body"), t["border"], t)
	_make_scroll_pass(leg_vb.get_parent())

func _add_about_card(parent: VBoxContainer, hdr_txt: String, body_txt: String, col: Color, t: Dictionary) -> VBoxContainer:
	var card := PanelContainer.new()
	card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], col, 22, 2, 10))
	parent.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	var hdr := Label.new()
	hdr.text = hdr_txt
	if ThemeManager.font_display:
		hdr.add_theme_font_override("font", ThemeManager.font_display)
	hdr.add_theme_font_size_override("font_size", 25)
	hdr.add_theme_color_override("font_color", col)
	vb.add_child(hdr)

	var body := Label.new()
	body.text = body_txt
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		body.add_theme_font_override("font", ThemeManager.font_body)
	body.add_theme_font_size_override("font_size", 23)
	body.add_theme_color_override("font_color", t["text"])
	vb.add_child(body)
	return vb

# ============================================================================
# SCREEN 7: INTRO SPLASH PAGE (BY IPUNGSX / GITHUB.COM/IPUNGSX)
# ============================================================================
func _build_intro_screen(parent: MarginContainer, t: Dictionary) -> void:
	var root := Control.new()
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	root.size_flags_vertical = Control.SIZE_EXPAND_FILL
	parent.add_child(root)

	var center_vb := VBoxContainer.new()
	center_vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	center_vb.add_theme_constant_override("separation", 24)
	center_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center_vb)

	# Spinning Vinyl Emblem
	var disc_wrap := CenterContainer.new()
	disc_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center_vb.add_child(disc_wrap)

	var disc := VinylDisc.new()
	disc.accent = t["accent"]
	disc.accent2 = t["accent_2"]
	disc.spinning = true
	disc.custom_minimum_size = Vector2(210, 210)
	disc_wrap.add_child(disc)

	# Main Title
	var title := Label.new()
	title.text = "DROIDHERO V2"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_display:
		title.add_theme_font_override("font", ThemeManager.font_display)
	title.add_theme_font_size_override("font_size", 64)
	title.add_theme_color_override("font_color", t["accent"])
	center_vb.add_child(title)

	# Creator Credit Card: By ipungsx + github.com/ipungsx
	var brand_card := PanelContainer.new()
	brand_card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	brand_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["accent_2"], 24, 2, 16))
	center_vb.add_child(brand_card)

	var bvb := VBoxContainer.new()
	bvb.alignment = BoxContainer.ALIGNMENT_CENTER
	bvb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bvb.add_theme_constant_override("separation", 10)
	brand_card.add_child(bvb)

	var by_lbl := Label.new()
	by_lbl.text = I18n.t("intro_by")
	by_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	by_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_display:
		by_lbl.add_theme_font_override("font", ThemeManager.font_display)
	by_lbl.add_theme_font_size_override("font_size", 38)
	by_lbl.add_theme_color_override("font_color", Color.WHITE)
	bvb.add_child(by_lbl)

	var url_lbl := Label.new()
	url_lbl.text = I18n.t("intro_url")
	url_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	url_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_display:
		url_lbl.add_theme_font_override("font", ThemeManager.font_display)
	url_lbl.add_theme_font_size_override("font_size", 28)
	url_lbl.add_theme_color_override("font_color", t["accent_2"])
	bvb.add_child(url_lbl)

	var copy_lbl := Label.new()
	copy_lbl.text = "Copyright © 2026 ipungsx"
	copy_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	copy_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_body:
		copy_lbl.add_theme_font_override("font", ThemeManager.font_body)
	copy_lbl.add_theme_font_size_override("font_size", 22)
	copy_lbl.add_theme_color_override("font_color", t["text_dim"])
	bvb.add_child(copy_lbl)

	var tap_lbl := Label.new()
	tap_lbl.text = I18n.t("intro_tap")
	tap_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tap_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_body:
		tap_lbl.add_theme_font_override("font", ThemeManager.font_body)
	tap_lbl.add_theme_font_size_override("font_size", 22)
	tap_lbl.add_theme_color_override("font_color", Color(1, 1, 1, 0.55))
	center_vb.add_child(tap_lbl)

	# Full-screen invisible button so tapping anywhere skips intro immediately
	var skip_btn := Button.new()
	skip_btn.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	skip_btn.flat = true
	var empty_sb := StyleBoxEmpty.new()
	skip_btn.add_theme_stylebox_override("normal", empty_sb)
	skip_btn.add_theme_stylebox_override("hover", empty_sb)
	skip_btn.add_theme_stylebox_override("pressed", empty_sb)
	skip_btn.add_theme_stylebox_override("focus", empty_sb)
	skip_btn.pressed.connect(func():
		if _current_screen == Screen.INTRO:
			GameState.play_click()
			_show_screen(Screen.HOME, true)
	)
	root.add_child(skip_btn)

	# Fade-in animation + automatic transition to Home after 2.6 seconds
	root.modulate.a = 0.0
	var tw := create_tween()
	tw.tween_property(root, "modulate:a", 1.0, 0.45).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

	var timer := get_tree().create_timer(2.6)
	timer.timeout.connect(func():
		if is_instance_valid(self) and _current_screen == Screen.INTRO:
			_show_screen(Screen.HOME, true)
	)

