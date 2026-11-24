class_name ConcertStage
extends Control

# High-FPS Concert Arena Visualizer:
# - Overhead truss with 8 moving-head spotlights sweeping and flashing on drum hits
# - Snare strobe blinders + criss-crossing cymbal laser beams
# - Dual stage subwoofer stacks + 16-band real-time LED spectrum wall
# - Kick-drum shockwave rings + Star Power overdrive aura
# - Animated concert crowd silhouettes jumping to the drum groove

var menu_idle_mode: bool = false
var music_playing: bool = false
var star_power_active: bool = false
var combo_level: int = 1 # 1..4

# Drum envelope states (0.0 .. 1.5)
var kick_pulse: float = 0.0
var snare_pulse: float = 0.0
var cymbal_pulse: float = 0.0
var light_scale: float = 1.0
var _has_audio_energy: bool = false

var _time: float = 0.0
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _eq_bars: PackedFloat32Array = PackedFloat32Array()
var _prev_sub_energy: float = 0.0
var _prev_snare_energy: float = 0.0
var _beat_cooldown: float = 0.0
var _snare_cooldown: float = 0.0
var _laser_seed: int = 0

# Preallocated polygon buffers to avoid per-frame GC allocations (smooth 60fps!)
var _beam_poly: PackedVector2Array = PackedVector2Array()
var _beam_cols: PackedColorArray = PackedColorArray()
var _crowd_heads: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eq_bars.resize(16)
	_eq_bars.fill(0.05)
	_beam_poly.resize(4)
	_beam_cols.resize(4)
	_crowd_heads.resize(34)
	for i in range(34):
		_crowd_heads[i] = fmod(float(i) * 0.37, 1.0)
	_spectrum = GameState.get_music_spectrum()
	light_scale = float(GameState.settings.get("light_intensity", 1.0))

func trigger_drum(drum_type: int, strength: float = 1.0) -> void:
	if not music_playing:
		return
	if drum_type == 0: # Kick drum boom
		kick_pulse = clampf(maxf(kick_pulse, 1.15 * strength), 0.0, 1.5)
	elif drum_type == 1: # Snare crack
		snare_pulse = clampf(maxf(snare_pulse, 1.15 * strength), 0.0, 1.5)
		_laser_seed = (_laser_seed + 1) % 8
	else: # Cymbal / Tom
		cymbal_pulse = clampf(maxf(cymbal_pulse, 0.95 * strength), 0.0, 1.4)

func _process(delta: float) -> void:
	light_scale = float(GameState.settings.get("light_intensity", 1.0))

	# Smooth decay of drum light envelopes
	kick_pulse = maxf(0.0, kick_pulse - delta * 4.6)
	snare_pulse = maxf(0.0, snare_pulse - delta * 6.4)
	cymbal_pulse = maxf(0.0, cymbal_pulse - delta * 5.2)
	_beat_cooldown = maxf(0.0, _beat_cooldown - delta)
	_snare_cooldown = maxf(0.0, _snare_cooldown - delta)

	if _spectrum == null:
		_spectrum = GameState.get_music_spectrum()

	var audio_active := false
	if music_playing and _spectrum != null:
		# Sample sub-bass / kick (35..135 Hz) and snare transient band (180..420 Hz + 1.8k..4.5k Hz)
		var sub_mag := _spectrum.get_magnitude_for_frequency_range(35.0, 135.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
		var low_mid := _spectrum.get_magnitude_for_frequency_range(160.0, 360.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE).length()
		var snap_hi := _spectrum.get_magnitude_for_frequency_range(1800.0, 4800.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
		var hat_hi := _spectrum.get_magnitude_for_frequency_range(5500.0, 12000.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE).length()

		if sub_mag > 0.004 or low_mid > 0.004 or snap_hi > 0.004:
			audio_active = true
			var sub_flux := sub_mag - _prev_sub_energy
			if sub_flux > 0.045 and sub_mag > 0.085 and _beat_cooldown <= 0.0:
				trigger_drum(0, clampf(sub_mag * 4.2, 0.65, 1.35))
				_beat_cooldown = 0.13
			_prev_sub_energy = lerpf(_prev_sub_energy, sub_mag, delta * 14.0)

			var snare_e := low_mid * 0.6 + snap_hi * 0.9
			if (snare_e - _prev_snare_energy) > 0.04 and snare_e > 0.075 and _snare_cooldown <= 0.0:
				trigger_drum(1, clampf(snare_e * 4.0, 0.55, 1.25))
				_snare_cooldown = 0.15
			_prev_snare_energy = lerpf(_prev_snare_energy, snare_e, delta * 15.0)

			if hat_hi > 0.035:
				cymbal_pulse = maxf(cymbal_pulse, clampf(hat_hi * 5.5, 0.0, 0.85))
		else:
			_prev_sub_energy = lerpf(_prev_sub_energy, 0.0, delta * 10.0)
			_prev_snare_energy = lerpf(_prev_snare_energy, 0.0, delta * 10.0)

		var f_lo := 40.0
		for i in range(16):
			var f_hi := f_lo * 1.38
			var m := _spectrum.get_magnitude_for_frequency_range(f_lo, f_hi).length()
			var target := clampf(sqrt(m) * 2.4, 0.05, 1.0) if audio_active else 0.05
			_eq_bars[i] = lerpf(_eq_bars[i], target, delta * 14.0)
			f_lo = f_hi
	else:
		kick_pulse = 0.0
		snare_pulse = 0.0
		cymbal_pulse = 0.0
		for i in range(16):
			_eq_bars[i] = lerpf(_eq_bars[i], 0.05, delta * 10.0)

	_has_audio_energy = music_playing and (audio_active or kick_pulse > 0.02 or snare_pulse > 0.02)
	if _has_audio_energy:
		_time += delta

	queue_redraw()

func _draw() -> void:
	var sz := size
	if sz.x <= 4.0 or sz.y <= 4.0:
		return
	var t := ThemeManager.get_theme_data()
	var spots: Array = t["spotlights"]
	var accent: Color = t["accent"]
	var accent2: Color = t["accent_2"]
	var sp_col: Color = t["star_power"]

	var kp := kick_pulse * light_scale
	var snp := snare_pulse * light_scale
	var cyp := cymbal_pulse * light_scale

	# 1. Arena Sky / Stage Backdrop Gradient + Kick reactive radial glow
	var top_c: Color = t["bg_top"].lightened(kp * 0.08 + snp * 0.06)
	var bot_c: Color = t["bg_bottom"].lightened(kp * 0.14)
	if star_power_active:
		bot_c = bot_c.lerp(Color(sp_col.r * 0.32, sp_col.g * 0.32, sp_col.b * 0.42), 0.55)
	_beam_poly[0] = Vector2(0, 0)
	_beam_poly[1] = Vector2(sz.x, 0)
	_beam_poly[2] = Vector2(sz.x, sz.y)
	_beam_poly[3] = Vector2(0, sz.y)
	_beam_cols[0] = top_c
	_beam_cols[1] = top_c
	_beam_cols[2] = bot_c
	_beam_cols[3] = bot_c
	draw_polygon(_beam_poly, _beam_cols)

	var horizon_y := sz.y * 0.64

	# 2. LED Equalizer Backdrop Wall (Left & Right wings behind stage)
	var wall_top := sz.y * 0.16
	var wall_h := sz.y * 0.42
	for side in range(2):
		var start_x := sz.x * 0.03 if side == 0 else sz.x * 0.73
		var span_w := sz.x * 0.24
		var bar_w := span_w / 8.0 - 4.0
		for b in range(8):
			var eq_idx := b if side == 0 else (15 - b)
			var lv := clampf(_eq_bars[eq_idx] + kp * 0.22, 0.05, 1.0)
			var bx := start_x + float(b) * (bar_w + 4.0)
			var bh := wall_h * lv
			var bcol: Color = spots[(b + side) % spots.size()]
			if star_power_active:
				bcol = sp_col
			draw_rect(Rect2(bx, wall_top, bar_w, wall_h), Color(bcol.r, bcol.g, bcol.b, 0.06), true)
			draw_rect(Rect2(bx, wall_top + wall_h - bh, bar_w, bh), Color(bcol.r, bcol.g, bcol.b, 0.28 + kp * 0.22), true)
			# Bright LED cap
			draw_rect(Rect2(bx, wall_top + wall_h - bh - 3.0, bar_w, 3.5), Color(1.0, 1.0, 1.0, 0.72), true)

	# 3. Kick Drum Shockwave Halos from Stage Center & Subwoofers
	if kp > 0.04:
		var ring_r := (1.25 - minf(1.2, kick_pulse)) * sz.x * 0.44 + sz.x * 0.08
		var ring_a := clampf(kp * 0.42, 0.0, 0.55)
		var rcol := sp_col if star_power_active else accent
		draw_arc(Vector2(sz.x * 0.5, horizon_y * 0.72), ring_r, 0.0, TAU, 48, Color(rcol.r, rcol.g, rcol.b, ring_a), 4.0 + kp * 5.0)
		draw_arc(Vector2(sz.x * 0.5, horizon_y * 0.72), ring_r * 0.65, 0.0, TAU, 40, Color(accent2.r, accent2.g, accent2.b, ring_a * 0.7), 2.5)

	# 4. Left & Right Concert Subwoofer Speaker Stacks (thump scale on kick!)
	for side in range(2):
		var sx := sz.x * 0.11 if side == 0 else sz.x * 0.89
		var sw := sz.x * 0.095
		var sh := sz.y * 0.30
		var sy := horizon_y - sh * 0.75
		var cab_rect := Rect2(sx - sw * 0.5, sy, sw, sh)
		draw_rect(cab_rect, Color(0.05, 0.05, 0.08, 0.92), true)
		draw_rect(cab_rect, Color(accent.r, accent.g, accent.b, 0.45 + kp * 0.4), false, 2.0)
		# Dual woofer cones pulsing with kick drum
		for c_idx in range(2):
			var cy := sy + sh * (0.28 if c_idx == 0 else 0.72)
			var base_r := minf(sw, sh * 0.45) * 0.36
			var cone_r := base_r * (1.0 + kp * 0.24)
			var wcol: Color = sp_col if star_power_active else spots[(side + c_idx) % spots.size()]
			draw_circle(Vector2(sx, cy), cone_r * 1.15, Color(wcol.r, wcol.g, wcol.b, 0.18 + kp * 0.35))
			draw_arc(Vector2(sx, cy), cone_r, 0.0, TAU, 28, Color(wcol.r, wcol.g, wcol.b, 0.85), 3.0)
			draw_circle(Vector2(sx, cy), cone_r * 0.38, Color(0.95, 0.98, 1.0, 0.45 + kp * 0.45))

	# 5. Overhead Concert Truss Rig & 8 Moving-Head Volumetric Spotlights
	var truss_y := sz.y * 0.055
	draw_line(Vector2(sz.x * 0.04, truss_y), Vector2(sz.x * 0.96, truss_y), Color(0.35, 0.40, 0.52, 0.75), 4.0)
	draw_line(Vector2(sz.x * 0.04, truss_y + 12.0), Vector2(sz.x * 0.96, truss_y + 12.0), Color(0.25, 0.30, 0.42, 0.65), 2.5)

	var num_lights := 8
	for i in range(num_lights):
		var frac := (float(i) + 0.5) / float(num_lights)
		var lx := lerpf(sz.x * 0.07, sz.x * 0.93, frac)
		var ly := truss_y + 10.0
		var lcol: Color = sp_col if star_power_active else spots[i % spots.size()]

		# Sweep angle modulated only while music is actively playing
		var speed := 1.35 + float(combo_level) * 0.28
		var sweep := (sin(_time * speed + float(i) * 0.92) * (0.38 + kp * 0.18)) if _has_audio_energy else 0.0
		var base_tilt := (0.5 - frac) * 0.48
		var angle := base_tilt + sweep

		var beam_len := sz.y * 0.92
		var dir := Vector2(sin(angle), cos(angle))
		var perp := Vector2(dir.y, -dir.x)
		var top_w := 7.0 + kp * 5.0
		var bot_w := sz.x * (0.052 + kp * 0.042 + snp * 0.025)

		var base_a := 0.24 if _has_audio_energy else 0.12
		var alpha_top := clampf((base_a + kp * 0.36 + snp * 0.22) * light_scale, 0.04, 0.82)
		_beam_poly[0] = Vector2(lx, ly) - perp * top_w
		_beam_poly[1] = Vector2(lx, ly) + perp * top_w
		_beam_poly[2] = Vector2(lx, ly) + dir * beam_len + perp * bot_w
		_beam_poly[3] = Vector2(lx, ly) + dir * beam_len - perp * bot_w

		_beam_cols[0] = Color(lcol.r, lcol.g, lcol.b, alpha_top)
		_beam_cols[1] = Color(lcol.r, lcol.g, lcol.b, alpha_top)
		_beam_cols[2] = Color(lcol.r, lcol.g, lcol.b, 0.0)
		_beam_cols[3] = Color(lcol.r, lcol.g, lcol.b, 0.0)
		draw_polygon(_beam_poly, _beam_cols)

		# Lamp head flare & core
		var flare_r := 7.5 + kp * 9.0 + snp * 6.0
		draw_circle(Vector2(lx, ly), flare_r * 1.7, Color(lcol.r, lcol.g, lcol.b, clampf((0.22 if not _has_audio_energy else 0.34) + kp * 0.4, 0.1, 0.85)))
		draw_circle(Vector2(lx, ly), flare_r * 0.58, Color(1.0, 1.0, 1.0, 0.88))

	# 6. Cymbal / Snare Criss-Crossing Laser Show (only during active music)
	if _has_audio_energy and (cyp > 0.08 or snp > 0.12 or star_power_active):
		var laser_alpha := clampf(maxf(cyp * 0.65, snp * 0.75) + (0.35 if star_power_active else 0.0), 0.0, 0.85) * light_scale
		var num_lasers := 6
		for l in range(num_lasers):
			var emitter_x := sz.x * (0.18 if (l % 2 == 0) else 0.82)
			var emitter_y := truss_y + 14.0
			var spread := sin(_time * 4.5 + float(l + _laser_seed) * 1.15) * sz.x * 0.45
			var target := Vector2(sz.x * 0.5 + spread, sz.y * 0.95)
			var lc: Color = sp_col if star_power_active else spots[(l + _laser_seed) % spots.size()]
			draw_line(Vector2(emitter_x, emitter_y), target, Color(lc.r, lc.g, lc.b, laser_alpha), 2.2 + snp * 2.0)

	# 7. Snare Blinder Strobe Flash (only during active music)
	if _has_audio_energy and snp > 0.15:
		var blinder_a := clampf((snp - 0.15) * 0.22 * light_scale, 0.0, 0.24)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 0.98, 1.0, blinder_a), true)
		for b in range(5):
			var bx := lerpf(sz.x * 0.15, sz.x * 0.85, float(b) / 4.0)
			draw_circle(Vector2(bx, truss_y + 12.0), 18.0 * snp, Color(1.0, 1.0, 0.95, clampf(snp * 0.55, 0.0, 0.75)))

	# 8. Concert Crowd Silhouettes at Bottom Edge
	var crowd_base_y := sz.y * 0.985
	for i in range(34):
		var frac := float(i) / 33.0
		if (not menu_idle_mode) and frac > 0.16 and frac < 0.84:
			continue
		var cx := frac * sz.x
		var phase := _crowd_heads[i]
		var bounce := (absf(sin(_time * 5.2 + phase * TAU)) * (6.0 + kp * 15.0)) if _has_audio_energy else 0.0
		var head_y := crowd_base_y - 18.0 - bounce
		var sil_col := Color(0.02, 0.01, 0.04, 0.88)
		draw_circle(Vector2(cx, head_y + 20.0), 15.0, sil_col)
		draw_circle(Vector2(cx, head_y), 8.0, sil_col)
		if _has_audio_energy and (i + int(_time * 2.0)) % 4 == 0 and (kp > 0.25 or combo_level >= 3 or star_power_active):
			draw_line(Vector2(cx - 7.0, head_y + 8.0), Vector2(cx - 11.0, head_y - 12.0 - kp * 7.0), sil_col, 3.0)
			draw_line(Vector2(cx + 7.0, head_y + 8.0), Vector2(cx + 11.0, head_y - 12.0 - kp * 7.0), sil_col, 3.0)
