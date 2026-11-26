class_name PlanetView
extends Node3D
## 행성 메시: 타일마다 육각/오각 기둥(윗면 + 낮은 이웃 쪽 벽), 강 리본, 바람 화살표, 선택 테두리

enum Mode { BIOME, ELEVATION, TEMPERATURE, PRECIP, PLATES, WIND }

var hs: HexSphere
var gen: WorldGen
var exaggeration: float = 1.0
var mode: int = Mode.BIOME

var tile_radius := PackedFloat32Array()
var _arrays: Array = []
var _vert_tile := PackedInt32Array()
var _vert_shade := PackedFloat32Array()

var terrain_mi := MeshInstance3D.new()
var river_mi := MeshInstance3D.new()
var wind_mi := MeshInstance3D.new()
var hover_mi := MeshInstance3D.new()
var atmo_mi := MeshInstance3D.new()
var terrain_mesh := ArrayMesh.new()


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.92
	mat.metallic_specular = 0.15
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	terrain_mi.material_override = mat
	terrain_mi.mesh = terrain_mesh
	add_child(terrain_mi)

	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color("2e6b9c")
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	river_mi.material_override = rmat
	add_child(river_mi)

	var wmat := StandardMaterial3D.new()
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.vertex_color_use_as_albedo = true
	wind_mi.material_override = wmat
	wind_mi.visible = false
	add_child(wind_mi)

	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.albedo_color = Color("f2d27a")
	hmat.no_depth_test = true
	hover_mi.material_override = hmat
	add_child(hover_mi)

	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, blend_add, cull_back, depth_draw_never;
void fragment() {
	float f = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	ALBEDO = vec3(0.42, 0.62, 0.95) * f * 0.9;
}
"""
	var am := ShaderMaterial.new()
	am.shader = sh
	var sph := SphereMesh.new()
	sph.radius = 1.07
	sph.height = 2.14
	sph.radial_segments = 96
	sph.rings = 48
	atmo_mi.mesh = sph
	atmo_mi.material_override = am
	add_child(atmo_mi)


func radius_for(i: int) -> float:
	var e: float = gen.elevation[i]
	if gen.is_lake[i] == 1:
		e = gen.filled[i]
	if e <= 0.0:
		return 1.0
	return 1.0 + e * 0.045 * exaggeration + 0.0015


## 칸 가운데의 실제 표면 높이 (구릉/산지는 봉우리 높이)
func surface_radius(i: int) -> float:
	var rel: int = gen.relief[i]
	if rel == 0:
		return tile_radius[i]
	return tile_radius[i] + (0.012 if rel == 2 else 0.0038) * maxf(exaggeration, 0.2)


func rebuild() -> void:
	tile_radius.resize(hs.count)
	for i in hs.count:
		tile_radius[i] = radius_for(i)
	_build_terrain()
	_build_rivers()
	_build_wind()
	set_hover(-1)


func _build_terrain() -> void:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	_vert_tile = PackedInt32Array()
	_vert_shade = PackedFloat32Array()
	var idx := PackedInt32Array()
	for i in hs.count:
		var c: Vector3 = hs.centers[i]
		var r: float = tile_radius[i]
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var base: int = pos.size()
		pos.append(c * r)
		nrm.append(c)
		_vert_tile.append(i)
		_vert_shade.append(1.0)
		for k in deg:
			pos.append(hs.corner_list[off + k] * r)
			nrm.append(c)
			_vert_tile.append(i)
			_vert_shade.append(0.97)
		var rel: int = gen.relief[i]
		if rel == 0:
			for k in deg:
				idx.append(base)
				idx.append(base + 1 + (k + 1) % deg)
				idx.append(base + 1 + k)
		else:
			# 산지와 구릉은 가운데를 솟게 해서 각진 봉우리로 보이게 한다
			var peak: Vector3 = c * surface_radius(i)
			pos[base] = peak
			for k in deg:
				var a: Vector3 = hs.corner_list[off + k] * r
				var b: Vector3 = hs.corner_list[off + (k + 1) % deg] * r
				var fn: Vector3 = (b - peak).cross(a - peak).normalized()
				if fn.dot(c) < 0.0:
					fn = -fn
				var v0: int = pos.size()
				pos.append_array([peak, b, a])
				nrm.append_array([fn, fn, fn])
				_vert_tile.append_array([i, i, i])
				_vert_shade.append_array([1.08 if rel == 2 else 1.0, 0.95, 0.95])
				idx.append_array([v0, v0 + 1, v0 + 2])
		# 낮은 이웃 쪽으로 벽
		for k in deg:
			var j: int = hs.nb_list[off + k]
			var rj: float = tile_radius[j]
			if rj >= r - 1e-6:
				continue
			var a: Vector3 = hs.corner_list[off + k]
			var b: Vector3 = hs.corner_list[off + (k + 1) % deg]
			var wn: Vector3 = ((a + b) * 0.5 - c).normalized()
			var w0: int = pos.size()
			pos.append(a * r)
			pos.append(b * r)
			pos.append(b * rj)
			pos.append(a * rj)
			for _q in 4:
				nrm.append(wn)
				_vert_tile.append(i)
			_vert_shade.append(0.82)
			_vert_shade.append(0.82)
			_vert_shade.append(0.62)
			_vert_shade.append(0.62)
			idx.append_array([w0, w0 + 1, w0 + 2, w0, w0 + 2, w0 + 3])
	_arrays = []
	_arrays.resize(Mesh.ARRAY_MAX)
	_arrays[Mesh.ARRAY_VERTEX] = pos
	_arrays[Mesh.ARRAY_NORMAL] = nrm
	_arrays[Mesh.ARRAY_INDEX] = idx
	recolor()


func recolor() -> void:
	var tile_col := PackedColorArray()
	tile_col.resize(hs.count)
	for i in hs.count:
		tile_col[i] = tile_color(i)
	var cols := PackedColorArray()
	cols.resize(_vert_tile.size())
	for v in _vert_tile.size():
		var col: Color = tile_col[_vert_tile[v]]
		var s: float = _vert_shade[v]
		cols[v] = Color(col.r * s, col.g * s, col.b * s)
	_arrays[Mesh.ARRAY_COLOR] = cols
	terrain_mesh.clear_surfaces()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)


func _hash01(i: int) -> float:
	var h: int = (i * 73856093) ^ (gen.seed_value * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0


func tile_color(i: int) -> Color:
	match mode:
		Mode.BIOME:
			var col: Color = WorldGen.BIOME_COLORS[gen.biome[i]]
			var j: float = (_hash01(i) - 0.5) * 0.06
			if gen.elevation[i] >= 0.0 and gen.is_lake[i] == 0:
				if gen.relief[i] == 2 and gen.biome[i] != WorldGen.B.SNOW_PEAK and gen.biome[i] != WorldGen.B.ICE:
					col = col.lerp(Color("8c806b"), 0.45)
				elif gen.relief[i] == 1:
					col = col.darkened(0.06)
			else:
				j = 0.0
				col = col.lerp(Color("0f2236"), clampf(-gen.elevation[i] - 0.5, 0.0, 0.5))
			return Color(col.r + j, col.g + j, col.b + j)
		Mode.ELEVATION:
			return elevation_color(gen.height_m(i))
		Mode.TEMPERATURE:
			return temp_color(gen.temperature[i])
		Mode.PRECIP:
			if gen.elevation[i] < 0.0:
				return Color("27374a").lerp(Color("3d5f80"), clampf(gen.precip[i] / 2500.0, 0.0, 1.0))
			return precip_color(gen.precip[i])
		Mode.PLATES:
			var pc: Color = gen.plate_color[gen.plate[i]]
			if gen.plate_oceanic[gen.plate[i]] == 1:
				pc = pc.darkened(0.35)
			var bd: float = gen.boundary[i]
			if bd > 0.05:
				pc = pc.lerp(Color("d1392b"), clampf(bd * 1.5, 0.3, 0.9))
			elif bd < -0.05:
				pc = pc.lerp(Color("37c6d8"), clampf(-bd * 1.5, 0.3, 0.9))
			return pc
		Mode.WIND:
			var pv: float = clampf(gen.pressure[i] * 0.5 + 0.5, 0.0, 1.0)
			var c2: Color = Color("3c5a8a").lerp(Color("c2a25c"), pv)
			if gen.elevation[i] >= 0.0:
				c2 = c2.lightened(0.15)
			return c2
	return Color.MAGENTA


static func elevation_color(h: float) -> Color:
	if h < 0.0:
		return Color("8fc3d6").lerp(Color("102a47"), clampf(-h / 6000.0, 0.0, 1.0))
	var stops := [[0.0, Color("4f7d3d")], [400.0, Color("8aa457")], [1000.0, Color("d6c97c")],
		[2000.0, Color("b0804a")], [3500.0, Color("7d5a43")], [5500.0, Color("f2f0ea")]]
	return _ramp(stops, h)


static func temp_color(t: float) -> Color:
	var stops := [[-30.0, Color("3b3f9e")], [-10.0, Color("6fa6d6")], [0.0, Color("e8f0f2")],
		[12.0, Color("e9d27a")], [22.0, Color("e2873c")], [32.0, Color("a8281f")]]
	return _ramp(stops, t)


static func precip_color(p: float) -> Color:
	var stops := [[0.0, Color("c9a566")], [300.0, Color("d9cc8a")], [700.0, Color("9bbd63")],
		[1400.0, Color("3f8f4d")], [2400.0, Color("2a6f8f")], [3500.0, Color("2a3f8f")]]
	return _ramp(stops, p)


static func _ramp(stops: Array, v: float) -> Color:
	if v <= stops[0][0]:
		return stops[0][1]
	for s in range(1, stops.size()):
		if v <= stops[s][0]:
			var a: float = stops[s - 1][0]
			var b: float = stops[s][0]
			return (stops[s - 1][1] as Color).lerp(stops[s][1], (v - a) / (b - a))
	return stops[stops.size() - 1][1]


func _build_rivers() -> void:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	var max_flow: float = 1.0
	for i in hs.count:
		if gen.is_river[i] == 1:
			max_flow = maxf(max_flow, gen.flow[i])
	for i in hs.count:
		if gen.is_river[i] == 0:
			continue
		var d: int = gen.downstream[i]
		if d < 0:
			continue
		var w: float = hs.spacing * (0.05 + 0.16 * sqrt(gen.flow[i] / max_flow))
		var ci: Vector3 = hs.centers[i]
		var cd: Vector3 = hs.centers[d]
		var mid: Vector3 = ((ci + cd) * 0.5).normalized()
		var lift: float = 0.0015
		var si: float = surface_radius(i) + lift
		var ri: float = tile_radius[i] + lift
		var rd: float = tile_radius[d] + lift
		var sd: float = surface_radius(d) + lift
		_ribbon(pos, idx, ci * si, mid * ri, w)
		if absf(ri - rd) > 1e-5:
			_ribbon(pos, idx, mid * ri, mid * rd, w)
		if gen.is_water(d):
			_ribbon(pos, idx, mid * rd, ((mid + cd) * 0.5).normalized() * rd, w)
		else:
			_ribbon(pos, idx, mid * rd, cd * sd, w)
		# 이음매를 메우는 작은 원판
		_disc(pos, idx, ci * si, ci, w * 0.5)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	river_mi.mesh = m


func _ribbon(pos: PackedVector3Array, idx: PackedInt32Array, a: Vector3, b: Vector3, w: float) -> void:
	var dir: Vector3 = b - a
	if dir.length_squared() < 1e-12:
		return
	var up: Vector3 = ((a + b) * 0.5).normalized()
	var side: Vector3 = dir.cross(up)
	if side.length_squared() < 1e-12:
		side = up.cross(Vector3.UP if absf(up.y) < 0.9 else Vector3.RIGHT)
	side = side.normalized() * w * 0.5
	var s: int = pos.size()
	pos.append_array([a - side, a + side, b + side, b - side])
	idx.append_array([s, s + 1, s + 2, s, s + 2, s + 3])


func _disc(pos: PackedVector3Array, idx: PackedInt32Array, c: Vector3, nrm: Vector3, r: float) -> void:
	var t: Vector3 = nrm.cross(Vector3.UP if absf(nrm.y) < 0.9 else Vector3.RIGHT).normalized()
	var b: Vector3 = nrm.cross(t)
	var s: int = pos.size()
	pos.append(c)
	for k in 6:
		var a: float = TAU * k / 6.0
		pos.append(c + (t * cos(a) + b * sin(a)) * r)
	for k in 6:
		idx.append_array([s, s + 1 + k, s + 1 + (k + 1) % 6])


func _build_wind() -> void:
	var pos := PackedVector3Array()
	var cols := PackedColorArray()
	var step: int = maxi(1, int(pow(4.0, hs.level - 3)))
	var len: float = hs.spacing * 0.9 * maxf(1.0, sqrt(float(step)))
	for i in range(0, hs.count, step):
		var w: Vector3 = gen.wind[i]
		var spd: float = w.length()
		if spd < 0.05:
			continue
		var c: Vector3 = hs.centers[i] * (surface_radius(i) + 0.004)
		var dirv: Vector3 = w.normalized()
		var tip: Vector3 = c + dirv * len * (0.4 + 0.6 * spd)
		var side: Vector3 = dirv.cross(hs.centers[i]).normalized() * len * 0.18
		var back: Vector3 = tip - dirv * len * 0.3
		var col := Color(1, 1, 1).lerp(Color("ffd36b"), spd)
		pos.append_array([c, tip, tip, back + side, tip, back - side])
		for _q in 6:
			cols.append(col)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_COLOR] = cols
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	wind_mi.mesh = m


func set_hover(i: int) -> void:
	if i < 0:
		hover_mi.mesh = null
		return
	var im := ImmediateMesh.new()
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	var r: float = tile_radius[i] + 0.002
	for k in deg + 1:
		im.surface_add_vertex(hs.corner_list[off + k % deg] * r)
	im.surface_end()
	hover_mi.mesh = im
