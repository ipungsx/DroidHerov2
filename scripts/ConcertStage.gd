class_name ConcertStage
extends Control

# 60 FPS Multi-Visualizer Background Engine for DroidHeroV2:
# Supports 6 selectable music visualizers + optional Flashing Lights toggle for slow songs:
# - concert_arena   : Moving-head spotlights, 16-band LED wall, subwoofers, lasers & blinders
# - neon_waveform   : Dual stereo glowing oscilloscope waves + synth horizon grid
# - radial_spectrum : 360-degree circular neon audio spectrum sunburst + orbiting beat dots
# - cyber_rain      : Vertical neon digital rain streaks + bass-reactive scanwaves
# - plasma_aurora   : Smooth flowing northern-lights ribbons + gentle drifting embers
# - minimal_dark    : Clean dark studio backdrop with soft ambient vignette

const VISUALIZER_IDS: Array[String] = [
	"concert_arena",
	"neon_waveform",
	"radial_spectrum",
	"cyber_rain",
	"plasma_aurora",
	"minimal_dark"
]

const VISUALIZER_NAMES: Dictionary = {
	"concert_arena": "CONCERT ARENA",
	"neon_waveform": "NEON WAVEFORM",
	"radial_spectrum": "RADIAL SPECTRUM",
	"cyber_rain": "CYBER RAIN",
	"plasma_aurora": "PLASMA AURORA",
	"minimal_dark": "MINIMAL DARK"
}

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
var _flash_enabled: bool = true

var _time: float = 0.0
var _spectrum: AudioEffectSpectrumAnalyzerInstance
var _eq_bars: PackedFloat32Array = PackedFloat32Array()
var _prev_sub_energy: float = 0.0
var _prev_snare_energy: float = 0.0
var _beat_cooldown: float = 0.0
var _snare_cooldown: float = 0.0
var _laser_seed: int = 0

# Preallocated draw buffers for zero-GC 60fps rendering
var _beam_poly: PackedVector2Array = PackedVector2Array()
var _beam_cols: PackedColorArray = PackedColorArray()
var _crowd_heads: PackedFloat32Array = PackedFloat32Array()
var _rain_seeds: PackedFloat32Array = PackedFloat32Array()

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_eq_bars.resize(16)
	_eq_bars.fill(0.05)
	_beam_poly.resize(4)
	_beam_cols.resize(4)
	_crowd_heads.resize(34)
	for i in range(34):
		_crowd_heads[i] = fmod(float(i) * 0.37, 1.0)
	_rain_seeds.resize(28)
	for i in range(28):
		_rain_seeds[i] = fmod(float(i) * 0.6180339 + 0.13, 1.0)
	_spectrum = GameState.get_music_spectrum()
	light_scale = float(GameState.settings.get("light_intensity", 1.0))

func trigger_drum(drum_type: int, strength: float = 1.0) -> void:
	if not music_playing:
		return
	if not bool(GameState.settings.get("stage_lights_flash", true)):
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
	_flash_enabled = bool(GameState.settings.get("stage_lights_flash", true))

	# Smooth decay of drum light envelopes
	kick_pulse = maxf(0.0, kick_pulse - delta * 4.6)
	snare_pulse = maxf(0.0, snare_pulse - delta * 6.4)
	cymbal_pulse = maxf(0.0, cymbal_pulse - delta * 5.2)
	_beat_cooldown = maxf(0.0, _beat_cooldown - delta)
	_snare_cooldown = maxf(0.0, _snare_cooldown - delta)

	if not _flash_enabled:
		kick_pulse = 0.0
		snare_pulse = 0.0
		cymbal_pulse = 0.0

	if _spectrum == null:
		_spectrum = GameState.get_music_spectrum()

	var audio_active := false
	if music_playing and _spectrum != null:
		var sub_mag := _spectrum.get_magnitude_for_frequency_range(35.0, 135.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
		var low_mid := _spectrum.get_magnitude_for_frequency_range(160.0, 360.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE).length()
		var snap_hi := _spectrum.get_magnitude_for_frequency_range(1800.0, 4800.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_MAX).length()
		var hat_hi := _spectrum.get_magnitude_for_frequency_range(5500.0, 12000.0, AudioEffectSpectrumAnalyzerInstance.MAGNITUDE_AVERAGE).length()

		if sub_mag > 0.004 or low_mid > 0.004 or snap_hi > 0.004:
			audio_active = true
			if _flash_enabled:
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
			_eq_bars[i] = lerpf(_eq_bars[i], target, delta * 12.0)
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

	var kp := (kick_pulse * light_scale) if _flash_enabled else 0.0
	var snp := (snare_pulse * light_scale) if _flash_enabled else 0.0
	var cyp := (cymbal_pulse * light_scale) if _flash_enabled else 0.0

	# 1. Backdrop Gradient (calm & steady when flashing lights are OFF or silent)
	var top_c: Color = t["bg_top"].lightened(kp * 0.08 + snp * 0.06)
	var bot_c: Color = t["bg_bottom"].lightened(kp * 0.12)
	if star_power_active:
		bot_c = bot_c.lerp(Color(sp_col.r * 0.30, sp_col.g * 0.30, sp_col.b * 0.42), 0.55)
	_beam_poly[0] = Vector2(0, 0)
	_beam_poly[1] = Vector2(sz.x, 0)
	_beam_poly[2] = Vector2(sz.x, sz.y)
	_beam_poly[3] = Vector2(0, sz.y)
	_beam_cols[0] = top_c
	_beam_cols[1] = top_c
	_beam_cols[2] = bot_c
	_beam_cols[3] = bot_c
	draw_polygon(_beam_poly, _beam_cols)

	var viz := str(GameState.settings.get("visualizer", "concert_arena"))
	if menu_idle_mode:
		# On menu screens, always show a subtle calm version of the chosen visualizer
		pass

	match viz:
		"neon_waveform":
			_draw_viz_waveform(sz, t, spots, accent, accent2, sp_col, kp)
		"radial_spectrum":
			_draw_viz_radial(sz, t, spots, accent, accent2, sp_col, kp)
		"cyber_rain":
			_draw_viz_cyber_rain(sz, t, spots, accent, accent2, sp_col, kp)
		"plasma_aurora":
			_draw_viz_aurora(sz, t, spots, accent, accent2, sp_col)
		"minimal_dark":
			_draw_viz_minimal(sz, accent, sp_col)
		_:
			_draw_viz_concert_arena(sz, t, spots, accent, accent2, sp_col, kp, snp, cyp)

func _draw_viz_concert_arena(sz: Vector2, _t: Dictionary, spots: Array, accent: Color, accent2: Color, sp_col: Color, kp: float, snp: float, cyp: float) -> void:
	var horizon_y := sz.y * 0.64

	# LED Equalizer Backdrop Wall
	var wall_top := sz.y * 0.16
	var wall_h := sz.y * 0.42
	for side in range(2):
		var start_x := sz.x * 0.03 if side == 0 else sz.x * 0.73
		var span_w := sz.x * 0.24
		var bar_w := span_w / 8.0 - 4.0
		for b in range(8):
			var eq_idx := b if side == 0 else (15 - b)
			var lv := clampf(_eq_bars[eq_idx] + kp * 0.20, 0.05, 1.0)
			var bx := start_x + float(b) * (bar_w + 4.0)
			var bh := wall_h * lv
			var bcol: Color = sp_col if star_power_active else spots[(b + side) % spots.size()]
			draw_rect(Rect2(bx, wall_top, bar_w, wall_h), Color(bcol.r, bcol.g, bcol.b, 0.05), true)
			draw_rect(Rect2(bx, wall_top + wall_h - bh, bar_w, bh), Color(bcol.r, bcol.g, bcol.b, 0.26 + kp * 0.20), true)
			draw_rect(Rect2(bx, wall_top + wall_h - bh - 3.0, bar_w, 3.5), Color(1.0, 1.0, 1.0, 0.68), true)

	# Kick Drum Shockwave Halos (only if flashing lights enabled)
	if _flash_enabled and kp > 0.04:
		var ring_r := (1.25 - minf(1.2, kick_pulse)) * sz.x * 0.44 + sz.x * 0.08
		var ring_a := clampf(kp * 0.40, 0.0, 0.52)
		var rcol := sp_col if star_power_active else accent
		draw_arc(Vector2(sz.x * 0.5, horizon_y * 0.72), ring_r, 0.0, TAU, 48, Color(rcol.r, rcol.g, rcol.b, ring_a), 4.0 + kp * 4.5)
		draw_arc(Vector2(sz.x * 0.5, horizon_y * 0.72), ring_r * 0.65, 0.0, TAU, 40, Color(accent2.r, accent2.g, accent2.b, ring_a * 0.7), 2.5)

	# Dual Subwoofer Speaker Stacks
	for side in range(2):
		var sx := sz.x * 0.11 if side == 0 else sz.x * 0.89
		var sw := sz.x * 0.095
		var sh := sz.y * 0.28
		var sy := horizon_y - sh * 0.75
		var cab_rect := Rect2(sx - sw * 0.5, sy, sw, sh)
		draw_rect(cab_rect, Color(0.05, 0.05, 0.08, 0.90), true)
		draw_rect(cab_rect, Color(accent.r, accent.g, accent.b, 0.42 + kp * 0.35), false, 2.0)
		for c_idx in range(2):
			var cy := sy + sh * (0.28 if c_idx == 0 else 0.72)
			var base_r := minf(sw, sh * 0.45) * 0.36
			var cone_r := base_r * (1.0 + kp * 0.22)
			var wcol: Color = sp_col if star_power_active else spots[(side + c_idx) % spots.size()]
			draw_circle(Vector2(sx, cy), cone_r * 1.15, Color(wcol.r, wcol.g, wcol.b, 0.16 + kp * 0.30))
			draw_arc(Vector2(sx, cy), cone_r, 0.0, TAU, 28, Color(wcol.r, wcol.g, wcol.b, 0.82), 3.0)
			draw_circle(Vector2(sx, cy), cone_r * 0.38, Color(0.95, 0.98, 1.0, 0.42 + kp * 0.40))

	# Overhead Concert Truss & 8 Spotlights
	var truss_y := sz.y * 0.055
	draw_line(Vector2(sz.x * 0.04, truss_y), Vector2(sz.x * 0.96, truss_y), Color(0.35, 0.40, 0.52, 0.72), 4.0)
	draw_line(Vector2(sz.x * 0.04, truss_y + 12.0), Vector2(sz.x * 0.96, truss_y + 12.0), Color(0.25, 0.30, 0.42, 0.62), 2.5)

	var num_lights := 8
	for i in range(num_lights):
		var frac := (float(i) + 0.5) / float(num_lights)
		var lx := lerpf(sz.x * 0.07, sz.x * 0.93, frac)
		var ly := truss_y + 10.0
		var lcol: Color = sp_col if star_power_active else spots[i % spots.size()]

		var speed := (1.35 + float(combo_level) * 0.28) if _flash_enabled else 0.45
		var sweep := (sin(_time * speed + float(i) * 0.92) * (0.36 + kp * 0.16)) if _has_audio_energy else 0.0
		var angle := (0.5 - frac) * 0.48 + sweep

		var beam_len := sz.y * 0.90
		var dir := Vector2(sin(angle), cos(angle))
		var perp := Vector2(dir.y, -dir.x)
		var top_w := 7.0 + kp * 4.5
		var bot_w := sz.x * (0.052 + kp * 0.040 + snp * 0.022)

		var base_a := (0.22 if _has_audio_energy else 0.11) if _flash_enabled else 0.14
		var alpha_top := clampf((base_a + kp * 0.34 + snp * 0.20) * light_scale, 0.04, 0.78)
		_beam_poly[0] = Vector2(lx, ly) - perp * top_w
		_beam_poly[1] = Vector2(lx, ly) + perp * top_w
		_beam_poly[2] = Vector2(lx, ly) + dir * beam_len + perp * bot_w
		_beam_poly[3] = Vector2(lx, ly) + dir * beam_len - perp * bot_w
		_beam_cols[0] = Color(lcol.r, lcol.g, lcol.b, alpha_top)
		_beam_cols[1] = Color(lcol.r, lcol.g, lcol.b, alpha_top)
		_beam_cols[2] = Color(lcol.r, lcol.g, lcol.b, 0.0)
		_beam_cols[3] = Color(lcol.r, lcol.g, lcol.b, 0.0)
		draw_polygon(_beam_poly, _beam_cols)

		var flare_r := 7.0 + kp * 8.0 + snp * 5.0
		draw_circle(Vector2(lx, ly), flare_r * 1.6, Color(lcol.r, lcol.g, lcol.b, clampf(0.24 + kp * 0.36, 0.1, 0.80)))
		draw_circle(Vector2(lx, ly), flare_r * 0.55, Color(1.0, 1.0, 1.0, 0.85))

	# Lasers & Snare Strobe Blinders (ONLY when flashing lights are enabled + music active)
	if _flash_enabled and _has_audio_energy and (cyp > 0.08 or snp > 0.12 or star_power_active):
		var laser_alpha := clampf(maxf(cyp * 0.65, snp * 0.75) + (0.35 if star_power_active else 0.0), 0.0, 0.82) * light_scale
		for l in range(6):
			var emitter_x := sz.x * (0.18 if (l % 2 == 0) else 0.82)
			var spread := sin(_time * 4.5 + float(l + _laser_seed) * 1.15) * sz.x * 0.45
			var lc: Color = sp_col if star_power_active else spots[(l + _laser_seed) % spots.size()]
			draw_line(Vector2(emitter_x, truss_y + 14.0), Vector2(sz.x * 0.5 + spread, sz.y * 0.95), Color(lc.r, lc.g, lc.b, laser_alpha), 2.2 + snp * 2.0)

	if _flash_enabled and _has_audio_energy and snp > 0.15:
		var blinder_a := clampf((snp - 0.15) * 0.20 * light_scale, 0.0, 0.22)
		draw_rect(Rect2(Vector2.ZERO, sz), Color(1.0, 0.98, 1.0, blinder_a), true)

	# Menu Crowd Silhouettes
	if menu_idle_mode:
		var crowd_base_y := sz.y * 0.985
		for i in range(34):
			var cx := (float(i) / 33.0) * sz.x
			var bounce := (absf(sin(_time * 5.2 + _crowd_heads[i] * TAU)) * (8.0 + kp * 16.0)) if _has_audio_energy else 0.0
			var head_y := crowd_base_y - 22.0 - bounce
			var sil_col := Color(0.02, 0.01, 0.04, 0.88)
			draw_circle(Vector2(cx, head_y + 24.0), 19.0, sil_col)
			draw_circle(Vector2(cx, head_y), 10.0, sil_col)

func _draw_viz_waveform(sz: Vector2, _t: Dictionary, spots: Array, accent: Color, accent2: Color, sp_col: Color, kp: float) -> void:
	# Perspective synth grid + dual glowing stereo audio waveform ribbons
	var mid_y := sz.y * 0.36
	var grid_c := sp_col if star_power_active else accent
	for row in range(8):
		var frac := float(row) / 7.0
		var y := lerpf(mid_y, sz.y * 0.98, pow(frac, 1.6))
		draw_line(Vector2(0, y), Vector2(sz.x, y), Color(grid_c.r, grid_c.g, grid_c.b, 0.08 + frac * 0.16), 1.6)
	for col in range(-5, 6):
		var tx := sz.x * 0.5 + float(col) * sz.x * 0.08
		var bx := sz.x * 0.5 + float(col) * sz.x * 0.24
		draw_line(Vector2(tx, mid_y), Vector2(bx, sz.y), Color(grid_c.r, grid_c.g, grid_c.b, 0.12), 1.4)

	# Dual stereo oscilloscope ribbons
	var pts_count := 32
	for wave_idx in range(2):
		var base_y := sz.y * (0.24 if wave_idx == 0 else 0.31)
		var wcol: Color = sp_col if star_power_active else (accent if wave_idx == 0 else accent2)
		var prev_pt := Vector2(0, base_y)
		for i in range(pts_count + 1):
			var frac := float(i) / float(pts_count)
			var eq_val := _eq_bars[clampi(int(frac * 15.0), 0, 15)]
			var env := sin(frac * PI)
			var amp := (eq_val * 125.0 + kp * 35.0) * env * light_scale
			var y := base_y + sin(_time * (5.5 + float(wave_idx) * 2.2) + frac * 14.0) * amp
			var pt := Vector2(frac * sz.x, y)
			if i > 0:
				draw_line(prev_pt, pt, Color(wcol.r, wcol.g, wcol.b, 0.35), 9.0)
				draw_line(prev_pt, pt, Color(wcol.r, wcol.g, wcol.b, 0.92), 3.4)
			prev_pt = pt
	# Subtle top spectrum ticks
	for i in range(16):
		var bx := (float(i) + 0.5) / 16.0 * sz.x
		var bh := _eq_bars[i] * sz.y * 0.12
		var sc: Color = spots[i % spots.size()]
		draw_line(Vector2(bx, sz.y * 0.12), Vector2(bx, sz.y * 0.12 + bh), Color(sc.r, sc.g, sc.b, 0.45), 6.0)

func _draw_viz_radial(sz: Vector2, _t: Dictionary, spots: Array, accent: Color, accent2: Color, sp_col: Color, kp: float) -> void:
	# 360-degree neon circular audio spectrum sunburst behind the horizon
	var center := Vector2(sz.x * 0.5, sz.y * 0.28)
	var base_r := minf(sz.x, sz.y) * 0.16 * (1.0 + kp * 0.14)
	var main_c := sp_col if star_power_active else accent

	draw_circle(center, base_r * 1.45, Color(main_c.r, main_c.g, main_c.b, 0.10 + kp * 0.10))
	draw_arc(center, base_r, 0.0, TAU, 56, Color(main_c.r, main_c.g, main_c.b, 0.72), 4.0)
	draw_arc(center, base_r * 0.72, 0.0, TAU, 44, Color(accent2.r, accent2.g, accent2.b, 0.45), 2.5)

	var spokes := 32
	for i in range(spokes):
		var ang := (float(i) / float(spokes)) * TAU + _time * 0.35
		var eq := _eq_bars[i % 16]
		var bar_len := (16.0 + eq * 145.0 + kp * 28.0) * light_scale
		var dir := Vector2(cos(ang), sin(ang))
		var p0 := center + dir * (base_r + 6.0)
		var p1 := center + dir * (base_r + 6.0 + bar_len)
		var col: Color = sp_col if star_power_active else spots[i % spots.size()]
		draw_line(p0, p1, Color(col.r, col.g, col.b, 0.80), 5.5)
		draw_circle(p1, 3.8, Color(1.0, 1.0, 1.0, 0.85))

	# Orbiting beat particles
	for k in range(10):
		var oa := _time * (0.65 + float(k % 3) * 0.25) + float(k) * 0.628
		var orad := base_r * (1.7 + float(k % 4) * 0.38)
		var op := center + Vector2(cos(oa), sin(oa)) * orad
		var oc: Color = spots[k % spots.size()]
		draw_circle(op, 4.5 + kp * 3.0, Color(oc.r, oc.g, oc.b, 0.65))

func _draw_viz_cyber_rain(sz: Vector2, _t: Dictionary, spots: Array, accent: Color, _accent2: Color, sp_col: Color, kp: float) -> void:
	# Vertical neon digital rain streaks & bass scanwaves
	var cols_n := _rain_seeds.size()
	for i in range(cols_n):
		var seed_v := _rain_seeds[i]
		var rx := (float(i) + 0.5) / float(cols_n) * sz.x
		var eq := _eq_bars[i % 16]
		var spd := 0.32 + seed_v * 0.55 + eq * 0.45
		var head_y := fmod(_time * spd + seed_v * 4.7, 1.25) * sz.y
		var tail_len := (80.0 + eq * 180.0 + kp * 45.0) * light_scale
		var rc: Color = sp_col if star_power_active else spots[i % spots.size()]
		draw_line(Vector2(rx, head_y - tail_len), Vector2(rx, head_y), Color(rc.r, rc.g, rc.b, 0.42 + eq * 0.38), 3.6)
		draw_circle(Vector2(rx, head_y), 4.0, Color(1.0, 1.0, 1.0, 0.82))

	# Horizontal bass scanline pulse
	if _has_audio_energy:
		var scan_y := fmod(_time * 0.45, 1.0) * sz.y
		var sc := sp_col if star_power_active else accent
		draw_line(Vector2(0, scan_y), Vector2(sz.x, scan_y), Color(sc.r, sc.g, sc.b, 0.28 + kp * 0.25), 3.0)

func _draw_viz_aurora(sz: Vector2, _t: Dictionary, spots: Array, accent: Color, accent2: Color, sp_col: Color) -> void:
	# Smooth, non-blinking flowing aurora ribbons & gentle embers (ideal for slow songs!)
	var energy := 0.0
	for i in range(16):
		energy += _eq_bars[i]
	energy /= 16.0

	for band in range(3):
		var col: Color = sp_col if star_power_active else (accent if band == 0 else (accent2 if band == 1 else spots[2 % spots.size()]))
		var base_y := sz.y * (0.14 + float(band) * 0.14)
		var segs := 18
		for s in range(segs):
			var f0 := float(s) / float(segs)
			var f1 := float(s + 1) / float(segs)
			var y0 := base_y + sin(_time * (0.7 + float(band) * 0.22) + f0 * 5.2 + float(band)) * (45.0 + energy * 85.0)
			var y1 := base_y + sin(_time * (0.7 + float(band) * 0.22) + f1 * 5.2 + float(band)) * (45.0 + energy * 85.0)
			var band_h := 88.0 + energy * 95.0
			_beam_poly[0] = Vector2(f0 * sz.x, y0)
			_beam_poly[1] = Vector2(f1 * sz.x, y1)
			_beam_poly[2] = Vector2(f1 * sz.x, y1 + band_h)
			_beam_poly[3] = Vector2(f0 * sz.x, y0 + band_h)
			var a := clampf((0.18 + energy * 0.24) * light_scale, 0.06, 0.48)
			_beam_cols[0] = Color(col.r, col.g, col.b, 0.0)
			_beam_cols[1] = Color(col.r, col.g, col.b, 0.0)
			_beam_cols[2] = Color(col.r, col.g, col.b, a)
			_beam_cols[3] = Color(col.r, col.g, col.b, a)
			draw_polygon(_beam_poly, _beam_cols)

	# Gentle floating embers
	for i in range(18):
		var sd := _rain_seeds[i]
		var ex := fmod(sd * sz.x + sin(_time * 0.8 + float(i)) * 32.0 + sz.x, sz.x)
		var ey := sz.y * (1.0 - fmod(_time * (0.06 + sd * 0.08) + sd * 3.1, 1.0))
		var ec: Color = sp_col if star_power_active else spots[i % spots.size()]
		draw_circle(Vector2(ex, ey), 3.0 + sd * 3.0, Color(ec.r, ec.g, ec.b, 0.45))

func _draw_viz_minimal(sz: Vector2, accent: Color, sp_col: Color) -> void:
	# Clean dark studio backdrop with soft top ambient glow for pure note focus
	var c := sp_col if star_power_active else accent
	draw_circle(Vector2(sz.x * 0.5, sz.y * 0.18), sz.x * 0.42, Color(c.r, c.g, c.b, 0.08))
