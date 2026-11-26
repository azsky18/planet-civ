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

## 타일 위 그림 (식생, 도로, 시설물). 그림 목록과 고르는 규칙은 TileArt 에 있다.
static var tile_art: TileArt
var art_enabled := true
var art_shore_mi := MeshInstance3D.new()
var art_veg_mi := MeshInstance3D.new()
var art_road_mi := MeshInstance3D.new()
var art_struct_mi := MeshInstance3D.new()
var art_shadow_mi := MeshInstance3D.new()
var art_sprite_mi := MeshInstance3D.new()
var river_bank_mi := MeshInstance3D.new()
var _terrain_mat := ShaderMaterial.new()

## 지형: 멀리서는 칸 색, 가까이 가면 바닥 무늬 (UV.x = 바닥 그림 번호, -1 이면 무늬 없음).
## 무늬는 위치로 세 방향에서 찍어 섞기 때문에(삼면 투영) 칸 경계에서도 이어진다.
const TERRAIN_SHADER := """
shader_type spatial;
uniform sampler2DArray ground : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_ground = true;
uniform float tex_scale = 25.0;
uniform float near_d = 0.6;
uniform float far_d = 0.9;
varying vec3 opos;
varying vec3 onrm;
void vertex() {
	opos = VERTEX;
	onrm = NORMAL;
}
void fragment() {
	vec3 col = COLOR.rgb;
	float layer = UV.x;
	if (use_ground && layer > -0.5) {
		vec3 w = pow(abs(normalize(onrm)), vec3(4.0));
		w /= (w.x + w.y + w.z);
		vec3 p = opos * tex_scale;
		vec3 t = texture(ground, vec3(p.yz, layer)).rgb * w.x
			+ texture(ground, vec3(p.xz, layer)).rgb * w.y
			+ texture(ground, vec3(p.xy, layer)).rgb * w.z;
		float k = 1.0 - smoothstep(near_d, far_d, length(VERTEX));
		col = mix(col, t, k * 0.9);
	}
	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}
"""

## 세운 그림: 네 꼭짓점이 모두 바닥 점에 모여 있고, UV2 만큼 카메라 쪽으로 펼친다.
## 세로축은 카메라 위쪽과 지면의 위쪽을 섞어서, 내려다볼 때도 납작해지지 않게 한다.
const SPRITE_SHADER := """
shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic;
uniform float near_d = 0.6;
uniform float far_d = 0.9;
void vertex() {
	vec3 anchor = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 up = normalize(anchor);
	vec3 cam_right = normalize(INV_VIEW_MATRIX[0].xyz);
	vec3 cam_up = normalize(INV_VIEW_MATRIX[1].xyz);
	vec3 vaxis = normalize(cam_up + up * 0.9);
	vec3 haxis = normalize(cross(vaxis, cross(cam_right, vaxis)) + cam_right * 0.001);
	float d = length(anchor - CAMERA_POSITION_WORLD);
	float k = 1.0 - smoothstep(near_d, far_d, d);
	vec3 wp = anchor + (haxis * UV2.x + vaxis * UV2.y) * k + up * 0.0008;
	VERTEX = (inverse(MODEL_MATRIX) * vec4(wp, 1.0)).xyz;
	NORMAL = (inverse(MODEL_MATRIX) * vec4(normalize(up * 0.5 + normalize(INV_VIEW_MATRIX[2].xyz) * 0.5), 0.0)).xyz;
}
void fragment() {
	vec4 t = texture(atlas, UV);
	ALBEDO = t.rgb * COLOR.rgb;
	ALPHA = t.a;
	ALPHA_SCISSOR_THRESHOLD = 0.5;
	EMISSION = t.rgb * COLOR.rgb * 0.18;
	ROUGHNESS = 1.0;
	SPECULAR = 0.05;
}
"""
var _sprite_mat := ShaderMaterial.new()
## 그림이 보이기 시작하는 화면 위 칸 크기 (px, 화면 높이 900 기준). 이보다 작으면 흐려지다 사라진다.
const ART_MIN_PX := 26.0
const ART_FULL_PX := 40.0


func _ready() -> void:
	if tile_art == null:
		tile_art = TileArt.new()
		tile_art.load_all()
	var tsh := Shader.new()
	tsh.code = TERRAIN_SHADER
	_terrain_mat.shader = tsh
	_terrain_mat.set_shader_parameter("ground", tile_art.ground_tex)
	terrain_mi.material_override = _terrain_mat
	terrain_mi.mesh = terrain_mesh
	add_child(terrain_mi)

	var wmat := StandardMaterial3D.new()
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.albedo_color = Color(0.08, 0.2, 0.36, 0.84)
	wmat.roughness = 0.55
	wmat.metallic_specular = 0.25
	wmat.render_priority = -1   # 해안 물거품이 수면 위에 그려지도록 수면을 먼저 그린다
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

	var prio := 0
	for mi in [river_bank_mi, art_shore_mi, art_veg_mi, art_road_mi, art_struct_mi, art_shadow_mi]:
		var m := StandardMaterial3D.new()
		m.albedo_texture = tile_art.decals.texture
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		m.vertex_color_use_as_albedo = true
		m.roughness = 1.0
		m.metallic_specular = 0.05
		m.render_priority = prio
		prio += 1
		m.distance_fade_mode = BaseMaterial3D.DISTANCE_FADE_PIXEL_ALPHA
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
	var ssh := Shader.new()
	ssh.code = SPRITE_SHADER
	_sprite_mat.shader = ssh
	_sprite_mat.set_shader_parameter("atlas", tile_art.sprites.texture)
	art_sprite_mi.material_override = _sprite_mat
	art_sprite_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# 세운 그림은 카메라 쪽으로 기울어 실제 위치를 벗어나므로 화면 밖으로 잘리지 않게 넉넉히
	art_sprite_mi.extra_cull_margin = 0.5
	add_child(art_sprite_mi)


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
	var guv := PackedVector2Array()
	guv.resize(_vert_tile.size())
	var gidx := PackedInt32Array()
	gidx.resize(hs.count)
	for i in hs.count:
		gidx[i] = tile_art.ground_index(gen, i)
	for v in _vert_tile.size():
		guv[v] = Vector2(gidx[_vert_tile[v]], 0.0)
	_arrays[Mesh.ARRAY_TEX_UV] = guv
	_terrain_mat.set_shader_parameter("use_ground", art_enabled and mode == Mode.BIOME)
	terrain_mesh.clear_surfaces()
	terrain_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, _arrays)
	# 수면은 지형/고도 보기에서만 덮는다
	water_mi.visible = mode == Mode.BIOME or mode == Mode.ELEVATION or mode == Mode.VEG
	lake_mi.visible = water_mi.visible
	_build_art()


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
	var bank := _ArtBuf.new()
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
		var pts: Array = [pf, pd]
		# 꺾이는 꼭짓점은 둥근 이음매(원판)로 메워 모서리가 튀어나오지 않게 한다
		_disc(pos, idx, pf, pf.normalized(), w0 * 0.5)
		_strip(pos, idx, pts, w0, w1)
		_bank_strip(bank, pf, pd, w0 * 2.8, w1 * 2.8, -lift * 0.3)
	var m := ArrayMesh.new()
	if pos.size() > 0:
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	river_mi.mesh = m
	river_bank_mi.mesh = bank.mesh()


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
	for k in 16:
		var a: float = TAU * k / 16.0
		pos.append(c + (t * cos(a) + b * sin(a)) * r)
	for k in 16:
		idx.append_array([s, s + 1 + k, s + 1 + (k + 1) % 16])


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


# ---------------------------------------------------------------- 타일 위 그림

func _build_art() -> void:
	var show: bool = art_enabled and (mode == Mode.BIOME or mode == Mode.VEG)
	# 칸이 화면에서 작아지면 흐려지다 사라지게 (먼 거리에서 투명, 가까우면 불투명)
	var px_per_unit: float = 900.0 / (2.0 * tan(deg_to_rad(20.0)))
	var far_d: float = hs.spacing * px_per_unit / ART_MIN_PX
	var near_d: float = hs.spacing * px_per_unit / ART_FULL_PX
	for mi in [art_veg_mi, art_road_mi, art_struct_mi, art_shadow_mi, art_sprite_mi, art_shore_mi, river_bank_mi]:
		mi.visible = show
		if mi.material_override is StandardMaterial3D:
			var m: StandardMaterial3D = mi.material_override
			m.distance_fade_min_distance = far_d
			m.distance_fade_max_distance = near_d
	_sprite_mat.set_shader_parameter("near_d", near_d)
	_sprite_mat.set_shader_parameter("far_d", far_d)
	_terrain_mat.set_shader_parameter("near_d", near_d)
	_terrain_mat.set_shader_parameter("far_d", far_d)
	# 바닥 무늬 한 장이 칸 두 개쯤을 덮도록
	_terrain_mat.set_shader_parameter("tex_scale", 1.0 / (hs.spacing * 2.0))
	if not show:
		return
	var veg := _ArtBuf.new()
	var road := _ArtBuf.new()
	var st := _ArtBuf.new()
	var shadow := _ArtBuf.new()
	var spr := _ArtBuf.new()
	var shore := _ArtBuf.new()
	var D: TileArt.Atlas = tile_art.decals
	for i in hs.count:
		var vk: String = TileArt.veg_key(gen, i)
		if vk != "" and D.has(vk):
			_art_fan(veg, i, vk, 0.0, 0.0006, Color.WHITE)
		_art_roads(road, i)
		var sk: String = TileArt.struct_key(gen, i)
		if sk != "" and D.has(sk):
			var tint: Color = TileArt.IDLE_TINT if gen.structure_state[i] == TileLayers.State.IDLE else Color.WHITE
			_art_fan(st, i, sk, 0.0, 0.0012, tint)
		_art_shore(shore, i)
		for e in TileArt.sprites_for(gen, i):
			_art_sprite(spr, shadow, i, e[0], e[1], e[2], e[3], e[4])
	art_veg_mi.mesh = veg.mesh()
	art_road_mi.mesh = road.mesh()
	art_struct_mi.mesh = st.mesh()
	art_shadow_mi.mesh = shadow.mesh()
	art_sprite_mi.mesh = spr.mesh(true)
	art_shore_mi.mesh = shore.mesh()


## 칸 i 의 점 (x, y) (칸 좌표, 꼭짓점까지 1) 아래 지형 표면 위치
func _art_ground(i: int, x: float, y: float) -> Vector3:
	var c: Vector3 = hs.centers[i]
	var fr: Array = _tile_frame(i)
	var dir: Vector3 = (c + (fr[0] * x + fr[1] * y) * _tile_rad(i)).normalized()
	var p: Vector3 = surface_point(dir, i)
	if gen.base[i] != TileLayers.Base.LAND:
		p = dir * (lake_level(i) if gen.is_lake[i] == 1 else maxf(p.length(), 1.0))
	return p


func _tile_rad(i: int) -> float:
	var c: Vector3 = hs.centers[i]
	var rad := 0.0
	for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
		rad = maxf(rad, (hs.corner_list[k] - c).length())
	return rad


## 세운 그림 하나: 바닥 점에 네 꼭짓점을 모아 두고, 셰이더가 카메라를 향해 펼친다.
## 발밑에는 납작한 그림자를 깐다.
func _art_sprite(buf: _ArtBuf, shadow: _ArtBuf, i: int, key: String, x: float, y: float, size: float, tint: Color) -> void:
	if not tile_art.sprites.has(key):
		return
	var p: Vector3 = _art_ground(i, x, y)
	var w: float = size * _tile_rad(i)
	var S: TileArt.Atlas = tile_art.sprites
	var base: int = buf.pos.size()
	var up: Vector3 = p.normalized()
	for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		buf.pos.append(p)
		buf.nrm.append(up)
		buf.col.append(tint)
		buf.uv.append(S.uv(key, corner.x, corner.y))
		# 바닥 점 기준 펼칠 거리 (가로는 가운데 기준, 세로는 아래 끝 기준)
		buf.uv2.append(Vector2(corner.x * 0.5 * w, (corner.y * 0.5 + 0.5) * w))
	buf.idx.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
	if tile_art.decals.has("shadow"):
		var fr: Array = _tile_frame(i)
		var e: Vector3 = fr[0] * w * 0.42
		var n: Vector3 = fr[1] * w * 0.26
		var c: Vector3 = p + up * 0.0013 + fr[0] * w * 0.08 - fr[1] * w * 0.04
		var sb: int = shadow.pos.size()
		for corner in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
			shadow.pos.append(c + e * corner.x + n * corner.y)
			shadow.nrm.append(up)
			shadow.col.append(Color.WHITE)
			shadow.uv.append(tile_art.decals.uv("shadow", corner.x, corner.y))
		shadow.tri(sb, sb + 2, sb + 1)
		shadow.tri(sb, sb + 3, sb + 2)


## 해안과 호숫가: 땅 칸에서 물과 닿는 변마다 모래톱(땅 쪽)과 물거품(물 쪽) 띠를 깐다.
func _art_shore(buf: _ArtBuf, i: int) -> void:
	if gen.base[i] != TileLayers.Base.LAND or not tile_art.decals.has("shore"):
		return
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	var c: Vector3 = hs.centers[i]
	var pc: Vector3 = c * tile_radius[i]
	var lift: float = 0.0004
	for k in deg:
		var j: int = hs.nb_list[off + k]
		if gen.base[j] == TileLayers.Base.LAND:
			continue
		var wl: float = lake_level(j) if gen.is_lake[j] == 1 else 1.0
		var ka: int = off + k
		var kb: int = off + (k + 1) % deg
		var a: Vector3 = corner_pos(ka)
		var b: Vector3 = corner_pos(kb)
		a = a.normalized() * maxf(a.length(), wl)
		b = b.normalized() * maxf(b.length(), wl)
		var a_in: Vector3 = a.lerp(pc, 0.3)
		var b_in: Vector3 = b.lerp(pc, 0.3)
		var a_out: Vector3 = (hs.corner_list[ka] + (hs.corner_list[ka] - c) * 0.3).normalized() * wl
		var b_out: Vector3 = (hs.corner_list[kb] + (hs.corner_list[kb] - c) * 0.3).normalized() * wl
		var rows: Array = [[a_out, b_out, 1.0], [a, b, 0.0], [a_in, b_in, -1.0]]
		var base: int = buf.pos.size()
		for r in rows:
			for q in 2:
				var p: Vector3 = r[q]
				p += p.normalized() * lift
				buf.pos.append(p)
				buf.nrm.append(p.normalized())
				buf.col.append(Color.WHITE)
				buf.uv.append(tile_art.decals.uv("shore", -0.98 if q == 0 else 0.98, r[2] * 0.98))
		for r in 2:
			var v: int = base + r * 2
			buf.tri(v, v + 1, v + 3)
			buf.tri(v, v + 3, v + 2)


## 강줄기 아래 흙둑 띠
func _bank_strip(buf: _ArtBuf, a: Vector3, b: Vector3, w0: float, w1: float, lift: float) -> void:
	if not tile_art.decals.has("river_bank"):
		return
	var up: Vector3 = ((a + b) * 0.5).normalized()
	var side: Vector3 = (b - a).cross(up)
	if side.length_squared() < 1e-14:
		return
	side = side.normalized()
	var ext: Vector3 = (b - a).normalized() * w0 * 0.25
	var pa: Vector3 = a - ext + a.normalized() * lift
	var pb: Vector3 = b + ext + b.normalized() * lift
	var base: int = buf.pos.size()
	var pts: Array = [pa - side * w0 * 0.5, pa + side * w0 * 0.5, pb + side * w1 * 0.5, pb - side * w1 * 0.5]
	var uvs: Array = [Vector2(-0.98, -0.98), Vector2(-0.98, 0.98), Vector2(0.98, 0.98), Vector2(0.98, -0.98)]
	for q in 4:
		buf.pos.append(pts[q])
		buf.nrm.append(up)
		buf.col.append(Color.WHITE)
		buf.uv.append(tile_art.decals.uv("river_bank", uvs[q].x, uvs[q].y))
	buf.tri(base, base + 2, base + 1)
	buf.tri(base, base + 3, base + 2)


func _art_roads(buf: _ArtBuf, i: int) -> void:
	var is_road: bool = gen.road[i] == 1
	var is_district: bool = TileArt.road_link(gen, i) and not is_road
	if not (is_road or is_district) or not tile_art.decals.has("road"):
		return
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	var any := false
	for k in deg:
		var j: int = hs.nb_list[off + k]
		# 도로 칸은 이어진 모든 방향으로, 정착지 구역은 도로 칸 쪽으로만 갈래를 낸다
		var linked: bool = TileArt.road_link(gen, j) if is_road else gen.road[j] == 1
		if not linked:
			continue
		any = true
		var mid: Vector3 = (hs.corner_list[off + k] + hs.corner_list[off + (k + 1) % deg]).normalized()
		var fr: Array = _tile_frame(i)
		var d: Vector3 = mid - hs.centers[i]
		_art_fan(buf, i, "road", atan2(d.dot(fr[1]), d.dot(fr[0])), 0.0009, Color.WHITE)
	if is_road and not any and tile_art.decals.has("road_alone"):
		_art_fan(buf, i, "road_alone", 0.0, 0.0009, Color.WHITE)


## 칸 중심의 접평면 좌표축 [동, 북]
func _tile_frame(i: int) -> Array:
	var c: Vector3 = hs.centers[i]
	var north: Vector3 = Vector3.UP - c * c.y
	if north.length_squared() < 1e-8:
		north = Vector3.BACK - c * c.z
	north = north.normalized()
	return [north.cross(c).normalized(), north]


## 칸 i 를 덮는 부채꼴에 그림 key 를 붙인다. angle 만큼 그림을 돌린다 (그림의 +x 가 그 방향).
func _art_fan(buf: _ArtBuf, i: int, key: String, angle: float, lift: float, tint: Color) -> void:
	var c: Vector3 = hs.centers[i]
	var off: int = hs.nb_offsets[i]
	var deg: int = hs.degree(i)
	var fr: Array = _tile_frame(i)
	var east: Vector3 = fr[0]
	var north: Vector3 = fr[1]
	var rad := 0.0
	for k in deg:
		rad = maxf(rad, (hs.corner_list[off + k] - c).length())
	var ca: float = cos(angle)
	var sa: float = sin(angle)
	var on_water: bool = gen.base[i] != TileLayers.Base.LAND
	var wr: float = lake_level(i) if gen.is_lake[i] == 1 else maxf(tile_radius[i], 1.0)
	var base: int = buf.pos.size()
	for k in deg + 1:
		var p: Vector3
		var dir: Vector3
		if k == 0:
			dir = c
			p = c * (wr if on_water else tile_radius[i])
		else:
			dir = hs.corner_list[off + k - 1]
			p = dir * wr if on_water else corner_pos(off + k - 1)
		p += p.normalized() * lift
		var d: Vector3 = dir - c
		var x: float = d.dot(east) / rad
		var y: float = d.dot(north) / rad
		buf.pos.append(p)
		buf.nrm.append(p.normalized())
		buf.col.append(tint)
		buf.uv.append(tile_art.decals.uv(key, x * ca + y * sa, -x * sa + y * ca))
	for k in deg:
		buf.idx.append_array([base, base + 1 + (k + 1) % deg, base + 1 + k])


class _ArtBuf:
	var pos := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	var uv := PackedVector2Array()
	var uv2 := PackedVector2Array()
	var idx := PackedInt32Array()

	## 바깥(행성 밖)을 향하도록 감는 방향을 맞춰 삼각형을 넣는다
	func tri(a: int, b: int, c: int) -> void:
		var n: Vector3 = (pos[b] - pos[a]).cross(pos[c] - pos[a])
		if n.dot(pos[a]) < 0.0:
			idx.append_array([a, b, c])
		else:
			idx.append_array([a, c, b])

	func mesh(with_uv2: bool = false) -> ArrayMesh:
		var m := ArrayMesh.new()
		if pos.is_empty():
			return m
		var arr: Array = []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = pos
		arr[Mesh.ARRAY_NORMAL] = nrm
		arr[Mesh.ARRAY_COLOR] = col
		arr[Mesh.ARRAY_TEX_UV] = uv
		if with_uv2:
			arr[Mesh.ARRAY_TEX_UV2] = uv2
		arr[Mesh.ARRAY_INDEX] = idx
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		return m
