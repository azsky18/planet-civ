class_name TileLayers
extends RefCounted
## 타일 레이어 규칙.
## 칸 하나는 세 층으로 나뉜다.
##   1층 지형·기후: 바탕, 기복, 기온대, 습도, 강. 세계 생성 때 정해지고 바뀌지 않는다.
##   2층 식생: 맨땅, 초지, 숲, 습지, 빙설. 천이, 벌목, 배수로 천천히 바뀐다.
##   3층 시설물: 경작지, 정착지 구역, 도로 등. 사람이 짓고 버린다.
## 지금의 12종 지형(WorldGen.B)은 저장하지 않고, 세 층을 조합한 표시 이름으로만 쓴다.
## 기획서: "타일 레이어 시스템 기획" (2026-11-26)

# ---------------------------------------------------------------- 1층 지형·기후

enum Base { LAND, SHALLOW, DEEP, LAKE }
const BASE_NAMES := ["땅", "얕은 바다", "깊은 바다", "호수"]

enum TempBand { TROPICAL, TEMPERATE, BOREAL, POLAR }
const TEMP_NAMES := ["열대", "온대", "냉대", "한대"]

enum Moist { ARID, SEMI, HUMID }
const MOIST_NAMES := ["건조", "반건조", "습윤"]

# 기복은 WorldGen.relief (0 평지, 1 구릉, 2 산지), 강은 WorldGen.river_mask 를 그대로 쓴다.


static func temp_band_of(t: float) -> int:
	if t >= 20.0:
		return TempBand.TROPICAL
	if t >= 6.0:
		return TempBand.TEMPERATE
	if t >= 0.0:
		return TempBand.BOREAL
	return TempBand.POLAR


static func moist_of(p: float) -> int:
	if p < 250.0:
		return Moist.ARID
	if p < 520.0:
		return Moist.SEMI
	return Moist.HUMID


# ---------------------------------------------------------------- 2층 식생

enum Veg { NONE, BARE, GRASS, FOREST, WETLAND, ICE }
const VEG_NAMES := ["없음", "맨땅", "초지", "숲", "습지", "빙설"]
const VEG_COLORS := [
	Color("1d3a5a"), Color("c9ad7a"), Color("8fb04f"), Color("2f5a2a"), Color("4f7f78"), Color("eef1ef")
]

## 자연 천이에 걸리는 턴 수 (초안)
const SUCCESSION_TURNS := { Veg.BARE: 10, Veg.GRASS: 20 }


# ---------------------------------------------------------------- 3층 시설물

enum Struct { NONE, FARM, DISTRICT, SHRINE, MINE, LUMBER, IRRIGATION, CAMP, FISHERY }
const STRUCT_NAMES := ["없음", "경작지", "정착지 구역", "성소", "광산", "벌목장", "관개수로", "유목 야영지", "어장"]

## 시설이 아래 식생을 다루는 방식
enum Cover { COEXIST, REPLACE, ON_WATER }
const COVER_NAMES := ["공존", "대체", "물 위"]
const STRUCT_COVER := [
	Cover.COEXIST,   # NONE
	Cover.REPLACE,   # FARM
	Cover.REPLACE,   # DISTRICT
	Cover.COEXIST,   # SHRINE
	Cover.COEXIST,   # MINE
	Cover.COEXIST,   # LUMBER
	Cover.COEXIST,   # IRRIGATION
	Cover.COEXIST,   # CAMP
	Cover.ON_WATER,  # FISHERY
]

enum State { ACTIVE, IDLE, RUIN }
const STATE_NAMES := ["사용 중", "방치", "폐허"]

## 방치, 폐허로 넘어가는 턴 수 (초안)
const IDLE_AFTER := 10
const RUIN_AFTER := 30


# ---------------------------------------------------------------- 산출량

## 식생 기본값 [식량, 생산, 교역]
const VEG_YIELD := [
	Vector3i(0, 0, 0),  # NONE (물은 아직 산출 규칙 없음)
	Vector3i(1, 1, 0),  # BARE
	Vector3i(2, 0, 0),  # GRASS
	Vector3i(1, 2, 0),  # FOREST
	Vector3i(1, 0, 0),  # WETLAND
	Vector3i(0, 0, 0),  # ICE
]
## 대체형 시설은 식생 기본값 대신 이 값을 쓴다
const REPLACE_YIELD := {
	Struct.FARM: Vector3i(3, 0, 0),
	Struct.DISTRICT: Vector3i(1, 1, 1),
}


## 강수 2000mm 이상인 열대 숲. 지금 지도의 "밀림"과 같은 기준.
static func is_jungle(gen: WorldGen, i: int) -> bool:
	return gen.veg[i] == Veg.FOREST and gen.temperature[i] >= 20.0 and gen.precip[i] >= 2000.0


static func yields(gen: WorldGen, i: int) -> Vector3i:
	var y := Vector3i.ZERO
	var v: int = gen.veg[i]
	var s: int = gen.structure[i]
	var active: bool = gen.structure_state[i] == State.ACTIVE
	if active and REPLACE_YIELD.has(s):
		y = REPLACE_YIELD[s]
	else:
		y = VEG_YIELD[v]
		if is_jungle(gen, i):
			y.y -= 2
	if gen.base[i] == Base.LAND:
		var river: bool = gen.is_river[i] == 1
		var irrigated: bool = river or gen.irrigated[i] == 1
		# 한대는 추위가 성장을 막으므로 습도 보정을 하지 않고 식량 -1 만 준다
		var m: int = gen.moist[i] if gen.temp_band[i] != TempBand.POLAR else Moist.HUMID
		match m:
			Moist.SEMI:
				y.x -= 1
				y.y += 1
			Moist.ARID:
				if not irrigated:
					y.x -= 1
		if gen.temp_band[i] == TempBand.POLAR:
			y.x -= 1
		match gen.relief[i]:
			1:
				y.x -= 1
				y.y += 1
			2:
				y.x -= 2
				y.y += 1
		if river:
			y.z += 1
	return Vector3i(maxi(y.x, 0), maxi(y.y, 0), maxi(y.z, 0))


# ---------------------------------------------------------------- 건설과 행동

## 칸 i 에 시설 s 를 지을 수 있으면 "" , 아니면 이유를 돌려준다.
static func build_block_reason(gen: WorldGen, i: int, s: int) -> String:
	if gen.structure[i] != Struct.NONE and gen.structure_state[i] != State.RUIN:
		return "이미 %s이(가) 있음" % STRUCT_NAMES[gen.structure[i]]
	var v: int = gen.veg[i]
	var land: bool = gen.base[i] == Base.LAND
	if STRUCT_COVER[s] == Cover.ON_WATER:
		if gen.base[i] == Base.SHALLOW or gen.base[i] == Base.LAKE:
			return ""
		return "얕은 바다나 호수에만 지을 수 있음"
	if not land:
		return "땅이 아님"
	if v == Veg.ICE:
		return "빙설 위에는 지을 수 없음"
	if v == Veg.WETLAND and s != Struct.MINE:
		return "습지: 먼저 배수해야 함"
	match s:
		Struct.FARM:
			if v == Veg.FOREST:
				return "숲: 먼저 벌목해야 함"
			if gen.relief[i] == 2:
				return "산지에는 경작지를 만들 수 없음"
			if gen.temp_band[i] == TempBand.POLAR:
				return "한대에는 경작지를 만들 수 없음"
			if gen.moist[i] == Moist.ARID and gen.is_river[i] == 0 and gen.irrigated[i] == 0:
				return "건조 지대: 강변이거나 관개가 필요함"
		Struct.DISTRICT:
			if v == Veg.FOREST:
				return "숲: 먼저 벌목해야 함"
			if gen.relief[i] == 2:
				return "산지에는 구역을 지을 수 없음"
		Struct.MINE:
			if gen.relief[i] == 0:
				return "구릉이나 산지에만 (광물 자원은 아직 없음)"
		Struct.LUMBER:
			if v != Veg.FOREST:
				return "숲에만 지을 수 있음"
		Struct.IRRIGATION:
			if not _near_water(gen, i):
				return "강, 호수, 관개된 칸 옆이어야 함"
	return ""


static func can_build(gen: WorldGen, i: int, s: int) -> bool:
	return build_block_reason(gen, i, s) == ""


## 시설을 짓는다. 대체형이면 식생을 걷어 낸다. 성공하면 true.
static func build(gen: WorldGen, i: int, s: int) -> bool:
	if not can_build(gen, i, s):
		return false
	gen.structure[i] = s
	gen.structure_state[i] = State.ACTIVE
	gen.idle_turns[i] = 0
	if STRUCT_COVER[s] == Cover.REPLACE:
		_set_veg(gen, i, Veg.BARE)
	if s == Struct.IRRIGATION:
		gen.irrigated[i] = 1
	return true


static func road_block_reason(gen: WorldGen, i: int) -> String:
	if gen.base[i] != Base.LAND:
		return "땅이 아님"
	if gen.veg[i] == Veg.WETLAND:
		return "습지: 먼저 배수해야 함"
	if gen.veg[i] == Veg.ICE:
		return "빙설 위에는 도로를 낼 수 없음"
	return ""


## 도로는 주 시설과 따로 두고, 식생과 공존한다.
static func build_road(gen: WorldGen, i: int) -> bool:
	if road_block_reason(gen, i) != "":
		return false
	gen.road[i] = 1
	return true


## 벌목: 숲 -> 맨땅. 얻는 생산량을 돌려준다 (숲이 아니면 0).
static func clear_forest(gen: WorldGen, i: int) -> int:
	if gen.veg[i] != Veg.FOREST:
		return 0
	_set_veg(gen, i, Veg.BARE)
	return 10


## 배수(매립): 습지 -> 초지. 버려두면 잠재 식생(습지)으로 돌아간다.
static func drain(gen: WorldGen, i: int) -> bool:
	if gen.veg[i] != Veg.WETLAND:
		return false
	_set_veg(gen, i, Veg.GRASS)
	return true


## 한 턴 진행: 시설 방치와 폐허화, 자연 천이.
## used 는 이번 턴에 도시가 쓴 칸 표시 (길이 n, 1 이면 사용).
static func advance_turn(gen: WorldGen, used: PackedByteArray) -> void:
	for i in gen.n:
		var s: int = gen.structure[i]
		if s != Struct.NONE:
			if used.size() > i and used[i] == 1:
				gen.idle_turns[i] = 0
				if gen.structure_state[i] == State.IDLE:
					gen.structure_state[i] = State.ACTIVE
			else:
				gen.idle_turns[i] += 1
				if gen.structure_state[i] == State.ACTIVE and gen.idle_turns[i] >= IDLE_AFTER:
					gen.structure_state[i] = State.IDLE
					if s == Struct.FARM:
						# 경작지는 폐허를 남기지 않고 사라진다
						_remove_structure(gen, i)
						continue
				elif gen.structure_state[i] == State.IDLE and gen.idle_turns[i] >= IDLE_AFTER + RUIN_AFTER:
					gen.structure_state[i] = State.RUIN
		_succession(gen, i)


static func _succession(gen: WorldGen, i: int) -> void:
	gen.veg_age[i] += 1
	# 대체형 시설이 서 있는 동안은 천이가 멈춘다 (폐허는 공존형이라 천이가 진행된다)
	if STRUCT_COVER[gen.structure[i]] == Cover.REPLACE and gen.structure_state[i] != State.RUIN:
		return
	var v: int = gen.veg[i]
	var pot: int = gen.potential_veg[i]
	if v == pot:
		return
	var next: int = _next_toward(v, pot)
	if next != v and gen.veg_age[i] >= int(SUCCESSION_TURNS.get(v, 20)):
		_set_veg(gen, i, next)


## 맨땅 -> 초지 -> (숲 또는 습지). 잠재 식생까지만 간다.
static func _next_toward(v: int, pot: int) -> int:
	match v:
		Veg.BARE:
			return Veg.ICE if pot == Veg.ICE else Veg.GRASS
		Veg.GRASS:
			if pot == Veg.FOREST or pot == Veg.WETLAND:
				return pot
	return v


static func _set_veg(gen: WorldGen, i: int, v: int) -> void:
	if gen.veg[i] != v:
		gen.veg[i] = v
		gen.veg_age[i] = 0


static func _remove_structure(gen: WorldGen, i: int) -> void:
	gen.structure[i] = Struct.NONE
	gen.structure_state[i] = State.ACTIVE
	gen.idle_turns[i] = 0


static func _near_water(gen: WorldGen, i: int) -> bool:
	if gen.is_river[i] == 1:
		return true
	for k in range(gen.hs.nb_offsets[i], gen.hs.nb_offsets[i + 1]):
		var j: int = gen.hs.nb_list[k]
		if gen.is_lake[j] == 1 or gen.irrigated[j] == 1:
			return true
	return false


# ---------------------------------------------------------------- 표시

## 세 층을 조합한 표시 지형 (WorldGen.B). 지도 색과 이름은 이 값을 쓴다.
static func display_biome(gen: WorldGen, i: int) -> int:
	var v: int = gen.veg[i]
	match gen.base[i]:
		Base.LAKE:
			return WorldGen.B.SEA_ICE if v == Veg.ICE else WorldGen.B.LAKE
		Base.SHALLOW:
			return WorldGen.B.SEA_ICE if v == Veg.ICE else WorldGen.B.OCEAN
		Base.DEEP:
			return WorldGen.B.SEA_ICE if v == Veg.ICE else WorldGen.B.DEEP_OCEAN
	match v:
		Veg.ICE:
			return WorldGen.B.SNOW
		Veg.WETLAND:
			return WorldGen.B.MARSH
		Veg.FOREST:
			return WorldGen.B.JUNGLE if is_jungle(gen, i) else WorldGen.B.FOREST
		Veg.BARE:
			return WorldGen.B.DESERT if gen.moist[i] == Moist.ARID else WorldGen.B.BARE
	# 초지
	if gen.temp_band[i] == TempBand.POLAR:
		return WorldGen.B.TUNDRA
	if gen.moist[i] == Moist.HUMID:
		return WorldGen.B.GRASSLAND
	return WorldGen.B.PLAINS


## "온대 습윤 구릉" 처럼 1층을 한 줄로
static func terrain_text(gen: WorldGen, i: int) -> String:
	if gen.base[i] != Base.LAND:
		return BASE_NAMES[gen.base[i]]
	return "%s %s %s" % [TEMP_NAMES[gen.temp_band[i]], MOIST_NAMES[gen.moist[i]], WorldGen.RELIEF_NAMES[gen.relief[i]]]


static func structure_text(gen: WorldGen, i: int) -> String:
	var parts: Array = []
	var s: int = gen.structure[i]
	if s != Struct.NONE:
		var t: String = STRUCT_NAMES[s]
		if gen.structure_state[i] != State.ACTIVE:
			t += " (%s)" % STATE_NAMES[gen.structure_state[i]]
		parts.append(t)
	if gen.road[i] == 1:
		parts.append("도로")
	return "없음" if parts.is_empty() else ", ".join(parts)
