class_name PlanetView
extends Node3D
## 행성 메시.
## 각 타일의 꼭짓점은 그 점을 공유하는 세 타일 고도의 평균에 놓인다. 그래서 타일 사이에
## 단차가 생기지 않고, 고도 차이는 타일이 기울어진 모습으로 나타난다. 산은 따로 모양을
## 만들지 않고 높은 고도가 모여서 자연스럽게 산맥으로 보인다.
## 바다는 해저 지형 위에 반투명 수면 구를 덮고, 호수는 평평한 수면을 따로 그린다.

enum Mode { BIOME, ELEVATION, TEMPERATURE, PRECIP, PLATES, WIND, VEG }

const LAND_SCALE := 0.07     # 고도 1.0 (약 7,500m) 일 때 반지름 증가량
const SEA_SCALE := 0.025     # 수심 쪽은 덜 과장
const LAND_BASE := 0.0025    # 해안선이 수면 위로 올라오도록 하는 최소 높이
const SEA_BASE := 0.004

var hs: HexSphere
var gen: WorldGen
var exaggeration: float = 1.0
var mode: int = Mode.BIOME

var tile_radius := PackedFloat32Array()     # 타일 가운데 반지름
var corner_radius := PackedFloat32Array()   # 꼭짓점(면) 반지름
var _arrays: Array = []
var _vert_tile := PackedInt32Array()
var _vert_shade := PackedFloat32Array()

var terrain_mi := MeshInstance3D.new()
var water_mi := MeshInstance3D.new()
var lake_mi := MeshInstance3D.new()
var river_mi := MeshInstance3D.new()
var grid_mi := MeshInstance3D.new()
var wind_mi := MeshInstance3D.new()
var hover_mi := MeshInstance3D.new()
var atmo_mi := MeshInstance3D.new()
var terrain_mesh := ArrayMesh.new()


func _ready() -> void:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.roughness = 0.95
	mat.metallic_specular = 0.1
	terrain_mi.material_override = mat
	terrain_mi.mesh = terrain_mesh
	add_child(terrain_mi)

	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.08, 0.2, 0.36, 0.84)
	wmat.roughness = 0.55
	wmat.metallic_specular = 0.25
	var ws := SphereMesh.new()
	ws.radius = 1.0
	ws.height = 2.0
	ws.radial_segments = 256
	ws.rings = 128
	water_mi.mesh = ws
	water_mi.material_override = wmat
	add_child(water_mi)

	var lmat := StandardMaterial3D.new()
	lmat.albedo_color = Color("4f93b3")
	lmat.roughness = 0.3
	lmat.metallic_specular = 0.6
	lmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	lake_mi.material_override = lmat
	add_child(lake_mi)

	var rmat := StandardMaterial3D.new()
	rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rmat.albedo_color = Color("2a64a8")
	rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
	river_mi.material_override = rmat
	add_child(river_mi)

	var gmat := StandardMaterial3D.new()
	gmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	gmat.albedo_color = Color(0.12, 0.09, 0.05, 0.13)
	grid_mi.material_override = gmat
	add_child(grid_mi)

	var amat := StandardMaterial3D.new()
	amat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	amat.vertex_color_use_as_albedo = true
	wind_mi.material_override = amat
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


func _land_r(e: float) -> float:
	return 1.0 + LAND_BASE + e * LAND_SCALE * exaggeration


func radius_for(i: int) -> float:
	if gen.is_lake[i] == 1:
		return _land_r(gen.filled[i]) - 0.0015   # 호수 바닥은 수면보다 약간 아래
	var e: float = gen.elevation[i]
	if e >= 0.0:
		return _land_r(e)
	return 1.0 - SEA_BASE + e * SEA_SCALE * maxf(exaggeration, 0.3)


func lake_level(i: int) -> float:
	return _land_r(gen.filled[i]) + 0.0004


func rebuild() -> void:
	tile_radius.resize(hs.count)
	for i in hs.count:
		tile_radius[i] = radius_for(i)
	var fc: int = hs.face_centers.size()
	corner_radius.resize(fc)
	for f in fc:
		var ta: int = hs.face_tiles[f * 3]
		var tb: int = hs.face_tiles[f * 3 + 1]
		var tc: int = hs.face_tiles[f * 3 + 2]
		var sea: int = int(gen.elevation[ta] < 0.0) + int(gen.elevation[tb] < 0.0) + int(gen.elevation[tc] < 0.0)
		if sea > 0 and sea < 3:
			# 땅과 바다가 만나는 꼭짓점은 정확히 수면 높이에 둔다 -> 해안선이 칸 경계를 따라간다
			corner_radius[f] = 1.0
		else:
			corner_radius[f] = (tile_radius[ta] + tile_radius[tb] + tile_radius[tc]) / 3.0
	_build_terrain()
	_build_lakes()
	_build_rivers()
	_build_grid()
	_build_wind()
	set_hover(-1)


func corner_pos(k: int) -> Vector3:
	var f: int = hs.corner_face[k]
	return hs.face_centers[f] * corner_radius[f]


func _build_terrain() -> void:
	var fc: int = hs.face_centers.size()
	# 공유 정점 기준으로 부드러운 법선 계산
	var n_center := PackedVector3Array()
	n_center.resize(hs.count)
	var n_face := PackedVector3Array()
	n_face.resize(fc)
	for i in hs.count:
		var c: Vector3 = hs.centers[i]
		var pc: Vector3 = c * tile_radius[i]
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		for k in deg:
			var ka: int = off + k
			var kb: int = off + (k + 1) % deg
			var pa: Vector3 = corner_pos(ka)
			var pb: Vector3 = corner_pos(kb)
			var tn: Vector3 = (pa - pc).cross(pb - pc)
			if tn.dot(c) < 0.0:
				tn = -tn
			n_center[i] += tn
			n_face[hs.corner_face[ka]] += tn
			n_face[hs.corner_face[kb]] += tn

	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	_vert_tile = PackedInt32Array()
	_vert_shade = PackedFloat32Array()
	for i in hs.count:
		var c: Vector3 = hs.centers[i]
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var base: int = pos.size()
		pos.append(c * tile_radius[i])
		nrm.append(n_center[i].normalized())
		_vert_tile.append(i)
		_vert_shade.append(1.0)
		for k in deg:
			pos.append(corner_pos(off + k))
			nrm.append(n_face[hs.corner_face[off + k]].normalized())
			_vert_tile.append(i)
			_vert_shade.append(1.0)
		for k in deg:
			idx.append(base)
			idx.append(base + 1 + (k + 1) % deg)
			idx.append(base + 1 + k)
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
	# 수면은 지형/고도 보기에서만 덮는다
	water_mi.visible = mode == Mode.BIOME or mode == Mode.ELEVATION or mode == Mode.VEG
	lake_mi.visible = water_mi.visible


func _hash01(i: int) -> float:
	var h: int = (i * 73856093) ^ (gen.seed_value * 19349663)
	h = (h ^ (h >> 13)) * 1274126177
	return float(h & 0xffff) / 65535.0


func tile_color(i: int) -> Color:
	match mode:
		Mode.BIOME:
			var b: int = gen.biome[i]
			var col: Color = WorldGen.BIOME_COLORS[b]
			var e: float = gen.elevation[i]
			if e < 0.0 and gen.is_lake[i] == 0:
				# 해저: 얕으면 모래빛, 깊을수록 어둡게 (수면을 통해 비쳐 보인다)
				if b == WorldGen.B.SEA_ICE:
					return col
				return Color("6fa0a0").lerp(Color("0e1d2e"), clampf(-e * 1.6, 0.0, 1.0))
			if gen.relief[i] == 2:
				col = col.lerp(WorldGen.ROCK_COLOR, 0.5)
				var tt: float = gen.temperature[i]
				if tt < -4.0:
					col = col.lerp(WorldGen.SNOWCAP_COLOR, clampf((-4.0 - tt) / 6.0, 0.35, 0.9))
			elif gen.relief[i] == 1:
				col = col.lerp(WorldGen.ROCK_COLOR, 0.12)
			var j: float = (_hash01(i) - 0.5) * 0.04
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
		Mode.VEG:
			# 2층 식생만 칠하고, 시설물이 있으면 표시한다
			if gen.base[i] != TileLayers.Base.LAND and gen.veg[i] != TileLayers.Veg.ICE:
				return Color("6fa0a0").lerp(Color("0e1d2e"), clampf(-gen.elevation[i] * 1.6, 0.0, 1.0))
			var vc: Color = TileLayers.VEG_COLORS[gen.veg[i]]
			if gen.structure[i] != TileLayers.Struct.NONE:
				vc = Color("d9a13b") if gen.structure_state[i] == TileLayers.State.ACTIVE else Color("8a6d4a")
			elif gen.road[i] == 1:
				vc = vc.lerp(Color("c46a3a"), 0.6)
			return vc
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


func _build_lakes() -> void:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	for i in hs.count:
		if gen.is_lake[i] == 0:
			continue
		var c: Vector3 = hs.centers[i]
		var r: float = lake_level(i)
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var base: int = pos.size()
		pos.append(c * r)
		nrm.append(c)
		for k in deg:
			# 이웃 호수 쪽으로는 살짝 넓혀 틈을 없앤다
			pos.append((c + (hs.corner_list[off + k] - c) * 1.04).normalized() * r)
			nrm.append(c)
		for k in deg:
			idx.append_array([base, base + 1 + (k + 1) % deg, base + 1 + k])
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	lake_mi.mesh = m


## 타일 i 에서 이웃 j 쪽 변의 가운데 점 (지형 표면 위)
func _edge_mid(i: int, j: int) -> Vector3:
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	for k in deg:
		if hs.nb_list[off + k] == j:
			return (corner_pos(off + k) + corner_pos(off + (k + 1) % deg)) * 0.5
	return (hs.centers[i] * tile_radius[i] + hs.centers[j] * tile_radius[j]) * 0.5


## 방향 dir 이 가리키는 지형 표면 위의 점 (타일 부채꼴 삼각형 평면과의 교점)
func surface_point(dir: Vector3, hint: int) -> Vector3:
	var t: int = hs.find_tile(dir, hint)
	var c: Vector3 = hs.centers[t]
	var pc: Vector3 = c * tile_radius[t]
	var off: int = hs.nb_offsets[t]
	var deg: int = hs.degree(t)
	for k in deg:
		var a: Vector3 = corner_pos(off + k)
		var b: Vector3 = corner_pos(off + (k + 1) % deg)
		var s1: float = dir.dot(c.cross(a))
		var s2: float = dir.dot(a.cross(b))
		var s3: float = dir.dot(b.cross(c))
		if (s1 >= 0.0 and s2 >= 0.0 and s3 >= 0.0) or (s1 <= 0.0 and s2 <= 0.0 and s3 <= 0.0):
			var nn: Vector3 = (a - pc).cross(b - pc)
			var den: float = nn.dot(dir)
			if absf(den) > 1e-9:
				return dir * (nn.dot(pc) / den)
	return dir * tile_radius[t]


func _face_pos(f: int) -> Vector3:
	return hs.face_centers[f] * corner_radius[f]


static func _bez3(a: Vector3, c: Vector3, b: Vector3, t: float) -> Vector3:
	var u: float = 1.0 - t
	return a * (u * u) + c * (2.0 * u * t) + b * (t * t)


## 경계 강: 해안선처럼 칸의 변을 따라 각지게 그린다.
func _build_rivers() -> void:
	var pos := PackedVector3Array()
	var idx := PackedInt32Array()
	var F: int = hs.face_centers.size()
	var max_flow: float = 1.0
	var main_up := PackedInt32Array()
	main_up.resize(F)
	main_up.fill(-1)
	for f in F:
		if gen.c_river[f] == 0:
			continue
		max_flow = maxf(max_flow, gen.c_flow[f])
		var d: int = gen.c_down[f]
		if d >= 0 and (main_up[d] < 0 or gen.c_flow[f] > gen.c_flow[main_up[d]]):
			main_up[d] = f
	var lift: float = 0.0016 * maxf(exaggeration, 0.5)
	for f in F:
		if gen.c_river[f] == 0:
			continue
		var d: int = gen.c_down[f]
		if d < 0:
			continue
		# 칸의 변을 그대로 따라가는 각진 직선. 이음매가 비지 않도록 양 끝을 폭의 절반만큼 늘린다.
		var pf: Vector3 = _face_pos(f)
		var pd: Vector3 = _face_pos(d)
		pf = pf.normalized() * (maxf(pf.length(), 1.0) + lift)
		pd = pd.normalized() * (maxf(pd.length(), 1.0) + lift)
		var w0: float = hs.spacing * (0.07 + 0.2 * sqrt(gen.c_flow[f] / max_flow))
		var w1: float = w0
		if gen.c_river[d] == 1:
			w1 = hs.spacing * (0.07 + 0.2 * sqrt(gen.c_flow[d] / max_flow))
		var dirv: Vector3 = (pd - pf).normalized()
		var pts: Array = [pf - dirv * w0 * 0.5, pd + dirv * w1 * 0.5]
		_strip(pos, idx, pts, w0, w1)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	river_mi.mesh = m


func _strip(pos: PackedVector3Array, idx: PackedInt32Array, pts: Array, w0: float, w1: float) -> void:
	var m: int = pts.size()
	var base: int = pos.size()
	for k in m:
		var p: Vector3 = pts[k]
		var a: Vector3 = pts[maxi(k - 1, 0)]
		var b: Vector3 = pts[mini(k + 1, m - 1)]
		var side: Vector3 = (b - a).cross(p.normalized())
		if side.length_squared() < 1e-14:
			side = Vector3.UP.cross(p).normalized()
		side = side.normalized() * lerpf(w0, w1, float(k) / (m - 1)) * 0.5
		pos.append(p - side)
		pos.append(p + side)
	for k in m - 1:
		var v: int = base + k * 2
		idx.append_array([v, v + 1, v + 3, v, v + 3, v + 2])


func _ribbon(pos: PackedVector3Array, idx: PackedInt32Array, a: Vector3, b: Vector3, w: float) -> void:
	var dir: Vector3 = b - a
	if dir.length_squared() < 1e-12:
		return
	var up: Vector3 = ((a + b) * 0.5).normalized()
	var side: Vector3 = dir.cross(up)
	if side.length_squared() < 1e-12:
		return
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


## 타일 경계선. 육지 위에만 그린다.
func _build_grid() -> void:
	var pos := PackedVector3Array()
	var lift: float = 0.0006
	for i in hs.count:
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var land_i: bool = gen.elevation[i] >= 0.0 and gen.is_lake[i] == 0
		for k in deg:
			var j: int = hs.nb_list[off + k]
			if j < i:
				continue
			var land_j: bool = gen.elevation[j] >= 0.0 and gen.is_lake[j] == 0
			if not (land_i or land_j):
				continue
			var a: Vector3 = corner_pos(off + k)
			var b: Vector3 = corner_pos(off + (k + 1) % deg)
			pos.append(a + a.normalized() * lift)
			pos.append(b + b.normalized() * lift)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		m.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arr)
	grid_mi.mesh = m


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
		var c: Vector3 = hs.centers[i] * (maxf(tile_radius[i], 1.0) + 0.006)
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
	for k in deg + 1:
		var p: Vector3 = corner_pos(off + k % deg)
		p = p.normalized() * maxf(p.length(), 1.0)
		im.surface_add_vertex(p + p.normalized() * 0.0015)
	im.surface_end()
	hover_mi.mesh = im
