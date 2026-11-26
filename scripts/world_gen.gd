class_name WorldGen
extends RefCounted
## 행성 생성기: 판 구조 -> 고도 -> 기온 -> 기압과 바람(코리올리) -> 수분 이동과 강수 -> 강, 호수, 습지 -> 생물군계

## 게임용으로 단순화한 지형 12종. 산과 구릉은 지형이 아니라 기복(relief)으로 따로 둔다.
enum B {
	DEEP_OCEAN, OCEAN, SEA_ICE, LAKE,
	GRASSLAND, PLAINS, DESERT, TUNDRA, SNOW, FOREST, JUNGLE, MARSH
}

const BIOME_NAMES := [
	"대양", "연안", "해빙", "호수",
	"초원", "평원", "사막", "툰드라", "설원", "숲", "밀림", "습지"
]

const BIOME_COLORS := [
	Color("1d3a5a"), Color("3d7a92"), Color("d9e3e6"), Color("5fa3bf"),
	Color("6f9a43"), Color("b3a65f"), Color("d8c08a"), Color("8f9479"), Color("eef1ef"), Color("3f6332"), Color("2b5228"), Color("5c7a5c")
]

## 산이 높고 추우면 눈, 아니면 바위 색으로 칠한다 (보기 전용)
const ROCK_COLOR := Color("8c806b")
const SNOWCAP_COLOR := Color("f2f2ee")

const LAND_HEIGHT_M := 7500.0
const SEA_DEPTH_M := 7000.0

# 생성 파라미터
var seed_value: int = 1
var land_ratio: float = 0.32
var plate_count: int = 16
var temp_offset: float = 0.0
var moisture_mult: float = 1.0
var river_amount: float = 1.0

var hs: HexSphere
var n: int = 0
var rng := RandomNumberGenerator.new()

# 결과
var plate := PackedInt32Array()
var plate_axis := PackedVector3Array()
var plate_oceanic := PackedByteArray()
var plate_color := PackedColorArray()
var boundary := PackedFloat32Array()     # +: 수렴, -: 발산 (경계 타일만)
var elevation := PackedFloat32Array()    # -1..1, 0 = 해수면
var temperature := PackedFloat32Array()  # 연평균 섭씨
var pressure := PackedFloat32Array()     # -1 저기압 .. +1 고기압
var wind := PackedVector3Array()         # 접평면 벡터, 길이 = 세기 (0..1)
var precip := PackedFloat32Array()       # mm/년
var downstream := PackedInt32Array()
var flow := PackedFloat32Array()
var filled := PackedFloat32Array()
var is_river := PackedByteArray()        # 칸의 변 중 하나 이상에 강이 흐름 (강변 칸)
var river_mask := PackedInt32Array()     # 칸별 비트마스크: k번째 변(이웃 nb_list[off+k] 쪽)에 강이 있으면 1
var runoff := PackedFloat32Array()       # 칸 자체의 유출량
# 경계 강: 꼭짓점(삼각형 면) 그래프 위에서 흐른다
var c_down := PackedInt32Array()         # 꼭짓점의 하류 꼭짓점
var c_flow := PackedFloat32Array()
var c_river := PackedByteArray()
var c_threshold: float = 0.0
var is_lake := PackedByteArray()
var is_marsh := PackedByteArray()
var biome := PackedInt32Array()
var relief := PackedByteArray()          # 0 평지, 1 구릉, 2 산지
var river_threshold: float = 0.0
var stats := {}

# 이웃 방향 (타일 i 에서 이웃 k 쪽 접선 단위벡터), nb_list 와 같은 인덱스
var nb_dir := PackedVector3Array()


func generate(sphere: HexSphere) -> void:
	hs = sphere
	n = hs.count
	rng.seed = seed_value
	_precompute_dirs()
	_make_plates()
	_make_elevation()
	_make_temperature()
	_make_wind()
	_make_precip()
	_make_hydrology()
	_make_biomes()
	_make_stats()


func lat_of(i: int) -> float:
	return asin(clampf(hs.centers[i].y, -1.0, 1.0))


func lon_of(i: int) -> float:
	var p: Vector3 = hs.centers[i]
	return atan2(p.x, p.z)


func is_water(i: int) -> bool:
	return elevation[i] < 0.0 or is_lake[i] == 1


func height_m(i: int) -> float:
	var e: float = elevation[i]
	return e * LAND_HEIGHT_M if e >= 0.0 else e * SEA_DEPTH_M


## 접평면 기준 동쪽/북쪽 단위벡터 (자전축 = +Y, 동쪽 = 위에서 볼 때 반시계 방향)
static func east_north(p: Vector3) -> Array:
	var e: Vector3 = Vector3.UP.cross(p)
	if e.length_squared() < 1e-8:
		e = Vector3.RIGHT
	e = e.normalized()
	var nn: Vector3 = p.cross(e).normalized()
	return [e, nn]


func _precompute_dirs() -> void:
	nb_dir.resize(hs.nb_list.size())
	for i in n:
		var p: Vector3 = hs.centers[i]
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			var q: Vector3 = hs.centers[hs.nb_list[k]]
			var d: Vector3 = q - p
			d = d - p * d.dot(p)
			nb_dir[k] = d.normalized()


func _noise(freq: float, octaves: int, salt: int) -> FastNoiseLite:
	var fn := FastNoiseLite.new()
	fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fn.seed = seed_value * 31 + salt
	fn.frequency = freq
	fn.fractal_type = FastNoiseLite.FRACTAL_FBM
	fn.fractal_octaves = octaves
	fn.fractal_lacunarity = 2.1
	fn.fractal_gain = 0.5
	return fn


# ---------------------------------------------------------------- 판 구조

func _make_plates() -> void:
	plate.resize(n)
	plate.fill(-1)
	var rate := PackedFloat32Array()
	var frontier := PackedInt32Array()
	plate_axis.resize(plate_count)
	plate_color.resize(plate_count)
	for p in plate_count:
		var s: int = rng.randi_range(0, n - 1)
		while plate[s] != -1:
			s = rng.randi_range(0, n - 1)
		plate[s] = p
		frontier.append(s)
		rate.append(rng.randf_range(0.25, 1.0))
		var ax := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		plate_axis[p] = ax * rng.randf_range(0.4, 1.4)
		plate_color[p] = Color.from_hsv(rng.randf(), rng.randf_range(0.35, 0.6), rng.randf_range(0.55, 0.85))
	# 불규칙한 판 모양을 위해 무작위 순서로 확장
	while frontier.size() > 0:
		var fk: int = rng.randi_range(0, frontier.size() - 1)
		var i: int = frontier[fk]
		if rng.randf() > rate[plate[i]]:
			continue
		var off: int = hs.nb_offsets[i]
		var deg: int = hs.degree(i)
		var start: int = rng.randi_range(0, deg - 1)
		var grew := false
		for t in deg:
			var j: int = hs.nb_list[off + (start + t) % deg]
			if plate[j] == -1:
				plate[j] = plate[i]
				frontier.append(j)
				grew = true
				break
		if not grew:
			frontier[fk] = frontier[frontier.size() - 1]
			frontier.resize(frontier.size() - 1)


func _plate_vel(p_id: int, pos: Vector3) -> Vector3:
	return plate_axis[p_id].cross(pos)


func _make_elevation() -> void:
	# 판마다 대륙/해양 지각 성향
	var area := PackedInt32Array()
	area.resize(plate_count)
	for i in n:
		area[plate[i]] += 1
	var order: Array = range(plate_count)
	for k in range(order.size() - 1, 0, -1):   # 시드 고정 셔플
		var r: int = rng.randi_range(0, k)
		var tmp = order[k]
		order[k] = order[r]
		order[r] = tmp
	var bias := PackedFloat32Array()
	bias.resize(plate_count)
	plate_oceanic.resize(plate_count)
	var cont_area: int = 0
	for p in order:
		if float(cont_area) < land_ratio * 1.15 * n:
			bias[p] = rng.randf_range(0.15, 0.4)
			plate_oceanic[p] = 0
			cont_area += area[p]
		else:
			bias[p] = rng.randf_range(-0.55, -0.3)
			plate_oceanic[p] = 1

	var crust_noise := _noise(1.1, 4, 1)
	var mid_noise := _noise(2.6, 5, 2)
	var ridge_noise := _noise(4.0, 4, 3)
	ridge_noise.fractal_type = FastNoiseLite.FRACTAL_RIDGED

	var base := PackedFloat32Array()
	base.resize(n)
	for i in n:
		var p: Vector3 = hs.centers[i]
		base[i] = bias[plate[i]] * 0.65 + crust_noise.get_noise_3dv(p) * 0.55

	# 경계 응력
	boundary.resize(n)
	boundary.fill(0.0)
	var src_val := PackedFloat32Array()
	src_val.resize(n)
	var is_src := PackedByteArray()
	is_src.resize(n)
	for i in n:
		var pi: int = plate[i]
		var p: Vector3 = hs.centers[i]
		var acc: float = 0.0
		var cnt: int = 0
		var conv_sum: float = 0.0
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			var j: int = hs.nb_list[k]
			var pj: int = plate[j]
			if pj == pi:
				continue
			var rel: Vector3 = _plate_vel(pi, p) - _plate_vel(pj, p)
			var conv: float = rel.dot(nb_dir[k])
			var shear: float = (rel - nb_dir[k] * conv).length()
			var ci: bool = base[i] > 0.0
			var cj: bool = base[j] > 0.0
			var v: float = 0.0
			if conv > 0.0:
				if ci and cj:
					v = 1.1 * conv            # 대륙 충돌: 높은 산맥
				elif ci and not cj:
					v = 0.85 * conv           # 섭입대의 대륙 쪽: 해안 산맥
				elif not ci and cj:
					v = -0.55 * conv          # 해구
				else:
					v = (0.6 if pi > pj else -0.4) * conv  # 호상 열도
			else:
				var mag: float = -conv
				v = (-0.15 if ci else 0.22) * mag   # 열곡 / 해령
			v += 0.08 * shear
			acc += v
			conv_sum += conv
			cnt += 1
		if cnt > 0:
			src_val[i] = acc / cnt
			boundary[i] = conv_sum / cnt
			is_src[i] = 1

	# 경계에서 판 안쪽으로 영향 퍼뜨리기 (판 내부 BFS)
	var width: float = 1.3 * pow(2.0, hs.level - 5)
	var maxd: int = int(ceil(width * 5.0))
	var dist := PackedInt32Array()
	dist.resize(n)
	dist.fill(-1)
	var near := PackedFloat32Array()
	near.resize(n)
	var queue := PackedInt32Array()
	for i in n:
		if is_src[i] == 1:
			dist[i] = 0
			near[i] = src_val[i]
			queue.append(i)
	var head: int = 0
	while head < queue.size():
		var i: int = queue[head]
		head += 1
		if dist[i] >= maxd:
			continue
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			var j: int = hs.nb_list[k]
			if dist[j] == -1 and plate[j] == plate[i]:
				dist[j] = dist[i] + 1
				near[j] = near[i]
				queue.append(j)

	elevation.resize(n)
	for i in n:
		var p: Vector3 = hs.centers[i]
		var e: float = base[i]
		if dist[i] >= 0:
			var d: float = float(dist[i])
			var v: float = near[i]
			var sharp: float = exp(-(d * d) / (2.0 * width * width))
			var broad: float = exp(-d / (width * 3.0))
			var r: float = 0.55 + 0.9 * ridge_noise.get_noise_3dv(p * 1.0)
			if v > 0.0:
				e += v * (sharp * clampf(r, 0.2, 1.4) * 0.9 + broad * 0.35)
			else:
				e += v * (sharp * 0.8 + broad * 0.2)
		e += mid_noise.get_noise_3dv(p) * 0.22
		elevation[i] = e

	# 두 번 살짝 평활화 (대륙붕과 완만한 사면)
	for _pass in 2:
		var nxt := PackedFloat32Array()
		nxt.resize(n)
		for i in n:
			var s: float = elevation[i] * 2.0
			var c: int = 2
			for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
				s += elevation[hs.nb_list[k]]
				c += 1
			nxt[i] = s / c
		elevation = nxt

	# 해수면: 육지 비율에 맞춘 분위수
	var sorted := elevation.duplicate()
	sorted.sort()
	var sea: float = sorted[clampi(int((1.0 - land_ratio) * n), 0, n - 1)]
	var emax: float = sorted[n - 1]
	var emin: float = sorted[0]
	for i in n:
		var e: float = elevation[i] - sea
		if e >= 0.0:
			elevation[i] = pow(e / max(emax - sea, 1e-4), 1.35)  # 저지대가 많은 고도 분포
		else:
			elevation[i] = -pow(-e / max(sea - emin, 1e-4), 0.8)


# ---------------------------------------------------------------- 기온

func _make_temperature() -> void:
	temperature.resize(n)
	var tn := _noise(3.0, 3, 11)
	for i in n:
		var a: float = absf(lat_of(i)) / (PI * 0.5)
		var t: float = 29.0 - 54.0 * pow(a, 1.7) + temp_offset
		t += tn.get_noise_3dv(hs.centers[i]) * 2.0
		if elevation[i] > 0.0:
			t -= 6.5 * height_m(i) / 1000.0   # 기온 감률 6.5°C/km
		temperature[i] = t


# ---------------------------------------------------------------- 기압과 바람

## 3세포 대기 순환: 적도 저압대(0°), 아열대 고압대(30°), 아한대 저압대(60°), 극고압대(90°)
static func band_pressure(lat: float) -> float:
	return -cos(6.0 * lat)


func _make_wind() -> void:
	pressure.resize(n)
	wind.resize(n)
	var pn := _noise(1.8, 3, 21)
	var pert := PackedFloat32Array()
	pert.resize(n)
	for i in n:
		var lat: float = lat_of(i)
		# 육지는 대기를 데워 약간 낮은 기압, 높은 산지는 흐름을 막는다
		var land: float = 1.0 if elevation[i] > 0.0 else 0.0
		pert[i] = pn.get_noise_3dv(hs.centers[i]) * 0.35 - land * 0.08 * (1.0 - absf(lat) / (PI * 0.5))
		pressure[i] = band_pressure(lat) + pert[i]
	var coriolis_angle: float = deg_to_rad(68.0)  # 지표 마찰 때문에 90° 보다 덜 꺾인다
	for i in n:
		var p: Vector3 = hs.centers[i]
		var lat: float = lat_of(i)
		var en: Array = east_north(p)
		var north: Vector3 = en[1]
		# 띠 기압의 기압경도력 (고기압 -> 저기압), 북쪽 성분 = -dP/dlat
		var pgf: Vector3 = north * (-sin(6.0 * lat))
		# 지역 섭동의 기압경도력
		var g := Vector3.ZERO
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			g += nb_dir[k] * (pert[hs.nb_list[k]] - pert[i])
		pgf -= g * (1.0 / hs.spacing) * 0.06
		# 코리올리: 북반구는 오른쪽, 남반구는 왼쪽으로 꺾임. 적도에서는 0
		var ang: float = coriolis_angle * clampf(absf(sin(lat)) * 5.0, 0.0, 1.0)
		ang = -ang if lat > 0.0 else ang
		var v: Vector3 = pgf * cos(ang) + p.cross(pgf) * sin(ang)
		var spd: float = clampf(v.length(), 0.0, 1.0)
		if elevation[i] > 0.0:
			spd *= 1.0 - 0.5 * clampf(elevation[i], 0.0, 1.0)
		wind[i] = v.normalized() * spd if v.length() > 1e-6 else Vector3.ZERO


# ---------------------------------------------------------------- 수분 이동과 강수

## 위도별 기본 강수 (mm/년): 적도 수렴대는 습하고, 아열대 고압대는 건조하며, 편서풍대는 다시 습하다
static func zonal_precip(lat: float) -> float:
	var a: float = absf(rad_to_deg(lat))
	var stops := [[0.0, 2300.0], [8.0, 1900.0], [16.0, 1100.0], [24.0, 520.0], [30.0, 560.0],
		[38.0, 850.0], [48.0, 1100.0], [58.0, 950.0], [68.0, 550.0], [78.0, 260.0], [90.0, 140.0]]
	for k in range(1, stops.size()):
		if a <= stops[k][0]:
			var t: float = (a - stops[k - 1][0]) / (stops[k][0] - stops[k - 1][0])
			return lerpf(stops[k - 1][1], stops[k][1], t)
	return 140.0


func _make_precip() -> void:
	# 1) 바다에서 증발한 수증기가 바람을 따라 내륙으로 이동 (바람 위쪽 이웃에서 끌어옴)
	#    이동하며 조금씩 비로 빠지고, 산을 넘을 때 크게 빠진다 -> 산맥 뒤편 비그늘
	var hum := PackedFloat32Array()
	hum.resize(n)
	var src := PackedFloat32Array()
	src.resize(n)
	var loss := PackedFloat32Array()
	loss.resize(n)
	var uplift := PackedFloat32Array()
	uplift.resize(n)
	var w_pull := PackedFloat32Array()
	w_pull.resize(hs.nb_list.size())
	var lvl_k: float = pow(2.0, hs.level - 5)
	for i in n:
		var water: bool = elevation[i] < 0.0
		src[i] = clampf((temperature[i] + 8.0) / 30.0, 0.25, 1.0) if water else -1.0
		hum[i] = src[i] if water else 0.0
		var w: Vector3 = wind[i]
		var spd: float = w.length()
		var sum: float = 0.0
		var up_h: float = 0.0
		var up_w: float = 0.0
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			var al: float = -nb_dir[k].dot(w)   # 양수 = 그 이웃이 바람 위쪽
			var x: float = maxf(al, 0.0)
			x = x * x + 0.04 + 0.1 * (1.0 - spd)   # 바람이 약하면 사방으로 퍼짐
			w_pull[k] = x
			sum += x
			if al > 0.0:
				up_h += maxf(elevation[hs.nb_list[k]], 0.0) * al
				up_w += al
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			w_pull[k] /= sum
		var hi: float = maxf(elevation[i], 0.0)
		var hu: float = up_h / up_w if up_w > 0.0 else hi
		# 격자가 촘촘해져도 거리당 효과가 같도록 칸 크기로 보정 (기준: 10,242칸)
		uplift[i] = clampf((hi - hu) * 6.0 * lvl_k, 0.0, 1.0)
		loss[i] = (0.04 + 0.45 * uplift[i] + 0.15 * clampf(hi - 0.35, 0.0, 1.0)) / lvl_k

	var iters: int = int(60 * pow(2.0, hs.level - 5))
	for _it in iters:
		for i in n:
			if src[i] >= 0.0:
				continue
			var acc: float = 0.0
			for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
				acc += w_pull[k] * hum[hs.nb_list[k]]
			hum[i] = acc * (1.0 - loss[i])

	# 2) 강수 = 위도별 기본값 x 수증기 x 지형 상승 x 기온 (찬 공기는 수증기를 덜 품는다)
	precip.resize(n)
	for i in n:
		var z: float = zonal_precip(lat_of(i))
		var h: float = hum[i]
		var tf: float = clampf(exp(0.035 * (temperature[i] - 12.0)), 0.25, 1.4)
		var p: float = z * (0.22 + 0.95 * h) * (1.0 + 1.8 * uplift[i]) * lerpf(1.0, tf, 0.6)
		precip[i] = p * moisture_mult
	# 아주 약한 평활화로 칸 사이 끊김 줄이기
	var nxt := PackedFloat32Array()
	nxt.resize(n)
	for i in n:
		var s: float = precip[i] * 3.0
		var c: float = 3.0
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			s += precip[hs.nb_list[k]]
			c += 1.0
		nxt[i] = s / c
	precip = nxt


# ---------------------------------------------------------------- 강, 호수, 습지

func _make_hydrology() -> void:
	downstream.resize(n)
	downstream.fill(-1)
	filled = elevation.duplicate()
	is_lake.resize(n)
	is_lake.fill(0)
	is_river.resize(n)
	is_river.fill(0)
	is_marsh.resize(n)
	is_marsh.fill(0)
	flow.resize(n)
	flow.fill(0.0)

	# Priority-Flood: 바다에서 시작해 낮은 곳부터 채워 나가며 하류 방향을 정한다
	var heap := _Heap.new()
	var visited := PackedByteArray()
	visited.resize(n)
	for i in n:
		if elevation[i] < 0.0:
			visited[i] = 1
			for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
				if elevation[hs.nb_list[k]] >= 0.0:
					heap.push(elevation[i], i)
					break
	# 평탄한 곳에서 강이 자로 그은 듯 곧게 흐르지 않도록 아주 작은 기복을 더한 경로용 고도
	var route := elevation.duplicate()
	var rn := _noise(14.0, 3, 51)
	for i in n:
		if route[i] >= 0.0:
			route[i] += (rn.get_noise_3dv(hs.centers[i]) + 1.0) * 0.012
	var order := PackedInt32Array()
	var eps: float = 1e-5
	while heap.size() > 0:
		var i: int = heap.pop()
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			var j: int = hs.nb_list[k]
			if visited[j] == 1:
				continue
			visited[j] = 1
			filled[j] = maxf(route[j], filled[i] + eps)
			downstream[j] = i
			heap.push(filled[j], j)
			order.append(j)

	# 유출량 = 강수 - 증발산
	for idx in order.size():
		var i: int = order[idx]
		var et: float = clampf(250.0 + 28.0 * temperature[i], 50.0, 1300.0)
		flow[i] = maxf(precip[i] - et * 0.75, precip[i] * 0.08)
	runoff = flow.duplicate()
	for idx in range(order.size() - 1, -1, -1):
		var i: int = order[idx]
		var d: int = downstream[i]
		if d >= 0 and elevation[d] >= 0.0:
			flow[d] += flow[i]

	var land_flows := PackedFloat32Array()
	for i in order:
		land_flows.append(flow[i])
	land_flows.sort()
	var q: float = clampf(1.0 - 0.09 * river_amount, 0.5, 0.995)
	river_threshold = land_flows[int(q * (land_flows.size() - 1))] if land_flows.size() > 0 else 1e9
	river_threshold = maxf(river_threshold, 1500.0)

	# 호수: 물이 고이는 움푹한 곳 중 유입량이 증발을 이기는 곳
	var lake_depth: float = 0.004
	for i in order:
		if filled[i] - route[i] > lake_depth and flow[i] > river_threshold * 0.35 and temperature[i] > -15.0:
			is_lake[i] = 1
	# 호수 하나가 너무 넓게 퍼지지 않도록 가장 깊은 칸만 남긴다
	var lake_cap: int = int(8 * pow(4.0, hs.level - 5))
	var seen := PackedByteArray()
	seen.resize(n)
	for s0 in order:
		if is_lake[s0] == 0 or seen[s0] == 1:
			continue
		var comp: Array = []
		var stack := PackedInt32Array([s0])
		seen[s0] = 1
		while stack.size() > 0:
			var c: int = stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			comp.append([filled[c] - elevation[c], c])
			for k in range(hs.nb_offsets[c], hs.nb_offsets[c + 1]):
				var j: int = hs.nb_list[k]
				if is_lake[j] == 1 and seen[j] == 0:
					seen[j] = 1
					stack.append(j)
		if comp.size() > lake_cap:
			comp.sort_custom(func(x, y): return x[0] > y[0])
			for m in range(lake_cap, comp.size()):
				is_lake[comp[m][1]] = 0
	_make_edge_rivers()

	# 습지: 평탄한 저지대 + 많은 물 (큰 강 하구, 다습 저지, 한대 소택지)
	var mn := _noise(4.5, 2, 41)
	for i in order:
		if is_lake[i] == 1:
			continue
		var h: float = elevation[i]
		if h > 0.07:
			continue
		var rough: float = 0.0
		var coast := false
		var near_lake := false
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			var j: int = hs.nb_list[k]
			if elevation[j] < 0.0:
				coast = true
			elif is_lake[j] == 1:
				near_lake = true
			else:
				rough = maxf(rough, absf(elevation[j] - h))
		if rough > 0.025 * pow(2.0, 5 - hs.level):
			continue
		var wet: float = precip[i] / 1000.0 + (flow[i] / river_threshold) * (0.35 if coast else 0.12)
		if near_lake:
			wet += 0.4
		if temperature[i] < 4.0 and temperature[i] > -8.0:
			wet += 0.5   # 영구동토 위 소택지
		if wet + mn.get_noise_3dv(hs.centers[i]) * 0.6 > 1.9:
			is_marsh[i] = 1


## 경계 강: 강은 칸 중심이 아니라 칸 사이의 변을 따라 흐른다.
## 꼭짓점(세 칸이 만나는 점)을 노드, 칸의 변을 간선으로 보고 바다에서부터 Priority-Flood 로
## 하류 방향을 정한 뒤, 유출량을 모아 강을 만든다.
func _make_edge_rivers() -> void:
	var F: int = hs.face_centers.size()
	var ce := PackedFloat32Array()
	ce.resize(F)
	var sink := PackedByteArray()
	sink.resize(F)
	var rn := _noise(16.0, 3, 61)
	var c_run := PackedFloat32Array()
	c_run.resize(F)
	for f in F:
		var e: float = 0.0
		var water := false
		for t in 3:
			var ti: int = hs.face_tiles[f * 3 + t]
			if elevation[ti] < 0.0 or is_lake[ti] == 1:
				water = true
			e += filled[ti]
			c_run[f] += runoff[ti] / float(hs.degree(ti))
		ce[f] = e / 3.0 + (rn.get_noise_3dv(hs.face_centers[f]) + 1.0) * 0.006
		sink[f] = 1 if water else 0
	c_down.resize(F)
	c_down.fill(-1)
	c_flow.resize(F)
	c_flow.fill(0.0)
	c_river.resize(F)
	c_river.fill(0)
	var heap := _Heap.new()
	var visited := PackedByteArray()
	visited.resize(F)
	for f in F:
		if sink[f] == 1:
			visited[f] = 1
			heap.push(ce[f], f)
	var order := PackedInt32Array()
	while heap.size() > 0:
		var f: int = heap.pop()
		for e in 3:
			var g: int = hs.face_nb[f * 3 + e]
			if visited[g] == 1:
				continue
			visited[g] = 1
			ce[g] = maxf(ce[g], ce[f] + 1e-5)
			c_down[g] = f
			heap.push(ce[g], g)
			order.append(g)
	for f in order:
		c_flow[f] = c_run[f]
	for idx in range(order.size() - 1, -1, -1):
		var f: int = order[idx]
		var d: int = c_down[f]
		if d >= 0 and sink[d] == 0:
			c_flow[d] += c_flow[f]
	# 임계값: 육지 꼭짓점 유량의 상위 분위수
	var fl := PackedFloat32Array()
	for f in order:
		fl.append(c_flow[f])
	fl.sort()
	var q: float = clampf(1.0 - 0.06 * river_amount, 0.5, 0.995)
	var thr: float = maxf(fl[int(q * (fl.size() - 1))] if fl.size() > 0 else 1e9, 400.0)
	for f in order:
		if c_flow[f] >= thr:
			c_river[f] = 1
	# 수계 정리: 하구(바다/호수 꼭짓점)까지 이어지고 본류가 충분히 긴 것만 남긴다
	var chain := PackedInt32Array()
	chain.resize(F)
	for idx in range(order.size() - 1, -1, -1):
		var f: int = order[idx]
		if c_river[f] == 0:
			continue
		chain[f] = maxi(chain[f], 1)
		var d: int = c_down[f]
		if d >= 0 and c_river[d] == 1:
			chain[d] = maxi(chain[d], chain[f] + 1)
	var mouth := PackedInt32Array()
	mouth.resize(F)
	mouth.fill(-1)
	for f in order:
		if c_river[f] == 0:
			continue
		var d: int = c_down[f]
		if d >= 0 and c_river[d] == 1:
			mouth[f] = mouth[d]
		elif d >= 0 and sink[d] == 1:
			mouth[f] = f
	var min_len: int = maxi(4, int(round(8.0 * pow(2.0, hs.level - 6))))
	for f in order:
		if c_river[f] == 1 and (mouth[f] < 0 or chain[mouth[f]] < min_len):
			c_river[f] = 0
	var spur: int = maxi(1, min_len / 3)
	for f in order:
		if c_river[f] == 1 and chain[f] <= spur:
			var d: int = c_down[f]
			if d >= 0 and c_river[d] == 1 and chain[d] > chain[f] + 1:
				c_river[f] = 0
	for f in order:
		if c_river[f] == 1:
			var d: int = c_down[f]
			if d < 0 or (c_river[d] == 0 and sink[d] == 0):
				c_river[f] = 0
	# 칸별 강 변 기록
	river_mask.resize(n)
	river_mask.fill(0)
	is_river.fill(0)
	for f in F:
		if c_river[f] == 0:
			continue
		var d: int = c_down[f]
		# f-d 간선을 공유하는 두 칸 = 두 면이 공유하는 두 꼭짓점
		for t in 3:
			var ti: int = hs.face_tiles[f * 3 + t]
			var off: int = hs.nb_offsets[ti]
			var deg: int = hs.degree(ti)
			for k in deg:
				var fa: int = hs.corner_face[off + k]
				var fb: int = hs.corner_face[off + (k + 1) % deg]
				if (fa == f and fb == d) or (fa == d and fb == f):
					river_mask[ti] |= 1 << k
					is_river[ti] = 1
	c_threshold = thr


# ---------------------------------------------------------------- 생물군계

const RELIEF_NAMES := ["평지", "구릉", "산지"]


func _make_biomes() -> void:
	biome.resize(n)
	relief.resize(n)
	relief.fill(0)
	for i in n:
		if elevation[i] < 0.0 or is_lake[i] == 1:
			continue
		var hm: float = height_m(i)
		var rng_m: float = 0.0
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i + 1]):
			var j: int = hs.nb_list[k]
			rng_m = maxf(rng_m, hm - maxf(height_m(j), 0.0))
		if hm > 1900.0 or (hm > 1000.0 and rng_m > 550.0):
			relief[i] = 2
		elif hm > 650.0 or rng_m > 300.0:
			relief[i] = 1
	for i in n:
		var t: float = temperature[i]
		var p: float = precip[i]
		var e: float = elevation[i]
		if is_lake[i] == 1:
			biome[i] = B.LAKE if t > -10.0 else B.SEA_ICE
			continue
		if e < 0.0:
			if t < -9.0:
				biome[i] = B.SEA_ICE
			elif e > -0.15:
				biome[i] = B.OCEAN
			else:
				biome[i] = B.DEEP_OCEAN
			continue
		var b: int
		if t < -10.0:
			b = B.SNOW
		elif is_marsh[i] == 1:
			b = B.MARSH
		elif t < 0.0:
			b = B.TUNDRA
		elif p < 250.0:
			b = B.DESERT
		elif p < 520.0:
			b = B.PLAINS
		elif t >= 20.0 and p >= 2000.0:
			b = B.JUNGLE
		elif p >= 950.0 or t < 6.0:
			b = B.FOREST
		else:
			b = B.GRASSLAND
		biome[i] = b


func _make_stats() -> void:
	var land: int = 0
	var rivers: int = 0
	var lakes: int = 0
	var marsh: int = 0
	var counts := PackedInt32Array()
	counts.resize(BIOME_NAMES.size())
	for i in n:
		counts[biome[i]] += 1
		if elevation[i] >= 0.0:
			land += 1
		rivers += is_river[i]
		lakes += is_lake[i]
		marsh += is_marsh[i]
	stats = {"land": land, "rivers": rivers, "lakes": lakes, "marsh": marsh, "counts": counts}


# 최소 힙 (Priority-Flood 용)
class _Heap:
	var keys := PackedFloat32Array()
	var vals := PackedInt32Array()

	func size() -> int:
		return vals.size()

	func push(k: float, v: int) -> void:
		keys.append(k)
		vals.append(v)
		var i: int = vals.size() - 1
		while i > 0:
			var p: int = (i - 1) >> 1
			if keys[p] <= keys[i]:
				break
			_swap(i, p)
			i = p

	func pop() -> int:
		var top: int = vals[0]
		var last: int = vals.size() - 1
		keys[0] = keys[last]
		vals[0] = vals[last]
		keys.resize(last)
		vals.resize(last)
		var i: int = 0
		while true:
			var l: int = i * 2 + 1
			var r: int = l + 1
			var m: int = i
			if l < last and keys[l] < keys[m]:
				m = l
			if r < last and keys[r] < keys[m]:
				m = r
			if m == i:
				break
			_swap(i, m)
			i = m
		return top

	func _swap(a: int, b: int) -> void:
		var tk: float = keys[a]
		keys[a] = keys[b]
		keys[b] = tk
		var tv: int = vals[a]
		vals[a] = vals[b]
		vals[b] = tv
