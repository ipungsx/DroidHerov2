extends Node

# Procedural HD Texture Baker for 60fps High-Definition Gameplay Rendering:
# Generates mipmapped RGBA8 GPU textures at startup:
# - 8-facet 3D cut-jewel note gems in brushed metallic bezels (per lane + HOPO + Tap + Star Power)
# - HD carbon-weave & rosewood highway deck textures
# - Soft additive glow & spark sprites for sustain friction and hit shockwaves

var gem_strum: Array[Texture2D] = []
var gem_hopo: Array[Texture2D] = []
var gem_tap: Array[Texture2D] = []
var gem_star: Texture2D
var gem_star_hopo: Texture2D

var board_carbon_tex: Texture2D
var board_wood_tex: Texture2D
var board_obsidian_tex: Texture2D
var radial_glow_tex: Texture2D
var ring_shock_tex: Texture2D

func _ready() -> void:
	_bake_all_hd_assets()

func _bake_all_hd_assets() -> void:
	gem_strum.clear()
	gem_hopo.clear()
	gem_tap.clear()

	var lane_cols: Array[Color] = [
		Color(0.06, 0.98, 0.44), # Green
		Color(1.00, 0.18, 0.30), # Red
		Color(1.00, 0.88, 0.12), # Yellow
		Color(0.14, 0.66, 1.00), # Blue
		Color(1.00, 0.52, 0.08)  # Orange
	]

	for c in lane_cols:
		gem_strum.append(_bake_jewel_gem(128, 84, c, 0))
		gem_hopo.append(_bake_jewel_gem(128, 84, c, 1))
		gem_tap.append(_bake_jewel_gem(128, 84, c, 2))

	var sp_cyan := Color(0.18, 0.96, 1.0)
	gem_star = _bake_jewel_gem(128, 84, sp_cyan, 3)
	gem_star_hopo = _bake_jewel_gem(128, 84, sp_cyan, 4)

	board_carbon_tex = _bake_board_texture(128, 128, 0)
	board_wood_tex = _bake_board_texture(128, 128, 1)
	board_obsidian_tex = _bake_board_texture(128, 128, 2)
	radial_glow_tex = _bake_radial_glow(96)
	ring_shock_tex = _bake_shockwave_ring(128)

# mode: 0=strum, 1=hopo, 2=tap, 3=star, 4=star_hopo
func _bake_jewel_gem(w: int, h: int, base_col: Color, mode: int) -> Texture2D:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var cx := float(w) * 0.5
	var cy := float(h) * 0.52
	var rx := float(w) * 0.45
	var ry := float(h) * 0.41
	var light_dir := Vector3(-0.32, -0.52, 0.79).normalized()

	var idx := 0
	for py in range(h):
		var dy := (float(py) - cy) / ry
		var sh_dy := (float(py) - (cy + ry * 0.18)) / (ry * 1.04)
		for px in range(w):
			var dx := (float(px) - cx) / rx
			var r2 := dx * dx + dy * dy
			var sh_r2 := (dx * 0.96) * (dx * 0.96) + sh_dy * sh_dy

			var out_r := 0.0
			var out_g := 0.0
			var out_b := 0.0
			var out_a := 0.0

			if r2 <= 1.0:
				var r := sqrt(r2)
				# Anti-aliased outer edge
				var edge_aa := clampf((1.0 - r) * 28.0, 0.0, 1.0)

				if r > 0.80:
					# Brushed gunmetal / chrome metallic outer bezel
					var bt := (r - 0.80) / 0.20
					var nx := dx * 0.85
					var ny := dy * 0.85
					var nz := sqrt(maxf(0.05, 1.0 - nx * nx - ny * ny))
					var ndotl := maxf(0.0, nx * light_dir.x + ny * light_dir.y + nz * light_dir.z)
					var brush := 0.92 + 0.08 * sin(float(py) * 1.9 + float(px) * 0.25)
					var metal := (0.20 + 0.62 * pow(ndotl, 2.2)) * brush
					if mode == 3 or mode == 4:
						# Star Power silver-cyan glowing bezel
						out_r = lerpf(metal, 0.65, 0.35)
						out_g = lerpf(metal, 0.98, 0.45)
						out_b = lerpf(metal, 1.00, 0.55)
					elif mode == 2:
						# Tap note neon-tinted outer ring
						out_r = base_col.r * (0.55 + 0.55 * ndotl)
						out_g = base_col.g * (0.55 + 0.55 * ndotl)
						out_b = base_col.b * (0.55 + 0.55 * ndotl)
					else:
						# Classic metallic bezel with subtle inner color rim
						var rim_mix := clampf(1.0 - bt * 1.4, 0.0, 0.45)
						out_r = lerpf(metal, base_col.r * 0.9, rim_mix)
						out_g = lerpf(metal, base_col.g * 0.9, rim_mix)
						out_b = lerpf(metal, base_col.b * 0.9, rim_mix)
					out_a = edge_aa
				else:
					# Inner 8-facet cut jewel crown + flat top table
					var jr := r / 0.80
					var ang := atan2(dy, dx)
					# Quantize crown angle into 8 crisp jewel facets
					var sector: float = floorf((ang + PI) / (TAU / 8.0))
					var facet_ang: float = (sector + 0.5) * (TAU / 8.0) - PI
					var star_mod := 1.0
					if mode == 3 or mode == 4:
						star_mod = 0.88 + 0.14 * cos(ang * 5.0)

					var fn: Vector3
					if jr < 0.46 * star_mod:
						# Raised flat jewel table
						fn = Vector3(dx * 0.14, (dy + 0.08) * 0.14, 0.98).normalized()
					else:
						# Sloped 8-facet jewel crown catching stage light
						fn = Vector3(cos(facet_ang) * 0.62, sin(facet_ang) * 0.62, 0.78).normalized()

					var diff := maxf(0.08, fn.dot(light_dir))
					var half_v := (light_dir + Vector3(0, 0, 1)).normalized()
					var spec := pow(maxf(0.0, fn.dot(half_v)), 26.0)
					var core_glow := clampf(1.0 - jr * 0.72, 0.15, 1.0)

					var col := base_col
					if (mode == 1 or mode == 4) and jr < 0.56:
						# HOPO: Bright luminous pearl-white table crown (readable at high speed!)
						var hopo_t := clampf((0.56 - jr) * 5.5, 0.0, 1.0)
						col = col.lerp(Color(0.98, 0.99, 1.0), hopo_t * 0.92)
						spec += hopo_t * 0.35
					elif mode == 2 and jr < 0.62:
						# Tap Note: Dark obsidian core with glowing neon inner ring
						var ring_band := absf(jr - 0.50)
						if ring_band < 0.09:
							col = Color(1.0, 1.0, 1.0).lerp(base_col, 0.35)
							spec += 0.45
						else:
							col = base_col.darkened(0.72)

					out_r = clampf(col.r * (0.34 + 0.82 * diff + 0.25 * core_glow) + spec * 0.95, 0.0, 1.0)
					out_g = clampf(col.g * (0.34 + 0.82 * diff + 0.25 * core_glow) + spec * 0.95, 0.0, 1.0)
					out_b = clampf(col.b * (0.34 + 0.82 * diff + 0.25 * core_glow) + spec * 0.95, 0.0, 1.0)
					out_a = 1.0
			elif sh_r2 <= 1.0:
				# Soft grounded contact shadow underneath the 3D bezel
				var sr := sqrt(sh_r2)
				out_a = clampf((1.0 - sr) * 1.8, 0.0, 0.58)

			data[idx] = int(clampf(out_r * 255.0, 0.0, 255.0))
			data[idx + 1] = int(clampf(out_g * 255.0, 0.0, 255.0))
			data[idx + 2] = int(clampf(out_b * 255.0, 0.0, 255.0))
			data[idx + 3] = int(clampf(out_a * 255.0, 0.0, 255.0))
			idx += 4

	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _bake_board_texture(w: int, h: int, style: int) -> Texture2D:
	var data := PackedByteArray()
	data.resize(w * h * 4)
	var idx := 0
	for y in range(h):
		for x in range(w):
			var r := 0.06
			var g := 0.06
			var b := 0.12
			if style == 0:
				# Carbon-fiber diagonal micro-weave
				var cell := ((x / 4) + (y / 4)) % 2
				var sheen := 0.025 * sin(float(x) * 0.39) * cos(float(y) * 0.39)
				var base_v := (0.075 if cell == 0 else 0.048) + sheen
				r = base_v * 0.88
				g = base_v * 0.92
				b = base_v * 1.38
			elif style == 1:
				# Dark midnight rosewood guitar fretboard grain
				var grain := sin(float(x) * 0.55 + sin(float(y) * 0.09) * 2.4) * 0.5 + 0.5
				r = 0.11 + grain * 0.055
				g = 0.055 + grain * 0.028
				b = 0.045 + grain * 0.020
			else:
				# Brushed obsidian metal
				var streak := sin(float(y) * 0.85 + float(x) * 0.12) * 0.018
				r = 0.045 + streak
				g = 0.050 + streak
				b = 0.072 + streak
			data[idx] = int(clampf(r * 255.0, 0.0, 255.0))
			data[idx + 1] = int(clampf(g * 255.0, 0.0, 255.0))
			data[idx + 2] = int(clampf(b * 255.0, 0.0, 255.0))
			data[idx + 3] = 242
			idx += 4
	var img := Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, data)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)

func _bake_radial_glow(sz: int) -> Texture2D:
	var data := PackedByteArray()
	data.resize(sz * sz * 4)
	var c := float(sz) * 0.5
	var idx := 0
	for y in range(sz):
		var dy := (float(y) - c) / c
		for x in range(sz):
			var dx := (float(x) - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var a := pow(clampf(1.0 - d, 0.0, 1.0), 2.2)
			data[idx] = 255
			data[idx + 1] = 255
			data[idx + 2] = 255
			data[idx + 3] = int(clampf(a * 255.0, 0.0, 255.0))
			idx += 4
	var img := Image.create_from_data(sz, sz, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(img)

func _bake_shockwave_ring(sz: int) -> Texture2D:
	var data := PackedByteArray()
	data.resize(sz * sz * 4)
	var c := float(sz) * 0.5
	var idx := 0
	for y in range(sz):
		var dy := (float(y) - c) / c
		for x in range(sz):
			var dx := (float(x) - c) / c
			var d := sqrt(dx * dx + dy * dy)
			var ring := exp(-pow((d - 0.74) / 0.095, 2.0)) * clampf((1.0 - d) * 6.0, 0.0, 1.0)
			data[idx] = 255
			data[idx + 1] = 255
			data[idx + 2] = 255
			data[idx + 3] = int(clampf(ring * 255.0, 0.0, 255.0))
			idx += 4
	var img := Image.create_from_data(sz, sz, false, Image.FORMAT_RGBA8, data)
	return ImageTexture.create_from_image(img)

func get_board_texture(style_id: String) -> Texture2D:
	match style_id:
		"rosewood":
			return board_wood_tex
		"obsidian":
			return board_obsidian_tex
		_:
			return board_carbon_tex
