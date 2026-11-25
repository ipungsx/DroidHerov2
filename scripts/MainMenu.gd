extends Control

# Native Portrait HD Smartphone Game Menu for DroidHeroV2 (720x1600):
# Full-screen single-column mobile game navigation:
# - SCREEN 0: HOME (Hero logo, stats pill, active song vinyl card, 4 huge full-width buttons)
# - SCREEN 1: SONG SELECT (Big vertical song cards, sort/import/preview controls, sticky launch bar)
# - SCREEN 2: DIFFICULTY (2x2 huge difficulty cards, speed & no-fail pills, giant PLAY button)
# - SCREEN 3: ENCHOR.US STORE (Full-width search bar, large mobile chart cards, pagination)
# - SCREEN 4: CUSTOMIZE (3 HD Fretboard surface buttons + 5 vertical Theme cards)
# - SCREEN 5: SETTINGS (Single-column scrollable sliders, hit window, haptics, audio calibration)

enum Screen {
	HOME = 0,
	SONGS = 1,
	DIFFICULTY = 2,
	ENCHOR = 3,
	CUSTOMIZE = 4,
	SETTINGS = 5
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

var _stage: ConcertStage
var _screen_holder: Control
var _current_screen: int = Screen.HOME
var _sort_mode: int = 0

# Song Select refs
var _lib_list_vbox: VBoxContainer
var _sel_banner_lbl: Label
var _vinyl: VinylDisc
var _preview_player: AudioStreamPlayer
var _preview_active: bool = false
var _btn_preview: Button

# Enchor.us refs
var _search_input: LineEdit
var _enchor_status: Label
var _enchor_list_vbox: VBoxContainer
var _enchor_page: int = 1
var _enchor_last_query: String = "*"
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
		_btn_preview.text = "🔊 PREVIEW"

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
		_btn_preview.text = "■ STOP"

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
	root_vb.add_theme_constant_override("separation", 24)
	parent.add_child(root_vb)

	# 1. Centered Hero Logo Header
	var hero_vb := VBoxContainer.new()
	hero_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	hero_vb.add_theme_constant_override("separation", 6)
	root_vb.add_child(hero_vb)

	var logo := Label.new()
	logo.text = "DROIDHERO"
	logo.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		logo.add_theme_font_override("font", ThemeManager.font_display)
	logo.add_theme_font_size_override("font_size", 74)
	logo.add_theme_color_override("font_color", t["accent"])
	hero_vb.add_child(logo)

	var sub := Label.new()
	sub.text = "V2.3 HD  •  MOBILE GUITAR RHYTHM"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		sub.add_theme_font_override("font", ThemeManager.font_display)
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", t["accent_2"])
	hero_vb.add_child(sub)

	# 2. Compact Stats Pill
	var stats_pill := PanelContainer.new()
	stats_pill.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], Color(1, 1, 1, 0.22), 20, 1, 0))
	root_vb.add_child(stats_pill)

	var stats_lbl := Label.new()
	stats_lbl.text = "🎵 %d SONGS INSTALLED   •   ★ %d STARS" % [GameState.library.size(), GameState.get_total_stars()]
	stats_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_body:
		stats_lbl.add_theme_font_override("font", ThemeManager.font_body)
	stats_lbl.add_theme_font_size_override("font_size", 26)
	stats_lbl.add_theme_color_override("font_color", t["text"])
	stats_pill.add_child(stats_lbl)

	# 3. Active Song Showcase Card with Vinyl Disc
	var now_card := PanelContainer.new()
	now_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["border"], 26, 2, 16))
	root_vb.add_child(now_card)

	var now_vb := VBoxContainer.new()
	now_vb.add_theme_constant_override("separation", 18)
	now_card.add_child(now_vb)

	var now_hb := HBoxContainer.new()
	now_hb.add_theme_constant_override("separation", 22)
	now_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	now_vb.add_child(now_hb)

	var home_vinyl := VinylDisc.new()
	home_vinyl.accent = t["accent"]
	home_vinyl.accent2 = t["accent_2"]
	home_vinyl.custom_minimum_size = Vector2(150, 150)
	now_hb.add_child(home_vinyl)

	var info_vb := VBoxContainer.new()
	info_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	info_vb.add_theme_constant_override("separation", 6)
	now_hb.add_child(info_vb)

	var tag_lbl := Label.new()
	tag_lbl.text = "READY TO PLAY"
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
	s_name.add_theme_font_size_override("font_size", 28)
	s_name.add_theme_color_override("font_color", t["text"])
	info_vb.add_child(s_name)

	var s_art := Label.new()
	s_art.text = str(GameState.current_song.get("artist", "DroidHero Studio")) + " • " + GameState.current_difficulty.to_upper()
	if ThemeManager.font_body:
		s_art.add_theme_font_override("font", ThemeManager.font_body)
	s_art.add_theme_font_size_override("font_size", 24)
	s_art.add_theme_color_override("font_color", t["text_dim"])
	info_vb.add_child(s_art)

	var btn_quick := Button.new()
	btn_quick.text = "⚡  QUICK PLAY NOW  ▶"
	btn_quick.custom_minimum_size = Vector2(0, 88)
	ThemeManager.style_button(btn_quick, true, t["accent_2"])
	btn_quick.add_theme_font_size_override("font_size", 30)
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
	var btn_play := _make_mobile_menu_btn("▶   PLAY SONGS", "Local song library & practice mode", true, t["accent"], 132)
	btn_play.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.SONGS)
	)
	root_vb.add_child(btn_play)

	var btn_store := _make_mobile_menu_btn("☁   DOWNLOAD SONGS", "Browse 85,000+ free charts on enchor.us", false, t["accent_2"], 118)
	btn_store.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.ENCHOR)
	)
	root_vb.add_child(btn_store)

	var btn_cust := _make_mobile_menu_btn("🎨   THEMES & HD GUITAR", "5 arena themes & 3 HD fretboard decks", false, t["accent_3"], 118)
	btn_cust.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.CUSTOMIZE)
	)
	root_vb.add_child(btn_cust)

	var btn_set := _make_mobile_menu_btn("⚙   SETTINGS", "Note speed, hit window & calibration", false, t["border"], 118)
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
	tl.add_theme_font_size_override("font_size", 36 if primary else 30)
	tl.add_theme_color_override("font_color", Color.WHITE if primary else t["text"])
	vb.add_child(tl)

	var sl := Label.new()
	sl.text = sub_txt
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_body:
		sl.add_theme_font_override("font", ThemeManager.font_body)
	sl.add_theme_font_size_override("font_size", 23)
	sl.add_theme_color_override("font_color", t["text_dim"])
	vb.add_child(sl)
	return btn

# ============================================================================
# SCREEN 1: PORTRAIT SONG SELECT
# ============================================================================
func _build_songs_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	_make_top_bar(vbox, "SELECT SONG", Screen.HOME, t)

	# Action Pill Row (Sort + Import + Preview)
	var tools_hb := HBoxContainer.new()
	tools_hb.add_theme_constant_override("separation", 12)
	vbox.add_child(tools_hb)

	var sort_names := ["SORT: TITLE", "SORT: ARTIST", "SORT: ★"]
	var btn_sort := Button.new()
	btn_sort.text = sort_names[_sort_mode]
	btn_sort.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_sort.custom_minimum_size = Vector2(0, 72)
	ThemeManager.style_button(btn_sort, false)
	btn_sort.add_theme_font_size_override("font_size", 24)
	btn_sort.pressed.connect(func():
		GameState.play_click()
		_sort_mode = (_sort_mode + 1) % 3
		btn_sort.text = sort_names[_sort_mode]
		_populate_song_cards()
	)
	tools_hb.add_child(btn_sort)

	_btn_preview = Button.new()
	_btn_preview.text = "🔊 PREVIEW"
	_btn_preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_btn_preview.custom_minimum_size = Vector2(0, 72)
	ThemeManager.style_button(_btn_preview, false)
	_btn_preview.add_theme_font_size_override("font_size", 24)
	_btn_preview.pressed.connect(func():
		GameState.play_click()
		_toggle_song_preview()
	)
	tools_hb.add_child(_btn_preview)

	var btn_imp := Button.new()
	btn_imp.text = "+ IMPORT"
	btn_imp.custom_minimum_size = Vector2(180, 72)
	ThemeManager.style_button(btn_imp, false, t["accent_2"])
	btn_imp.add_theme_font_size_override("font_size", 24)
	btn_imp.pressed.connect(func():
		GameState.play_click()
		_file_dialog.popup_centered_ratio(0.92)
	)
	tools_hb.add_child(btn_imp)

	# Scrollable Vertical Song List
	var list_panel := PanelContainer.new()
	list_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	vbox.add_child(list_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_child(scroll)

	_lib_list_vbox = VBoxContainer.new()
	_lib_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_list_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(_lib_list_vbox)

	# Sticky Bottom Selected Song & Next Step Card
	var bot_card := PanelContainer.new()
	bot_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["accent_2"], 22, 2, 12))
	vbox.add_child(bot_card)

	var bot_vb := VBoxContainer.new()
	bot_vb.add_theme_constant_override("separation", 14)
	bot_card.add_child(bot_vb)

	var sel_hb := HBoxContainer.new()
	sel_hb.add_theme_constant_override("separation", 16)
	sel_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	bot_vb.add_child(sel_hb)

	_vinyl = VinylDisc.new()
	_vinyl.accent = t["accent"]
	_vinyl.accent2 = t["accent_2"]
	_vinyl.custom_minimum_size = Vector2(92, 92)
	sel_hb.add_child(_vinyl)

	_sel_banner_lbl = Label.new()
	_sel_banner_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sel_banner_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		_sel_banner_lbl.add_theme_font_override("font", ThemeManager.font_body)
	_sel_banner_lbl.add_theme_font_size_override("font_size", 25)
	_sel_banner_lbl.add_theme_color_override("font_color", t["text"])
	sel_hb.add_child(_sel_banner_lbl)

	var btn_next := Button.new()
	btn_next.text = "SELECT DIFFICULTY  ▶"
	btn_next.custom_minimum_size = Vector2(0, 92)
	ThemeManager.style_button(btn_next, true, t["accent"])
	btn_next.add_theme_font_size_override("font_size", 32)
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

	for song in songs:
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
		st_lbl.text = ("★".repeat(best_st) + "☆".repeat(5 - best_st)) if best_st > 0 else "NEW"
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

	_make_top_bar(vbox, "DIFFICULTY", Screen.SONGS, t)

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
		{"id": "Easy", "title": "EASY", "desc": "Casual • 3-4 Lanes", "col": Color(0.12, 0.96, 0.48)},
		{"id": "Medium", "title": "MEDIUM", "desc": "Standard • 4 Lanes", "col": Color(1.0, 0.84, 0.16)},
		{"id": "Hard", "title": "HARD", "desc": "Fast • 5 Lanes", "col": Color(1.0, 0.52, 0.12)},
		{"id": "Expert", "title": "EXPERT", "desc": "Pro • Full Chart", "col": Color(1.0, 0.20, 0.34)}
	]

	for dd in diff_defs:
		var d_id: String = dd["id"]
		var is_sel := (GameState.current_difficulty == d_id)
		var dcol: Color = dd["col"]

		var dbtn := Button.new()
		dbtn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		dbtn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		ThemeManager.style_button(dbtn, is_sel, dcol)

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
		dlbl.add_theme_color_override("font_color", Color.WHITE if is_sel else dcol)
		cv.add_child(dlbl)

		var dsub := Label.new()
		dsub.text = dd["desc"]
		dsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_body:
			dsub.add_theme_font_override("font", ThemeManager.font_body)
		dsub.add_theme_font_size_override("font_size", 24)
		dsub.add_theme_color_override("font_color", t["text_dim"])
		cv.add_child(dsub)

		var rec := GameState.get_best(str(GameState.current_song.get("id", "")), d_id)
		var st_cnt := int(rec.get("stars", 0))
		var st_lbl := Label.new()
		st_lbl.text = ("★".repeat(st_cnt) + "☆".repeat(5 - st_cnt)) if st_cnt > 0 else "☆☆☆☆☆"
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_lbl.add_theme_font_size_override("font_size", 34)
		st_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22) if st_cnt > 0 else Color(1, 1, 1, 0.22))
		cv.add_child(st_lbl)

		var best_txt := Label.new()
		best_txt.text = ("%d PTS" % int(rec.get("score", 0))) if not rec.is_empty() else "Not played yet"
		best_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_body:
			best_txt.add_theme_font_override("font", ThemeManager.font_body)
		best_txt.add_theme_font_size_override("font_size", 24)
		best_txt.add_theme_color_override("font_color", t["text"])
		cv.add_child(best_txt)

		dbtn.pressed.connect(func():
			GameState.play_click()
			GameState.current_difficulty = d_id
			_show_screen(Screen.DIFFICULTY, false)
		)
		grid.add_child(dbtn)

	# Speed & No-Fail Row
	var opt_hb := HBoxContainer.new()
	opt_hb.add_theme_constant_override("separation", 14)
	vbox.add_child(opt_hb)

	var speeds := [1.0, 0.75, 0.50, 1.25]
	var speed_labels := ["SPEED: 100%", "PRACTICE: 75%", "LEARN: 50%", "HYPER: 125%"]
	var cur_spd_idx := speeds.find(GameState.practice_speed)
	if cur_spd_idx < 0:
		cur_spd_idx = 0

	var btn_spd := Button.new()
	btn_spd.text = speed_labels[cur_spd_idx]
	btn_spd.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_spd.custom_minimum_size = Vector2(0, 82)
	ThemeManager.style_button(btn_spd, false)
	btn_spd.pressed.connect(func():
		GameState.play_click()
		var nxt := (speeds.find(GameState.practice_speed) + 1) % speeds.size()
		GameState.practice_speed = speeds[nxt]
		btn_spd.text = speed_labels[nxt]
	)
	opt_hb.add_child(btn_spd)

	var nf_on := bool(GameState.settings.get("no_fail", false))
	var btn_nf := Button.new()
	btn_nf.text = "NO-FAIL: ON ✓" if nf_on else "NO-FAIL: OFF"
	btn_nf.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_nf.custom_minimum_size = Vector2(0, 82)
	ThemeManager.style_button(btn_nf, nf_on, Color(0.15, 0.95, 0.55))
	btn_nf.pressed.connect(func():
		GameState.play_click()
		GameState.settings["no_fail"] = not nf_on
		GameState.save_data()
		_show_screen(Screen.DIFFICULTY, false)
	)
	opt_hb.add_child(btn_nf)

	# Giant Bottom Launch Button
	var btn_go := Button.new()
	btn_go.text = "★   ROCK ON STAGE!   ★"
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
# SCREEN 3: PORTRAIT ENCHOR.US MOBILE STORE
# ============================================================================
func _build_enchor_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	parent.add_child(vbox)

	_make_top_bar(vbox, "ENCHOR.US STORE", Screen.HOME, t)

	# Full-width Search Box + Buttons
	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Search song title, artist, or charter..."
	_search_input.custom_minimum_size = Vector2(0, 78)
	_search_input.add_theme_stylebox_override("normal", ThemeManager.make_card_style(Color(0.03, 0.03, 0.08, 0.96), t["border"], 18, 2, 0))
	if ThemeManager.font_body:
		_search_input.add_theme_font_override("font", ThemeManager.font_body)
	_search_input.add_theme_font_size_override("font_size", 28)
	_search_input.text_submitted.connect(func(q: String): _trigger_enchor_search(q, 1))
	vbox.add_child(_search_input)

	var s_hb := HBoxContainer.new()
	s_hb.add_theme_constant_override("separation", 12)
	vbox.add_child(s_hb)

	var btn_search := Button.new()
	btn_search.text = "🔍  SEARCH ENCHOR.US"
	btn_search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_search.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_search, true)
	btn_search.pressed.connect(func():
		GameState.play_click()
		_trigger_enchor_search(_search_input.text, 1)
	)
	s_hb.add_child(btn_search)

	var btn_top := Button.new()
	btn_top.text = "TOP / LATEST"
	btn_top.custom_minimum_size = Vector2(185, 74)
	ThemeManager.style_button(btn_top, false)
	btn_top.pressed.connect(func():
		GameState.play_click()
		_search_input.text = ""
		_trigger_enchor_search("*", 1)
	)
	s_hb.add_child(btn_top)

	_enchor_status = Label.new()
	_enchor_status.text = "Loading charts from enchor.us..."
	if ThemeManager.font_body:
		_enchor_status.add_theme_font_override("font", ThemeManager.font_body)
	_enchor_status.add_theme_font_size_override("font_size", 24)
	_enchor_status.add_theme_color_override("font_color", t["text_dim"])
	vbox.add_child(_enchor_status)

	var list_card := PanelContainer.new()
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	vbox.add_child(list_card)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_card.add_child(scroll)

	_enchor_list_vbox = VBoxContainer.new()
	_enchor_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enchor_list_vbox.add_theme_constant_override("separation", 14)
	scroll.add_child(_enchor_list_vbox)

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 14)
	vbox.add_child(prow)

	var btn_prev := Button.new()
	btn_prev.text = "◀  PREVIOUS"
	btn_prev.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_prev.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_prev, false)
	btn_prev.pressed.connect(func():
		if _enchor_page > 1:
			_trigger_enchor_search(_enchor_last_query, _enchor_page - 1)
	)
	prow.add_child(btn_prev)

	var btn_next := Button.new()
	btn_next.text = "NEXT  ▶"
	btn_next.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_next.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_next, false)
	btn_next.pressed.connect(func():
		_trigger_enchor_search(_enchor_last_query, _enchor_page + 1)
	)
	prow.add_child(btn_next)

	_trigger_enchor_search(_enchor_last_query, _enchor_page)

func _trigger_enchor_search(query: String, page: int) -> void:
	_enchor_last_query = query if query.strip_edges() != "" else "*"
	_enchor_page = maxi(1, page)
	if _enchor_status:
		_enchor_status.text = "Searching... (Page " + str(_enchor_page) + ")"
	EnchorClient.search_charts(_enchor_last_query, _enchor_page)

func _on_enchor_results(results: Array, total_found: int, page: int, error_msg: String) -> void:
	if _current_screen != Screen.ENCHOR or not _enchor_list_vbox or not is_instance_valid(_enchor_list_vbox):
		return
	for c in _enchor_list_vbox.get_children():
		c.queue_free()
	_cover_rects.clear()

	if error_msg != "":
		_enchor_status.text = "⚠ " + error_msg
		return

	_enchor_status.text = "%d charts found  •  Page %d" % [total_found, page]
	var t := ThemeManager.get_theme_data()

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
		meta_lbl.text = "%s • %d:%02d • Charter: %s" % [
			str(item.get("artist", "Artist")),
			dur_s / 60,
			dur_s % 60,
			str(item.get("charter", "Community"))
		]
		meta_lbl.clip_text = true
		if ThemeManager.font_body:
			meta_lbl.add_theme_font_override("font", ThemeManager.font_body)
		meta_lbl.add_theme_font_size_override("font_size", 22)
		meta_lbl.add_theme_color_override("font_color", t["text_dim"])
		vb.add_child(meta_lbl)

		var item_copy: Dictionary = item
		if downloaded:
			var btn_play := Button.new()
			btn_play.text = "▶  PLAY NOW"
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
			btn_dl.text = "⬇  DOWNLOAD & PLAY"
			btn_dl.custom_minimum_size = Vector2(0, 68)
			ThemeManager.style_button(btn_dl, true, t["accent_2"])
			btn_dl.pressed.connect(func():
				GameState.play_click()
				_start_song_download(item_copy)
			)
			row_vb.add_child(btn_dl)

func _on_cover_loaded(art_md5: String, tex: Texture2D) -> void:
	if _cover_rects.has(art_md5):
		for rect in _cover_rects[art_md5]:
			if is_instance_valid(rect):
				rect.texture = tex

# ============================================================================
# SCREEN 4: PORTRAIT CUSTOMIZE (THEMES & HD FRETBOARD)
# ============================================================================
func _build_customize_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	_make_top_bar(vbox, "THEMES & HD DECKS", Screen.HOME, t)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content_vb := VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation", 18)
	scroll.add_child(content_vb)

	# Fretboard Surface Card
	var board_card := PanelContainer.new()
	board_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	content_vb.add_child(board_card)

	var bvb := VBoxContainer.new()
	bvb.add_theme_constant_override("separation", 14)
	board_card.add_child(bvb)

	var blbl := Label.new()
	blbl.text = "HD FRETBOARD SURFACE"
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

	# 5 Full-Width Vertical Theme Cards
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
		btn.text = "✓  ACTIVE THEME" if active else "APPLY THEME"
		btn.custom_minimum_size = Vector2(0, 74)
		ThemeManager.style_button(btn, active, td["accent"])
		var target_id := str(tid)
		btn.pressed.connect(func():
			GameState.play_star_sfx()
			ThemeManager.set_theme(target_id)
		)
		tv.add_child(btn)

# ============================================================================
# SCREEN 5: PORTRAIT SINGLE-COLUMN SMARTPHONE SETTINGS
# ============================================================================
func _build_settings_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	var bar := _make_top_bar(vbox, "SETTINGS", Screen.HOME, t)

	_fps_lbl = Label.new()
	_fps_lbl.text = "60 FPS"
	if ThemeManager.font_display:
		_fps_lbl.add_theme_font_override("font", ThemeManager.font_display)
	_fps_lbl.add_theme_font_size_override("font_size", 24)
	_fps_lbl.add_theme_color_override("font_color", t["accent_2"])
	bar.add_child(_fps_lbl)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var content_vb := VBoxContainer.new()
	content_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vb.add_theme_constant_override("separation", 20)
	scroll.add_child(content_vb)

	# Card 1: Gameplay & Audio Sliders
	var card1 := PanelContainer.new()
	card1.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	content_vb.add_child(card1)

	var c1_vb := VBoxContainer.new()
	c1_vb.add_theme_constant_override("separation", 18)
	card1.add_child(c1_vb)

	_add_slider_row(c1_vb, "Highway Note Speed", 0.7, 1.8, 0.05, float(GameState.settings.get("note_speed", 1.0)), func(v: float):
		GameState.settings["note_speed"] = v
		GameState.save_data()
	)
	_add_slider_row(c1_vb, "Music Volume", 0.1, 1.0, 0.05, float(GameState.settings.get("music_volume", 1.0)), func(v: float):
		GameState.settings["music_volume"] = v
		GameState.save_data()
	)
	_add_slider_row(c1_vb, "SFX Volume", 0.0, 1.0, 0.05, float(GameState.settings.get("sfx_volume", 0.85)), func(v: float):
		GameState.settings["sfx_volume"] = v
		GameState.save_data()
	)
	_add_slider_row(c1_vb, "Stage Light Intensity", 0.4, 1.5, 0.05, float(GameState.settings.get("light_intensity", 1.0)), func(v: float):
		GameState.settings["light_intensity"] = v
		GameState.save_data()
	)

	var hw_lbl := Label.new()
	hw_lbl.text = "HIT WINDOW TIMING"
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
	btn_hap.text = "HAPTICS: ON ✓" if hap_on else "HAPTICS: OFF"
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
	btn_fps.text = "FPS HUD: ON ✓" if fps_on else "FPS HUD: OFF"
	btn_fps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_fps.custom_minimum_size = Vector2(0, 72)
	ThemeManager.style_button(btn_fps, fps_on)
	btn_fps.pressed.connect(func():
		GameState.settings["show_fps"] = not fps_on
		GameState.save_data()
		_show_screen(Screen.SETTINGS, false)
	)
	tog_row.add_child(btn_fps)

	# Card 2: Audio / Bluetooth Calibration
	var card2 := PanelContainer.new()
	card2.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["accent_2"], 22, 2, 10))
	content_vb.add_child(card2)

	var c2_vb := VBoxContainer.new()
	c2_vb.add_theme_constant_override("separation", 16)
	card2.add_child(c2_vb)

	_cal_lbl = Label.new()
	_cal_lbl.text = "AUDIO OFFSET: %d ms" % int(round(float(GameState.settings.get("audio_offset_ms", 0.0))))
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
		_cal_lbl.text = "AUDIO OFFSET: %d ms" % int(round(v))
	)
	c2_vb.add_child(cal_slider)

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 12)
	c2_vb.add_child(step_row)

	for step_ms in [-10.0, 0.0, 10.0]:
		var sb := Button.new()
		sb.text = "RESET 0" if step_ms == 0.0 else ("%+d ms" % int(step_ms))
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
	btn_toggle_beat.text = "▶  START BEAT SOUND TEST"
	btn_toggle_beat.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_toggle_beat, false)
	btn_toggle_beat.pressed.connect(func():
		_cal_test_active = not _cal_test_active
		_cal_beat_timer = 0.0
		_cal_taps.clear()
		btn_toggle_beat.text = "■  STOP BEAT TEST" if _cal_test_active else "▶  START BEAT SOUND TEST"
	)
	c2_vb.add_child(btn_toggle_beat)

	var btn_tap := Button.new()
	btn_tap.text = "🥁  TAP ON BEAT (AUTO)"
	btn_tap.custom_minimum_size = Vector2(0, 88)
	ThemeManager.style_button(btn_tap, true, t["accent_2"])
	btn_tap.pressed.connect(func():
		if not _cal_test_active:
			_cal_test_active = true
			_cal_beat_timer = 0.0
			btn_toggle_beat.text = "■  STOP BEAT TEST"
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
	_dl_label.text = "Downloading .sng package..."
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
	btn_cancel.text = "CANCEL"
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
	_dl_label.text = "Downloading: " + str(meta.get("name", "Chart")) + "..."
	EnchorClient.download_chart(meta)

func _on_dl_progress(_md5: String, dl_bytes: int, total_bytes: int) -> void:
	if not _dl_modal or not _dl_modal.visible:
		return
	var mb := float(dl_bytes) / 1048576.0
	if total_bytes > 0:
		var tmb := float(total_bytes) / 1048576.0
		_dl_bar.value = (float(dl_bytes) / float(total_bytes)) * 100.0
		_dl_label.text = "Downloading... %.1f / %.1f MB" % [mb, tmb]
	else:
		_dl_bar.value = fmod(mb * 20.0, 95.0)
		_dl_label.text = "Downloading... %.1f MB" % mb

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
