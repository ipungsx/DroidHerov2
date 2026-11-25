# Copyright (c) 2026 ipungsx (https://github.com/ipungsx)
extends Control

var _stage: ConcertStage

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_go_back_to_songs()

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		_go_back_to_songs()

func _go_back_to_songs() -> void:
	GameState.play_click()
	GameState.open_screen_on_menu = 1
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_stage = ConcertStage.new()
	_stage.menu_idle_mode = true
	_stage.music_playing = false
	_stage.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_stage)

	var t := ThemeManager.get_theme_data()
	var res := GameState.last_result
	var song := GameState.current_song

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 28)
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_top", 50)
	margin.add_theme_constant_override("margin_bottom", 38)
	add_child(margin)

	var card := PanelContainer.new()
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_theme_stylebox_override("panel", ThemeManager.make_card_style(Color(0.04, 0.04, 0.10, 0.96), t["accent"], 26, 3, 24))
	margin.add_child(card)

	var root_vb := VBoxContainer.new()
	root_vb.add_theme_constant_override("separation", 18)
	card.add_child(root_vb)

	# Top Title Banner
	var is_fc := bool(res.get("fc", false))
	var is_new := bool(res.get("new_best", false))
	var banner := Label.new()
	banner.text = I18n.t("res_fc") if is_fc else (I18n.t("res_new") if is_new else I18n.t("res_done"))
	banner.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		banner.add_theme_font_override("font", ThemeManager.font_display)
	banner.add_theme_font_size_override("font_size", 42)
	banner.add_theme_color_override("font_color", t["star_power"] if is_fc else t["accent"])
	root_vb.add_child(banner)

	var song_lbl := Label.new()
	song_lbl.text = "%s\n%s  [%s]" % [
		str(song.get("name", "Song")),
		str(song.get("artist", "Artist")),
		str(res.get("difficulty", "Expert")).to_upper()
	]
	song_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	song_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if ThemeManager.font_body:
		song_lbl.add_theme_font_override("font", ThemeManager.font_body)
	song_lbl.add_theme_font_size_override("font_size", 26)
	song_lbl.add_theme_color_override("font_color", t["text_dim"])
	root_vb.add_child(song_lbl)

	# Giant Rank + Stars + Score Block
	var acc := float(res.get("accuracy", 0.0))
	var rank_letter := "S" if acc >= 95.0 else ("A" if acc >= 86.0 else ("B" if acc >= 75.0 else ("C" if acc >= 60.0 else "D")))
	var rank_col: Color = t["star_power"] if rank_letter == "S" else (Color(0.25, 1.0, 0.55) if rank_letter == "A" else Color(1.0, 0.84, 0.22))

	var rank_lbl := Label.new()
	rank_lbl.text = rank_letter
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		rank_lbl.add_theme_font_override("font", ThemeManager.font_display)
	rank_lbl.add_theme_font_size_override("font_size", 142)
	rank_lbl.add_theme_color_override("font_color", rank_col)
	root_vb.add_child(rank_lbl)

	var stars := int(res.get("stars", 3))
	var star_lbl := Label.new()
	star_lbl.text = "★".repeat(stars) + "☆".repeat(5 - stars)
	star_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	star_lbl.add_theme_font_size_override("font_size", 58)
	star_lbl.add_theme_color_override("font_color", Color(1.0, 0.86, 0.20) if not is_fc else t["star_power"])
	root_vb.add_child(star_lbl)

	var score_lbl := Label.new()
	score_lbl.text = str(int(res.get("score", 0))) + " PTS"
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if ThemeManager.font_display:
		score_lbl.add_theme_font_override("font", ThemeManager.font_display)
	score_lbl.add_theme_font_size_override("font_size", 50)
	score_lbl.add_theme_color_override("font_color", t["text"])
	root_vb.add_child(score_lbl)

	# Breakdown Rows
	var hit_cnt := int(res.get("perfect", 0)) + int(res.get("great", 0)) + int(res.get("good", 0))
	var tot_cnt := maxi(hit_cnt + int(res.get("missed", 0)), int(res.get("total_notes", 0)))
	_add_stat_row(root_vb, I18n.t("notes_hit"), "%d / %d (%.1f%%)" % [hit_cnt, tot_cnt, acc], t["accent"], t)
	_add_stat_row(root_vb, I18n.t("best_streak"), str(int(res.get("max_streak", 0))) + "x", t["accent_2"], t)
	_add_stat_row(
		root_vb,
		"P / GR / GD / M",
		"%d / %d / %d / %d" % [
			int(res.get("perfect", 0)),
			int(res.get("great", 0)),
			int(res.get("good", 0)),
			int(res.get("missed", 0))
		],
		Color(0.25, 1.0, 0.62),
		t
	)
	if int(res.get("solo_bonus", 0)) > 0:
		_add_stat_row(root_vb, I18n.t("solo_bonus"), "+" + str(int(res.get("solo_bonus", 0))) + " PTS", t["star_power"], t)

	# Smart Timing Offset Assistant
	var samples := int(res.get("hit_samples", 0))
	var med_ms := float(res.get("median_offset_ms", 0.0))
	if samples >= 10 and absf(med_ms) >= 8.0:
		var fix_delta: float = roundf(med_ms / 5.0) * 5.0
		var dir_word := I18n.t("late") if med_ms > 0.0 else I18n.t("early")
		var tip_btn := Button.new()
		tip_btn.text = I18n.t("timing_tip") % [int(round(absf(med_ms))), dir_word, int(fix_delta)]
		tip_btn.custom_minimum_size = Vector2(0, 74)
		ThemeManager.style_button(tip_btn, false, Color(1.0, 0.78, 0.20))
		tip_btn.add_theme_font_size_override("font_size", 24)
		tip_btn.pressed.connect(func():
			GameState.play_click()
			var cur_off := float(GameState.settings.get("audio_offset_ms", 0.0))
			var next_off := clampf(cur_off + fix_delta, -150.0, 150.0)
			GameState.settings["audio_offset_ms"] = next_off
			GameState.save_data()
			tip_btn.text = I18n.t("timing_fixed") % int(round(next_off))
			tip_btn.disabled = true
		)
		root_vb.add_child(tip_btn)

	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_vb.add_child(sp)

	# Bottom Vertical Smartphone Action Buttons
	var pair_hb := HBoxContainer.new()
	pair_hb.add_theme_constant_override("separation", 14)
	root_vb.add_child(pair_hb)

	var btn_retry := Button.new()
	btn_retry.text = I18n.t("play_again")
	btn_retry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_retry.custom_minimum_size = Vector2(0, 88)
	ThemeManager.style_button(btn_retry, false)
	btn_retry.pressed.connect(func():
		GameState.play_click()
		get_tree().change_scene_to_file("res://scenes/Gameplay.tscn")
	)
	pair_hb.add_child(btn_retry)

	var btn_diff := Button.new()
	btn_diff.text = I18n.t("change_diff")
	btn_diff.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_diff.custom_minimum_size = Vector2(0, 88)
	ThemeManager.style_button(btn_diff, false, t["accent_2"])
	btn_diff.pressed.connect(func():
		GameState.play_click()
		GameState.open_screen_on_menu = 2
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	pair_hb.add_child(btn_diff)

	var btn_songs := Button.new()
	btn_songs.text = I18n.t("song_library")
	btn_songs.custom_minimum_size = Vector2(0, 96)
	ThemeManager.style_button(btn_songs, true, t["accent"])
	btn_songs.add_theme_font_size_override("font_size", 32)
	btn_songs.pressed.connect(func():
		GameState.play_click()
		GameState.open_screen_on_menu = 1
		get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
	)
	root_vb.add_child(btn_songs)

	GameState.play_star_sfx()

func _add_stat_row(parent: Control, label_txt: String, val_txt: String, val_col: Color, t: Dictionary) -> void:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", ThemeManager.make_card_style(t["panel_alt"], Color(val_col.r, val_col.g, val_col.b, 0.45), 16, 1, 0))
	parent.add_child(p)

	var hb := HBoxContainer.new()
	p.add_child(hb)

	var k := Label.new()
	k.text = label_txt
	k.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if ThemeManager.font_semi:
		k.add_theme_font_override("font", ThemeManager.font_semi)
	k.add_theme_font_size_override("font_size", 24)
	k.add_theme_color_override("font_color", t["text_dim"])
	hb.add_child(k)

	var v := Label.new()
	v.text = val_txt
	if ThemeManager.font_display:
		v.add_theme_font_override("font", ThemeManager.font_display)
	v.add_theme_font_size_override("font_size", 26)
	v.add_theme_color_override("font_color", val_col)
	hb.add_child(v)
