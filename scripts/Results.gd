extends Control

var _stage: ConcertStage

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage = ConcertStage.new()
	_stage.menu_idle_mode = true
	_stage.star_power_active = bool(GameState.last_result.get("fc", false))
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	var t := ThemeManager.get_theme_data()
	var res := GameState.last_result
	var song := GameState.current_song

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 60)
	margin.add_theme_constant_override("margin_right", 60)
	margin.add_theme_constant_override("margin_top", 22)
	margin.add_theme_constant_override("margin_bottom", 22)
	add_child(margin)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.04, 0.04, 0.10, 0.95), t["accent"], 18, 3, 18))
	margin.add_child(card)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	card.add_child(vbox)

	# Header
	var banner := Label.new()
	var is_fc := bool(res.get("fc", false))
	var is_new := bool(res.get("new_best", false))
	banner.text = "FULL COMBO!! LEGENDARY!" if is_fc else ("NEW HIGH SCORE! CONCERT CLEARED" if is_new else "CONCERT COMPLETE")
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		banner.add_theme_font_override("font", ThemeManager.font_display)
	banner.add_theme_font_size_override("font_size", 24)
	banner.add_theme_color_override("font_color", t["star_power"] if is_fc else t["accent"])
	vbox.add_child(banner)

	var song_lbl := Label.new()
	song_lbl.text = str(song.get("name", "Unknown Song")) + " — " + str(song.get("artist", "Artist")) + " [" + str(res.get("difficulty", "Expert")).to_upper() + "]"
	song_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_body:
		song_lbl.add_theme_font_override("font", ThemeManager.font_body)
	song_lbl.add_theme_font_size_override("font_size", 19)
	song_lbl.add_theme_color_override("font_color", t["text_dim"])
	vbox.add_child(song_lbl)

	# 5 Stars + Big Score Row
	var score_row := HBoxContainer.new()
	score_row.alignment = BoxContainer.ALIGNMENT_CENTER
	score_row.add_theme_constant_override("separation", 24)
	vbox.add_child(score_row)

	var stars := int(res.get("stars", 3))
	var star_lbl := Label.new()
	var s_txt := ""
	for i in range(5):
		s_txt += "★" if i < stars else "☆"
	star_lbl.text = s_txt
	star_lbl.add_theme_font_size_override("font_size", 38)
	star_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.20) if not is_fc else t["star_power"])
	score_row.add_child(star_lbl)

	var score_lbl := Label.new()
	score_lbl.text = str(int(res.get("score", 0))) + " PTS"
	if ThemeManager.font_display:
		score_lbl.add_theme_font_override("font", ThemeManager.font_display)
	score_lbl.add_theme_font_size_override("font_size", 34)
	score_lbl.add_theme_color_override("font_color", t["text"])
	score_row.add_child(score_lbl)

	# Stats Grid
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 8)
	vbox.add_child(grid)

	_add_stat_box(grid, "ACCURACY", "%.1f%%" % float(res.get("accuracy", 0.0)), t["accent"], t)
	_add_stat_box(grid, "MAX STREAK", str(int(res.get("max_streak", 0))), t["accent_2"], t)
	_add_stat_box(grid, "PERFECT / GREAT", str(int(res.get("perfect", 0))) + " / " + str(int(res.get("great", 0))), Color(0.18, 1.0, 0.58), t)
	_add_stat_box(grid, "GOOD / MISS", str(int(res.get("good", 0))) + " / " + str(int(res.get("missed", 0))), Color(1.0, 0.45, 0.35), t)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(spacer)

	# Action Buttons
	var btn_row := HBoxContainer.new()
	btn_row.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_row.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_row)

	var btn_replay := Button.new()
	btn_replay.text = "PLAY AGAIN"
	btn_replay.custom_minimum_size = Vector2(210, 50)
	ThemeManager.style_button(btn_replay, false)
	btn_replay.pressed.connect(func():
		GameState.play_click()
		get_tree().change_scene_to_file("res://scenes/Gameplay.tscn")
	)
	btn_row.add_child(btn_replay)

	var btn_menu := Button.new()
	btn_menu.text = "SONG LIBRARY"
	btn_menu.custom_minimum_size = Vector2(230, 50)
	ThemeManager.style_button(btn_menu, true)
	btn_menu.pressed.connect(func():
		GameState.play_click()
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	btn_row.add_child(btn_menu)

	GameState.play_star_sfx()

func _add_stat_box(parent: Control, label_txt: String, val_txt: String, val_col: Color, t: Dictionary) -> void:
	var p := PanelContainer.new()
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	p.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], Color(val_col.r, val_col.g, val_col.b, 0.55), 10, 1, 0))
	parent.add_child(p)
	var vb := VBoxContainer.new()
	vb.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(vb)
	var k := Label.new()
	k.text = label_txt
	k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_semi:
		k.add_theme_font_override("font", ThemeManager.font_semi)
	k.add_theme_font_size_override("font_size", 14)
	k.add_theme_color_override("font_color", t["text_dim"])
	vb.add_child(k)
	var v := Label.new()
	v.text = val_txt
	v.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		v.add_theme_font_override("font", ThemeManager.font_display)
	v.add_theme_font_size_override("font_size", 21)
	v.add_theme_color_override("font_color", val_col)
	vb.add_child(v)
