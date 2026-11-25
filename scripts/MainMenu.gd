extends Control

# Smartphone-Native Game Menu System for DroidHeroV2 (1600x720 HD Landscape):
# Step-by-step full-screen mobile flow:
# - SCREEN 0: HOME HUB (Hero emblem, Vinyl showcase, 4 big arcade touch buttons)
# - SCREEN 1: SONG SELECT (Touch song cards, Sort filter, Vinyl disc & optional audio preview)
# - SCREEN 2: DIFFICULTY & MODE (4 big level cards, Speed & No-Fail pills, Giant Launch button)
# - SCREEN 3: ENCHOR.US STORE (Full-screen mobile chart browser & 1-tap .sng downloader)
# - SCREEN 4: CUSTOMIZE (5 Concert Arena Themes + 3 HD Fretboard Deck Textures)
# - SCREEN 5: SETTINGS (Mobile sliders, Hit Window Strict/Normal/Lenient, Haptics, Calibration)

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
		# Iridescent sheen wedges
		for s in range(2):
			var a0 := angle + float(s) * PI
			draw_arc(c, r * 0.68, a0, a0 + 0.55, 20, Color(accent.r, accent.g, accent.b, 0.26), r * 0.36)
			draw_arc(c, r * 0.68, a0 + 0.6, a0 + 0.95, 16, Color(accent2.r, accent2.g, accent2.b, 0.20), r * 0.36)
		# Center label + spindle hole
		draw_circle(c, r * 0.31, accent2.darkened(0.25))
		draw_arc(c, r * 0.31, 0.0, TAU, 40, Color.WHITE, 2.2)
		draw_circle(c, r * 0.09, Color(0.03, 0.03, 0.06, 1.0))

var _stage: ConcertStage
var _screen_holder: Control
var _current_screen: int = Screen.HOME
var _sort_mode: int = 0 # 0=Title, 1=Artist, 2=Stars

# Song Select refs
var _lib_list_vbox: VBoxContainer
var _showcase_title: Label
var _showcase_artist: Label
var _showcase_best: Label
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

# Settings calibration state
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
		_btn_preview.text = "🔊 PREVIEW LAGU"

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
	var start_pos := maxf(0.0, streams[0].get_length() * 0.22)
	_preview_player.play(start_pos)
	_preview_active = true
	if _vinyl and is_instance_valid(_vinyl):
		_vinyl.spinning = true
	if _btn_preview and is_instance_valid(_btn_preview):
		_btn_preview.text = "■ HENTIKAN PREVIEW"

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
	page.add_theme_constant_override("margin_left", 32)
	page.add_theme_constant_override("margin_right", 32)
	page.add_theme_constant_override("margin_top", 22)
	page.add_theme_constant_override("margin_bottom", 22)
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
		page.position.x = 36.0
		var tw := create_tween().set_parallel(true)
		tw.tween_property(page, "modulate:a", 1.0, 0.16)
		tw.tween_property(page, "position:x", 0.0, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func _make_top_bar(parent: VBoxContainer, title_txt: String, back_target: int, back_label: String, t: Dictionary) -> HBoxContainer:
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 18)
	parent.add_child(bar)

	var btn_back := Button.new()
	btn_back.text = "◀  " + back_label
	btn_back.custom_minimum_size = Vector2(210, 66)
	ThemeManager.style_button(btn_back, false)
	btn_back.pressed.connect(func():
		GameState.play_click()
		_show_screen(back_target)
	)
	bar.add_child(btn_back)

	var title := Label.new()
	title.text = title_txt
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_display:
		title.add_theme_font_override("font", ThemeManager.font_display)
	title.add_theme_font_size_override("font_size", 34)
	title.add_theme_color_override("font_color", t["accent"])
	bar.add_child(title)
	return bar

# ============================================================================
# SCREEN 0: SMARTPHONE GAME HOME HUB
# ============================================================================
func _build_home_screen(parent: MarginContainer, t: Dictionary) -> void:
	var root_hb := HBoxContainer.new()
	root_hb.add_theme_constant_override("separation", 38)
	parent.add_child(root_hb)

	# Left Hero Branding + Current Track Vinyl Card
	var left_vb := VBoxContainer.new()
	left_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_vb.size_flags_stretch_ratio = 1.08
	left_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	left_vb.add_theme_constant_override("separation", 18)
	root_hb.add_child(left_vb)

	var title_box := VBoxContainer.new()
	title_box.add_theme_constant_override("separation", 2)
	left_vb.add_child(title_box)

	var logo := Label.new()
	logo.text = "DROIDHERO"
	if ThemeManager.font_display:
		logo.add_theme_font_override("font", ThemeManager.font_display)
	logo.add_theme_font_size_override("font_size", 64)
	logo.add_theme_color_override("font_color", t["accent"])
	title_box.add_child(logo)

	var sub_logo := Label.new()
	sub_logo.text = "V2.2 HD  •  MOBILE GUITAR RHYTHM"
	if ThemeManager.font_display:
		sub_logo.add_theme_font_override("font", ThemeManager.font_display)
	sub_logo.add_theme_font_size_override("font_size", 22)
	sub_logo.add_theme_color_override("font_color", t["accent_2"])
	title_box.add_child(sub_logo)

	# Collection Stats Pill
	var stats_pill := PanelContainer.new()
	stats_pill.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], Color(1, 1, 1, 0.22), 18, 1, 0))
	left_vb.add_child(stats_pill)

	var stats_lbl := Label.new()
	stats_lbl.text = "🎵 %d LAGU TERPASANG    •    ★ %d TOTAL BINTANG" % [GameState.library.size(), GameState.get_total_stars()]
	if ThemeManager.font_body:
		stats_lbl.add_theme_font_override("font", ThemeManager.font_body)
	stats_lbl.add_theme_font_size_override("font_size", 24)
	stats_lbl.add_theme_color_override("font_color", t["text"])
	stats_pill.add_child(stats_lbl)

	# Featured Active Song Card (Tap to jump straight to Difficulty!)
	var now_card := PanelContainer.new()
	now_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	now_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["border"], 24, 2, 14))
	left_vb.add_child(now_card)

	var now_hb := HBoxContainer.new()
	now_hb.add_theme_constant_override("separation", 22)
	now_hb.alignment = BoxContainer.ALIGNMENT_CENTER
	now_card.add_child(now_hb)

	var home_vinyl := VinylDisc.new()
	home_vinyl.accent = t["accent"]
	home_vinyl.accent2 = t["accent_2"]
	home_vinyl.custom_minimum_size = Vector2(165, 165)
	now_hb.add_child(home_vinyl)

	var now_vb := VBoxContainer.new()
	now_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	now_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	now_vb.add_theme_constant_override("separation", 8)
	now_hb.add_child(now_vb)

	var tag_lbl := Label.new()
	tag_lbl.text = "LAGU SIAP DIMAINKAN"
	if ThemeManager.font_semi:
		tag_lbl.add_theme_font_override("font", ThemeManager.font_semi)
	tag_lbl.add_theme_font_size_override("font_size", 20)
	tag_lbl.add_theme_color_override("font_color", t["accent"])
	now_vb.add_child(tag_lbl)

	var s_name := Label.new()
	s_name.text = str(GameState.current_song.get("name", "Neon Overdrive"))
	s_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	s_name.max_lines_visible = 2
	if ThemeManager.font_display:
		s_name.add_theme_font_override("font", ThemeManager.font_display)
	s_name.add_theme_font_size_override("font_size", 28)
	s_name.add_theme_color_override("font_color", t["text"])
	now_vb.add_child(s_name)

	var s_art := Label.new()
	s_art.text = str(GameState.current_song.get("artist", "DroidHero Studio")) + "  •  " + GameState.current_difficulty.to_upper()
	if ThemeManager.font_body:
		s_art.add_theme_font_override("font", ThemeManager.font_body)
	s_art.add_theme_font_size_override("font_size", 22)
	s_art.add_theme_color_override("font_color", t["text_dim"])
	now_vb.add_child(s_art)

	var btn_quick := Button.new()
	btn_quick.text = "⚡ LANGSUNG MAIN ▶"
	btn_quick.custom_minimum_size = Vector2(0, 62)
	ThemeManager.style_button(btn_quick, true, t["accent_2"])
	btn_quick.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.DIFFICULTY)
	)
	now_vb.add_child(btn_quick)

	# Right Column: Big Arcade Smartphone Menu Buttons
	var right_vb := VBoxContainer.new()
	right_vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_vb.size_flags_stretch_ratio = 0.95
	right_vb.alignment = BoxContainer.ALIGNMENT_CENTER
	right_vb.add_theme_constant_override("separation", 18)
	root_hb.add_child(right_vb)

	var btn_play := _make_arcade_menu_button("▶   PILIH LAGU & MAIN", "Koleksi lagu lokal & mode latihan", true, t["accent"], 126)
	btn_play.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.SONGS)
	)
	right_vb.add_child(btn_play)

	var btn_store := _make_arcade_menu_button("☁   UNDUH LAGU BARU", "Cari 85.000+ chart gratis di enchor.us", false, t["accent_2"], 104)
	btn_store.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.ENCHOR)
	)
	right_vb.add_child(btn_store)

	var btn_cust := _make_arcade_menu_button("🎨   TEMA & GITAR HD", "5 tema panggung & 3 tekstur fretboard", false, t["accent_3"], 104)
	btn_cust.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.CUSTOMIZE)
	)
	right_vb.add_child(btn_cust)

	var btn_set := _make_arcade_menu_button("⚙   PENGATURAN", "Kecepatan not, hit window & kalibrasi", false, t["border"], 104)
	btn_set.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.SETTINGS)
	)
	right_vb.add_child(btn_set)

func _make_arcade_menu_button(title_txt: String, sub_txt: String, primary: bool, col: Color, min_h: int) -> Button:
	var t := ThemeManager.get_theme_data()
	var btn := Button.new()
	btn.custom_minimum_size = Vector2(0, min_h)
	ThemeManager.style_button(btn, primary, col)

	var vb := VBoxContainer.new()
	vb.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	vb.add_theme_constant_override("separation", 2)
	var pad := MarginContainer.new()
	pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pad.add_theme_constant_override("margin_left", 26)
	pad.add_theme_constant_override("margin_right", 26)
	pad.add_child(vb)
	btn.add_child(pad)

	var tl := Label.new()
	tl.text = title_txt
	tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_display:
		tl.add_theme_font_override("font", ThemeManager.font_display)
	tl.add_theme_font_size_override("font_size", 32 if primary else 27)
	tl.add_theme_color_override("font_color", Color.WHITE if primary else t["text"])
	vb.add_child(tl)

	var sl := Label.new()
	sl.text = sub_txt
	sl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if ThemeManager.font_semi:
		sl.add_theme_font_override("font", ThemeManager.font_semi)
	sl.add_theme_font_size_override("font_size", 19)
	sl.add_theme_color_override("font_color", t["text_dim"])
	vb.add_child(sl)
	return btn

# ============================================================================
# SCREEN 1: MOBILE SONG SELECT CAROUSEL
# ============================================================================
func _build_songs_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	parent.add_child(vbox)

	var bar := _make_top_bar(vbox, "PILIH LAGU", Screen.HOME, "MENU", t)

	var sort_names := ["URUT: JUDUL", "URUT: ARTIS", "URUT: ★ BINTANG"]
	var btn_sort := Button.new()
	btn_sort.text = sort_names[_sort_mode]
	btn_sort.custom_minimum_size = Vector2(240, 64)
	ThemeManager.style_button(btn_sort, false)
	btn_sort.pressed.connect(func():
		GameState.play_click()
		_sort_mode = (_sort_mode + 1) % 3
		btn_sort.text = sort_names[_sort_mode]
		_populate_song_cards()
	)
	bar.add_child(btn_sort)

	var btn_imp := Button.new()
	btn_imp.text = "+ IMPORT .SNG/.ZIP"
	btn_imp.custom_minimum_size = Vector2(255, 64)
	ThemeManager.style_button(btn_imp, false, t["accent_2"])
	btn_imp.pressed.connect(func():
		GameState.play_click()
		_file_dialog.popup_centered_ratio(0.86)
	)
	bar.add_child(btn_imp)

	var split := HBoxContainer.new()
	split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	split.add_theme_constant_override("separation", 24)
	vbox.add_child(split)

	# Left: Big Touch Song Cards
	var list_panel := PanelContainer.new()
	list_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_panel.size_flags_stretch_ratio = 1.28
	list_panel.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	split.add_child(list_panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_panel.add_child(scroll)

	_lib_list_vbox = VBoxContainer.new()
	_lib_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_lib_list_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(_lib_list_vbox)

	# Right: Vinyl Showcase & Play Trigger
	var right_card := PanelContainer.new()
	right_card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_card.size_flags_stretch_ratio = 0.92
	right_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["accent_2"], 22, 2, 12))
	split.add_child(right_card)

	var rv := VBoxContainer.new()
	rv.alignment = BoxContainer.ALIGNMENT_CENTER
	rv.add_theme_constant_override("separation", 12)
	right_card.add_child(rv)

	_vinyl = VinylDisc.new()
	_vinyl.accent = t["accent"]
	_vinyl.accent2 = t["accent_2"]
	_vinyl.custom_minimum_size = Vector2(185, 185)
	_vinyl.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	rv.add_child(_vinyl)

	_showcase_title = Label.new()
	_showcase_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_showcase_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_showcase_title.max_lines_visible = 2
	if ThemeManager.font_display:
		_showcase_title.add_theme_font_override("font", ThemeManager.font_display)
	_showcase_title.add_theme_font_size_override("font_size", 28)
	_showcase_title.add_theme_color_override("font_color", t["text"])
	rv.add_child(_showcase_title)

	_showcase_artist = Label.new()
	_showcase_artist.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_body:
		_showcase_artist.add_theme_font_override("font", ThemeManager.font_body)
	_showcase_artist.add_theme_font_size_override("font_size", 22)
	_showcase_artist.add_theme_color_override("font_color", t["text_dim"])
	rv.add_child(_showcase_artist)

	_showcase_best = Label.new()
	_showcase_best.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_body:
		_showcase_best.add_theme_font_override("font", ThemeManager.font_body)
	_showcase_best.add_theme_font_size_override("font_size", 23)
	_showcase_best.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22))
	rv.add_child(_showcase_best)

	_btn_preview = Button.new()
	_btn_preview.text = "🔊 PREVIEW LAGU"
	_btn_preview.custom_minimum_size = Vector2(0, 58)
	ThemeManager.style_button(_btn_preview, false)
	_btn_preview.pressed.connect(func():
		GameState.play_click()
		_toggle_song_preview()
	)
	rv.add_child(_btn_preview)

	var btn_next := Button.new()
	btn_next.text = "PILIH KESULITAN  ▶"
	btn_next.custom_minimum_size = Vector2(0, 82)
	ThemeManager.style_button(btn_next, true, t["accent"])
	btn_next.add_theme_font_size_override("font_size", 30)
	btn_next.pressed.connect(func():
		GameState.play_click()
		_show_screen(Screen.DIFFICULTY)
	)
	rv.add_child(btn_next)

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
		card_btn.custom_minimum_size = Vector2(0, 96)
		card_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ThemeManager.style_button(card_btn, is_sel, t["accent"] if is_sel else Color(1, 1, 1, 0.22))

		var pad := MarginContainer.new()
		pad.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
		pad.add_theme_constant_override("margin_left", 22)
		pad.add_theme_constant_override("margin_right", 22)
		card_btn.add_child(pad)

		var hb := HBoxContainer.new()
		hb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_theme_constant_override("separation", 16)
		pad.add_child(hb)

		var vb := VBoxContainer.new()
		vb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		hb.add_child(vb)

		var nt := Label.new()
		nt.text = ("▶  " if is_sel else "") + str(song.get("name", "Song"))
		nt.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ThemeManager.font_display:
			nt.add_theme_font_override("font", ThemeManager.font_display)
		nt.add_theme_font_size_override("font_size", 25)
		nt.add_theme_color_override("font_color", Color.WHITE if is_sel else t["text"])
		vb.add_child(nt)

		var dur_s := int(song.get("song_length", 180000)) / 1000
		var sub := Label.new()
		sub.text = "%s   •   %d:%02d" % [str(song.get("artist", "Artist")), dur_s / 60, dur_s % 60]
		sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ThemeManager.font_body:
			sub.add_theme_font_override("font", ThemeManager.font_body)
		sub.add_theme_font_size_override("font_size", 21)
		sub.add_theme_color_override("font_color", t["text_dim"])
		vb.add_child(sub)

		var best_st := _get_best_stars_any_diff(str(song.get("id", "")))
		var st_lbl := Label.new()
		st_lbl.text = ("★".repeat(best_st) + "☆".repeat(5 - best_st)) if best_st > 0 else "BELUM DIMAIN"
		st_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if ThemeManager.font_body:
			st_lbl.add_theme_font_override("font", ThemeManager.font_body)
		st_lbl.add_theme_font_size_override("font_size", 24 if best_st > 0 else 19)
		st_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22) if best_st > 0 else t["text_dim"])
		hb.add_child(st_lbl)

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

	_refresh_showcase()

func _refresh_showcase() -> void:
	if not _showcase_title:
		return
	var s := GameState.current_song
	_showcase_title.text = str(s.get("name", "Neon Overdrive"))
	var dur_s := int(s.get("song_length", 180000)) / 1000
	_showcase_artist.text = "%s  •  %d:%02d" % [str(s.get("artist", "-")), dur_s / 60, dur_s % 60]
	var best := GameState.get_best(str(s.get("id", "")), GameState.current_difficulty)
	if best.is_empty():
		_showcase_best.text = "Rekor " + GameState.current_difficulty.to_upper() + ": Belum ada skor"
	else:
		_showcase_best.text = "%s: %d PTS  •  %.1f%% %s" % [
			GameState.current_difficulty.to_upper(),
			int(best.get("score", 0)),
			float(best.get("accuracy", 0.0)),
			" [FC]" if bool(best.get("fc", false)) else ""
		]

# ============================================================================
# SCREEN 2: SMARTPHONE DIFFICULTY & MODE LAUNCHER
# ============================================================================
func _build_difficulty_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	var s_title := str(GameState.current_song.get("name", "Song")) + " — " + str(GameState.current_song.get("artist", ""))
	_make_top_bar(vbox, s_title.left(42), Screen.SONGS, "LAGU", t)

	# 4 Big Arcade Difficulty Cards
	var cards_hb := HBoxContainer.new()
	cards_hb.size_flags_vertical = Control.SIZE_EXPAND_FILL
	cards_hb.add_theme_constant_override("separation", 18)
	vbox.add_child(cards_hb)

	var diff_defs := [
		{"id": "Easy", "title": "EASY", "desc": "Santai • 3-4 Jalur", "col": Color(0.12, 0.96, 0.48)},
		{"id": "Medium", "title": "MEDIUM", "desc": "Standar • 4 Jalur", "col": Color(1.0, 0.84, 0.16)},
		{"id": "Hard", "title": "HARD", "desc": "Cepat • 5 Jalur Penuh", "col": Color(1.0, 0.52, 0.12)},
		{"id": "Expert", "title": "EXPERT", "desc": "Pro • Chart Asli Penuh", "col": Color(1.0, 0.20, 0.34)}
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
		cv.add_theme_constant_override("separation", 14)
		dbtn.add_child(cv)

		var dlbl := Label.new()
		dlbl.text = dd["title"]
		dlbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_display:
			dlbl.add_theme_font_override("font", ThemeManager.font_display)
		dlbl.add_theme_font_size_override("font_size", 38)
		dlbl.add_theme_color_override("font_color", Color.WHITE if is_sel else dcol)
		cv.add_child(dlbl)

		var dsub := Label.new()
		dsub.text = dd["desc"]
		dsub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_body:
			dsub.add_theme_font_override("font", ThemeManager.font_body)
		dsub.add_theme_font_size_override("font_size", 22)
		dsub.add_theme_color_override("font_color", t["text_dim"])
		cv.add_child(dsub)

		var rec := GameState.get_best(str(GameState.current_song.get("id", "")), d_id)
		var st_cnt := int(rec.get("stars", 0))
		var st_lbl := Label.new()
		st_lbl.text = ("★".repeat(st_cnt) + "☆".repeat(5 - st_cnt)) if st_cnt > 0 else "☆☆☆☆☆"
		st_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		st_lbl.add_theme_font_size_override("font_size", 32)
		st_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.22) if st_cnt > 0 else Color(1, 1, 1, 0.22))
		cv.add_child(st_lbl)

		var best_txt := Label.new()
		best_txt.text = ("%d PTS (%.0f%%)" % [int(rec.get("score", 0)), float(rec.get("accuracy", 0.0))]) if not rec.is_empty() else "Belum ada skor"
		best_txt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		if ThemeManager.font_body:
			best_txt.add_theme_font_override("font", ThemeManager.font_body)
		best_txt.add_theme_font_size_override("font_size", 22)
		best_txt.add_theme_color_override("font_color", t["text"])
		cv.add_child(best_txt)

		dbtn.pressed.connect(func():
			GameState.play_click()
			GameState.current_difficulty = d_id
			_show_screen(Screen.DIFFICULTY, false)
		)
		cards_hb.add_child(dbtn)

	# Bottom Bar: Speed Pill + No-Fail Pill + Giant Launch Button
	var bot_hb := HBoxContainer.new()
	bot_hb.add_theme_constant_override("separation", 16)
	vbox.add_child(bot_hb)

	var speeds := [1.0, 0.75, 0.50, 1.25]
	var speed_labels := ["KECEPATAN: 100% NORMAL", "LATIHAN: 75% LAMBAT", "BELAJAR: 50% PELAN", "HYPERSPEED: 125%"]
	var cur_spd_idx := speeds.find(GameState.practice_speed)
	if cur_spd_idx < 0:
		cur_spd_idx = 0

	var btn_spd := Button.new()
	btn_spd.text = speed_labels[cur_spd_idx]
	btn_spd.custom_minimum_size = Vector2(390, 86)
	ThemeManager.style_button(btn_spd, false)
	btn_spd.pressed.connect(func():
		GameState.play_click()
		var nxt := (speeds.find(GameState.practice_speed) + 1) % speeds.size()
		GameState.practice_speed = speeds[nxt]
		btn_spd.text = speed_labels[nxt]
	)
	bot_hb.add_child(btn_spd)

	var nf_on := bool(GameState.settings.get("no_fail", false))
	var btn_nf := Button.new()
	btn_nf.text = "NO-FAIL: AKTIF ✓" if nf_on else "NO-FAIL: MATI"
	btn_nf.custom_minimum_size = Vector2(280, 86)
	ThemeManager.style_button(btn_nf, nf_on, Color(0.15, 0.95, 0.55))
	btn_nf.pressed.connect(func():
		GameState.play_click()
		var v := not bool(GameState.settings.get("no_fail", false))
		GameState.settings["no_fail"] = v
		GameState.save_data()
		_show_screen(Screen.DIFFICULTY, false)
	)
	bot_hb.add_child(btn_nf)

	var btn_go := Button.new()
	btn_go.text = "★  MULAI KONSER!  ★"
	btn_go.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_go.custom_minimum_size = Vector2(0, 86)
	ThemeManager.style_button(btn_go, true, t["accent"])
	btn_go.add_theme_font_size_override("font_size", 34)
	btn_go.pressed.connect(func():
		GameState.play_star_sfx()
		GameState.trigger_haptic(30)
		GameState.practice_start_sec = 0.0
		get_tree().change_scene_to_file("res://scenes/Gameplay.tscn")
	)
	bot_hb.add_child(btn_go)

# ============================================================================
# SCREEN 3: ENCHOR.US MOBILE SONG STORE
# ============================================================================
func _build_enchor_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	parent.add_child(vbox)

	var bar := _make_top_bar(vbox, "ENCHOR.US STORE", Screen.HOME, "MENU", t)

	_search_input = LineEdit.new()
	_search_input.placeholder_text = "Cari judul lagu, band, atau charter..."
	_search_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_search_input.custom_minimum_size = Vector2(460, 66)
	_search_input.add_theme_stylebox_override("normal", ThemeManager.make_card_style(Color(0.03, 0.03, 0.08, 0.96), t["border"], 16, 2, 0))
	if ThemeManager.font_body:
		_search_input.add_theme_font_override("font", ThemeManager.font_body)
	_search_input.add_theme_font_size_override("font_size", 26)
	_search_input.text_submitted.connect(func(q: String): _trigger_enchor_search(q, 1))
	bar.add_child(_search_input)

	var btn_search := Button.new()
	btn_search.text = "CARI"
	btn_search.custom_minimum_size = Vector2(150, 66)
	ThemeManager.style_button(btn_search, true)
	btn_search.pressed.connect(func():
		GameState.play_click()
		_trigger_enchor_search(_search_input.text, 1)
	)
	bar.add_child(btn_search)

	var btn_top := Button.new()
	btn_top.text = "POPULER"
	btn_top.custom_minimum_size = Vector2(175, 66)
	ThemeManager.style_button(btn_top, false)
	btn_top.pressed.connect(func():
		GameState.play_click()
		_search_input.text = ""
		_trigger_enchor_search("*", 1)
	)
	bar.add_child(btn_top)

	var list_card := PanelContainer.new()
	list_card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	vbox.add_child(list_card)

	var inner_vb := VBoxContainer.new()
	inner_vb.add_theme_constant_override("separation", 12)
	list_card.add_child(inner_vb)

	var prow := HBoxContainer.new()
	prow.add_theme_constant_override("separation", 14)
	inner_vb.add_child(prow)

	_enchor_status = Label.new()
	_enchor_status.text = "Memuat daftar chart dari api.enchor.us..."
	_enchor_status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_body:
		_enchor_status.add_theme_font_override("font", ThemeManager.font_body)
	_enchor_status.add_theme_font_size_override("font_size", 23)
	_enchor_status.add_theme_color_override("font_color", t["text_dim"])
	prow.add_child(_enchor_status)

	var btn_prev := Button.new()
	btn_prev.text = "◀ SEBELUMNYA"
	btn_prev.custom_minimum_size = Vector2(210, 54)
	ThemeManager.style_button(btn_prev, false)
	btn_prev.pressed.connect(func():
		if _enchor_page > 1:
			_trigger_enchor_search(_enchor_last_query, _enchor_page - 1)
	)
	prow.add_child(btn_prev)

	var btn_next := Button.new()
	btn_next.text = "BERIKUTNYA ▶"
	btn_next.custom_minimum_size = Vector2(210, 54)
	ThemeManager.style_button(btn_next, false)
	btn_next.pressed.connect(func():
		_trigger_enchor_search(_enchor_last_query, _enchor_page + 1)
	)
	prow.add_child(btn_next)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	inner_vb.add_child(scroll)

	_enchor_list_vbox = VBoxContainer.new()
	_enchor_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_enchor_list_vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(_enchor_list_vbox)

	_trigger_enchor_search(_enchor_last_query, _enchor_page)

func _trigger_enchor_search(query: String, page: int) -> void:
	_enchor_last_query = query if query.strip_edges() != "" else "*"
	_enchor_page = maxi(1, page)
	if _enchor_status:
		_enchor_status.text = "Mencari di enchor.us (Halaman " + str(_enchor_page) + ")..."
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

	_enchor_status.text = "Ditemukan %d chart  •  Halaman %d" % [total_found, page]
	var t := ThemeManager.get_theme_data()

	for item in results:
		var md5 := str(item.get("md5", ""))
		var downloaded := EnchorClient.is_downloaded(md5)

		var row := PanelContainer.new()
		row.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], t["accent"] if downloaded else Color(1, 1, 1, 0.16), 18, 2 if downloaded else 1, 0))
		_enchor_list_vbox.add_child(row)

		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 20)
		hb.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_child(hb)

		var art_box := TextureRect.new()
		art_box.custom_minimum_size = Vector2(86, 86)
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
		vb.alignment = BoxContainer.ALIGNMENT_CENTER
		hb.add_child(vb)

		var title := Label.new()
		title.text = str(item.get("name", "Song")) + " — " + str(item.get("artist", "Artist"))
		if ThemeManager.font_display:
			title.add_theme_font_override("font", ThemeManager.font_display)
		title.add_theme_font_size_override("font_size", 24)
		title.add_theme_color_override("font_color", t["text"])
		vb.add_child(title)

		var dur_s := int(item.get("song_length", 180000)) / 1000
		var diff_g := maxi(0, int(item.get("diff_guitar", 3)))
		var meta_lbl := Label.new()
		meta_lbl.text = "Charter: %s   •   Kesulitan Gitar: %d/6   •   %d:%02d" % [
			str(item.get("charter", "Community")),
			diff_g,
			dur_s / 60,
			dur_s % 60
		]
		if ThemeManager.font_body:
			meta_lbl.add_theme_font_override("font", ThemeManager.font_body)
		meta_lbl.add_theme_font_size_override("font_size", 21)
		meta_lbl.add_theme_color_override("font_color", t["text_dim"])
		vb.add_child(meta_lbl)

		var item_copy: Dictionary = item
		if downloaded:
			var btn_play := Button.new()
			btn_play.text = "▶ MAIN"
			btn_play.custom_minimum_size = Vector2(200, 70)
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
			hb.add_child(btn_play)
		else:
			var btn_dl := Button.new()
			btn_dl.text = "⬇ UNDUH"
			btn_dl.custom_minimum_size = Vector2(215, 70)
			ThemeManager.style_button(btn_dl, true, t["accent_2"])
			btn_dl.pressed.connect(func():
				GameState.play_click()
				_start_song_download(item_copy)
			)
			hb.add_child(btn_dl)

func _on_cover_loaded(art_md5: String, tex: Texture2D) -> void:
	if _cover_rects.has(art_md5):
		for rect in _cover_rects[art_md5]:
			if is_instance_valid(rect):
				rect.texture = tex

# ============================================================================
# SCREEN 4: CUSTOMIZE ARENA THEME & HD FRETBOARD TEXTURE
# ============================================================================
func _build_customize_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 18)
	parent.add_child(vbox)

	_make_top_bar(vbox, "TEMA ARENA & PAPAN GITAR HD", Screen.HOME, "MENU", t)

	# Fretboard Surface Style Selector Row
	var board_card := PanelContainer.new()
	board_card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 20, 2, 6))
	vbox.add_child(board_card)

	var bhb := HBoxContainer.new()
	bhb.add_theme_constant_override("separation", 16)
	bhb.alignment = BoxContainer.ALIGNMENT_CENTER
	board_card.add_child(bhb)

	var blbl := Label.new()
	blbl.text = "TEKSTUR FRETBOARD HD:"
	blbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_display:
		blbl.add_theme_font_override("font", ThemeManager.font_display)
	blbl.add_theme_font_size_override("font_size", 24)
	blbl.add_theme_color_override("font_color", t["text"])
	bhb.add_child(blbl)

	var cur_board := str(GameState.settings.get("board_style", "carbon"))
	var boards := [
		{"id": "carbon", "name": "CARBON FIBER"},
		{"id": "rosewood", "name": "ROSEWOOD KAYU"},
		{"id": "obsidian", "name": "OBSIDIAN METAL"}
	]
	for b in boards:
		var bid: String = b["id"]
		var active := (cur_board == bid)
		var bb := Button.new()
		bb.text = ("✓ " if active else "") + str(b["name"])
		bb.custom_minimum_size = Vector2(255, 62)
		ThemeManager.style_button(bb, active, t["accent_2"])
		bb.pressed.connect(func():
			GameState.play_click()
			GameState.settings["board_style"] = bid
			GameState.save_data()
			_show_screen(Screen.CUSTOMIZE, false)
		)
		bhb.add_child(bb)

	# Scrollable 5 Arena Theme Cards
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)

	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 18)
	grid.add_theme_constant_override("v_separation", 18)
	scroll.add_child(grid)

	for tid in ThemeManager.THEMES.keys():
		var td: Dictionary = ThemeManager.THEMES[tid]
		var active: bool = (str(tid) == ThemeManager.current_theme_id)
		var tc := PanelContainer.new()
		tc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tc.add_theme_stylebox_override("panel", ThemeManager.make_card_style(td["panel_alt"], td["accent"], 20, 3 if active else 1, 14 if active else 0))
		grid.add_child(tc)

		var tv := VBoxContainer.new()
		tv.add_theme_constant_override("separation", 12)
		tc.add_child(tv)

		var tname := Label.new()
		tname.text = str(td["name"])
		if ThemeManager.font_display:
			tname.add_theme_font_override("font", ThemeManager.font_display)
		tname.add_theme_font_size_override("font_size", 24)
		tname.add_theme_color_override("font_color", td["accent"])
		tv.add_child(tname)

		var tsub := Label.new()
		tsub.text = str(td["subtitle"])
		tsub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		if ThemeManager.font_body:
			tsub.add_theme_font_override("font", ThemeManager.font_body)
		tsub.add_theme_font_size_override("font_size", 20)
		tsub.add_theme_color_override("font_color", td["text_dim"])
		tv.add_child(tsub)

		var sw_row := HBoxContainer.new()
		sw_row.add_theme_constant_override("separation", 10)
		tv.add_child(sw_row)
		for sc in td["spotlights"]:
			var sw := ColorRect.new()
			sw.color = sc
			sw.custom_minimum_size = Vector2(48, 24)
			sw_row.add_child(sw)

		var btn := Button.new()
		btn.text = "✓ TEMA AKTIF" if active else "PAKAI TEMA"
		btn.custom_minimum_size = Vector2(0, 64)
		ThemeManager.style_button(btn, active, td["accent"])
		var target_id := str(tid)
		btn.pressed.connect(func():
			GameState.play_star_sfx()
			ThemeManager.set_theme(target_id)
		)
		tv.add_child(btn)

# ============================================================================
# SCREEN 5: SMARTPHONE SETTINGS & AUDIO CALIBRATION
# ============================================================================
func _build_settings_screen(parent: MarginContainer, t: Dictionary) -> void:
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	parent.add_child(vbox)

	var bar := _make_top_bar(vbox, "PENGATURAN & KALIBRASI", Screen.HOME, "MENU", t)

	_fps_lbl = Label.new()
	_fps_lbl.text = "60 FPS"
	if ThemeManager.font_display:
		_fps_lbl.add_theme_font_override("font", ThemeManager.font_display)
	_fps_lbl.add_theme_font_size_override("font_size", 24)
	_fps_lbl.add_theme_color_override("font_color", t["accent_2"])
	bar.add_child(_fps_lbl)

	var card := PanelContainer.new()
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel"], t["border"], 22, 2, 8))
	vbox.add_child(card)

	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(scroll)

	var hsplit := HBoxContainer.new()
	hsplit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hsplit.add_theme_constant_override("separation", 36)
	scroll.add_child(hsplit)

	# Left Column: Gameplay Sliders & Hit Window
	var left_v := VBoxContainer.new()
	left_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left_v.add_theme_constant_override("separation", 16)
	hsplit.add_child(left_v)

	_add_slider_row(left_v, "Kecepatan Scroll Not", 0.7, 1.8, 0.05, float(GameState.settings.get("note_speed", 1.0)), func(v: float):
		GameState.settings["note_speed"] = v
		GameState.save_data()
	)
	_add_slider_row(left_v, "Volume Musik", 0.1, 1.0, 0.05, float(GameState.settings.get("music_volume", 1.0)), func(v: float):
		GameState.settings["music_volume"] = v
		GameState.save_data()
	)
	_add_slider_row(left_v, "Volume Efek Suara", 0.0, 1.0, 0.05, float(GameState.settings.get("sfx_volume", 0.85)), func(v: float):
		GameState.settings["sfx_volume"] = v
		GameState.save_data()
	)
	_add_slider_row(left_v, "Intensitas Lampu Konser", 0.4, 1.5, 0.05, float(GameState.settings.get("light_intensity", 1.0)), func(v: float):
		GameState.settings["light_intensity"] = v
		GameState.save_data()
	)

	# Hit Window Selector (inspired by Switch Hero!)
	var hw_row := HBoxContainer.new()
	hw_row.add_theme_constant_override("separation", 10)
	left_v.add_child(hw_row)

	var hw_lbl := Label.new()
	hw_lbl.text = "Toleransi Timing:"
	hw_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_body:
		hw_lbl.add_theme_font_override("font", ThemeManager.font_body)
	hw_lbl.add_theme_font_size_override("font_size", 25)
	hw_row.add_child(hw_lbl)

	var cur_hw := str(GameState.settings.get("hit_window", "normal"))
	for w_opt in ["strict", "normal", "lenient"]:
		var wb := Button.new()
		wb.text = w_opt.to_upper()
		wb.custom_minimum_size = Vector2(138, 56)
		ThemeManager.style_button(wb, cur_hw == w_opt, t["accent"])
		var w_val: String = w_opt
		wb.pressed.connect(func():
			GameState.play_click()
			GameState.settings["hit_window"] = w_val
			GameState.save_data()
			_show_screen(Screen.SETTINGS, false)
		)
		hw_row.add_child(wb)

	# Right Column: Toggles & Audio Calibration
	var right_v := VBoxContainer.new()
	right_v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right_v.add_theme_constant_override("separation", 16)
	hsplit.add_child(right_v)

	var toggle_row := HBoxContainer.new()
	toggle_row.add_theme_constant_override("separation", 14)
	right_v.add_child(toggle_row)

	var hap_on := bool(GameState.settings.get("haptics", true))
	var btn_hap := Button.new()
	btn_hap.text = "GETAR HAPTIC: ON" if hap_on else "GETAR HAPTIC: OFF"
	btn_hap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_hap.custom_minimum_size = Vector2(0, 62)
	ThemeManager.style_button(btn_hap, hap_on)
	btn_hap.pressed.connect(func():
		GameState.settings["haptics"] = not hap_on
		GameState.save_data()
		GameState.trigger_haptic(25)
		_show_screen(Screen.SETTINGS, false)
	)
	toggle_row.add_child(btn_hap)

	var fps_on := bool(GameState.settings.get("show_fps", true))
	var btn_fps := Button.new()
	btn_fps.text = "INFO FPS: ON" if fps_on else "INFO FPS: OFF"
	btn_fps.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_fps.custom_minimum_size = Vector2(0, 62)
	ThemeManager.style_button(btn_fps, fps_on)
	btn_fps.pressed.connect(func():
		GameState.settings["show_fps"] = not fps_on
		GameState.save_data()
		_show_screen(Screen.SETTINGS, false)
	)
	toggle_row.add_child(btn_fps)

	_cal_lbl = Label.new()
	_cal_lbl.text = "Offset Audio / Bluetooth: %d ms" % int(round(float(GameState.settings.get("audio_offset_ms", 0.0))))
	if ThemeManager.font_display:
		_cal_lbl.add_theme_font_override("font", ThemeManager.font_display)
	_cal_lbl.add_theme_font_size_override("font_size", 25)
	_cal_lbl.add_theme_color_override("font_color", t["accent_2"])
	right_v.add_child(_cal_lbl)

	var cal_slider := HSlider.new()
	cal_slider.min_value = -150.0
	cal_slider.max_value = 150.0
	cal_slider.step = 5.0
	cal_slider.custom_minimum_size = Vector2(0, 44)
	cal_slider.value = float(GameState.settings.get("audio_offset_ms", 0.0))
	cal_slider.value_changed.connect(func(v: float):
		GameState.settings["audio_offset_ms"] = v
		GameState.save_data()
		_cal_lbl.text = "Offset Audio / Bluetooth: %d ms" % int(round(v))
	)
	right_v.add_child(cal_slider)

	var step_row := HBoxContainer.new()
	step_row.add_theme_constant_override("separation", 12)
	right_v.add_child(step_row)

	for step_ms in [-10.0, 0.0, 10.0]:
		var sb := Button.new()
		sb.text = "RESET 0 ms" if step_ms == 0.0 else ("%+d ms" % int(step_ms))
		sb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		sb.custom_minimum_size = Vector2(0, 58)
		ThemeManager.style_button(sb, false)
		var delta_ms: float = step_ms
		sb.pressed.connect(func():
			GameState.play_click()
			cal_slider.value = 0.0 if delta_ms == 0.0 else clampf(cal_slider.value + delta_ms, -150.0, 150.0)
		)
		step_row.add_child(sb)

	var btn_toggle_beat := Button.new()
	btn_toggle_beat.text = "▶ MULAI TES SUARA KETUKAN"
	btn_toggle_beat.custom_minimum_size = Vector2(0, 64)
	ThemeManager.style_button(btn_toggle_beat, false)
	btn_toggle_beat.pressed.connect(func():
		_cal_test_active = not _cal_test_active
		_cal_beat_timer = 0.0
		_cal_taps.clear()
		btn_toggle_beat.text = "■ HENTIKAN TES KETUKAN" if _cal_test_active else "▶ MULAI TES SUARA KETUKAN"
	)
	right_v.add_child(btn_toggle_beat)

	var btn_tap := Button.new()
	btn_tap.text = "🥁 KETUK SESUAI SUARA BIT (AUTO-KALIBRASI)"
	btn_tap.custom_minimum_size = Vector2(0, 74)
	ThemeManager.style_button(btn_tap, true, t["accent_2"])
	btn_tap.pressed.connect(func():
		if not _cal_test_active:
			_cal_test_active = true
			_cal_beat_timer = 0.0
			btn_toggle_beat.text = "■ HENTIKAN TES KETUKAN"
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
	right_v.add_child(btn_tap)

func _add_slider_row(parent: Control, label_txt: String, min_v: float, max_v: float, step_v: float, init_v: float, cb: Callable) -> void:
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 4)
	parent.add_child(vb)
	var hb := HBoxContainer.new()
	vb.add_child(hb)
	var l := Label.new()
	l.text = label_txt
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_body:
		l.add_theme_font_override("font", ThemeManager.font_body)
	l.add_theme_font_size_override("font_size", 25)
	hb.add_child(l)
	var vl := Label.new()
	vl.text = "%.2f" % init_v
	if ThemeManager.font_display:
		vl.add_theme_font_override("font", ThemeManager.font_display)
	vl.add_theme_font_size_override("font_size", 23)
	hb.add_child(vl)
	var sl := HSlider.new()
	sl.min_value = min_v
	sl.max_value = max_v
	sl.step = step_v
	sl.value = init_v
	sl.custom_minimum_size = Vector2(0, 42)
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
	_dl_modal.offset_left = -340
	_dl_modal.offset_top = -145
	_dl_modal.offset_right = 340
	_dl_modal.offset_bottom = 145
	_dl_modal.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.03, 0.03, 0.09, 0.98), t["accent"], 24, 3, 24))
	add_child(_dl_modal)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	_dl_modal.add_child(vb)

	_dl_label = Label.new()
	_dl_label.text = "Mengunduh paket lagu .sng..."
	_dl_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dl_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		_dl_label.add_theme_font_override("font", ThemeManager.font_body)
	_dl_label.add_theme_font_size_override("font_size", 26)
	vb.add_child(_dl_label)

	_dl_bar = ProgressBar.new()
	_dl_bar.custom_minimum_size = Vector2(0, 34)
	vb.add_child(_dl_bar)

	var btn_cancel := Button.new()
	btn_cancel.text = "BATALKAN"
	btn_cancel.custom_minimum_size = Vector2(0, 62)
	ThemeManager.style_button(btn_cancel, false)
	btn_cancel.pressed.connect(func():
		EnchorClient.cancel_download()
		_dl_modal.visible = false
	)
	vb.add_child(btn_cancel)

func _start_song_download(meta: Dictionary) -> void:
	_dl_modal.visible = true
	_dl_bar.value = 0.0
	_dl_label.text = "Mengunduh: " + str(meta.get("name", "Chart")) + "..."
	EnchorClient.download_chart(meta)

func _on_dl_progress(_md5: String, dl_bytes: int, total_bytes: int) -> void:
	if not _dl_modal or not _dl_modal.visible:
		return
	var mb := float(dl_bytes) / 1048576.0
	if total_bytes > 0:
		var tmb := float(total_bytes) / 1048576.0
		_dl_bar.value = (float(dl_bytes) / float(total_bytes)) * 100.0
		_dl_label.text = "Mengunduh... %.1f / %.1f MB" % [mb, tmb]
	else:
		_dl_bar.value = fmod(mb * 20.0, 95.0)
		_dl_label.text = "Mengunduh... %.1f MB" % mb

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
