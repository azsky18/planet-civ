extends RefCounted
## 채집 → 인구 상승 → 사냥(야생동물과 전투) → 식량 → 인구 상승 순환의 규칙.
## 화면과 떨어져 있어서 headless 점검(tools/game_check.gd)으로 바로 돌려 볼 수 있다.
##
## 핵심 규칙
## - 유닛 1개 = 인구 1. 부족민이 야영지를 세우면 그 부족민이 야영지 인구 1이 된다.
## - 야영지는 비용과 턴 없이 바로 세운다. 최대 인구 3.
## - 야영지 인구 1을 부족민 1명으로 내보낼 수 있다 (마지막 1명이 나가면 야영지는 사라짐). 부족민은 야영지에 합류해 인구가 될 수 있다.
## - 부족민은 야생 식량을 채집하거나 동물을 사냥해 식량을 들고 다니다 야영지에 들어가면 내려놓는다.
## - 야영지에 식량이 성장 기준만큼 모이면 턴이 끝날 때 인구가 1 는다.
## - 전투는 문명3 방식: 공격력 대 (지형 보정을 받은) 방어력으로 한 합씩 겨뤄 진 쪽이 체력 1을 잃고, 체력이 0이 되면 쓰러진다.

const L := preload("res://scripts/tile_layers.gd")

const CAMP_MAX_POP := 3
const CARRY_MAX := 10
const CAMP_MIN_GAP := 2          # 다른 야영지에서 이 칸 수 이내에는 세울 수 없다
const FOOD_PER_POP := 2          # 야영지 인구 1명이 턴마다 먹는 식량
const CAMP_BONUS := 1            # 야영지 모닥불: 턴마다 식량 +1
const START_UNITS := 2

## 성장에 필요한 식량 (지금 인구 기준)
static func growth_need(pop: int) -> int:
	return 10 + 5 * (pop - 1)


# ---------------------------------------------------------------- 채집 식량

enum Res { NONE, WHEAT, RICE, BERRY, FISH, SHELL }
const RES_NAMES := ["", "야생 밀", "야생 쌀", "나무 열매", "물고기", "조개"]
const RES_SHORT := ["", "밀", "쌀", "열매", "물고기", "조개"]
## 한 번 채집하면 그 자리의 양을 모두 거둔다 (한 턴에 끝). 야생 곡물은 사냥감(사슴 6, 멧돼지 8, 들소 12)보다
## 훨씬 적게 주는 대신 위험이 없다. 다 거둔 곳은 REGROW_TURNS 턴 뒤에 다시 차오른다.
const RES_MAX := [0, 3, 3, 2, 4, 2]
const REGROW_TURNS := [0, 12, 12, 8, 6, 8]
const RES_COLORS := [Color(0, 0, 0), Color("e6c34a"), Color("f2eedc"), Color("b0466e"), Color("4aa3e0"), Color("e89a8a")]


# ---------------------------------------------------------------- 유닛 종류

enum Side { PLAYER, PREY, PREDATOR }
## a 공격, d 방어, hp 체력, mp 이동력, food 사냥했을 때 얻는 식량, aggro 곁에 있을 때 덮칠 확률
const KINDS := {
	"tribe": {"name": "부족민", "side": Side.PLAYER, "a": 2, "d": 2, "hp": 3, "mp": 2, "food": 0, "aggro": 0.0},
	"deer": {"name": "사슴", "side": Side.PREY, "a": 0, "d": 1, "hp": 2, "mp": 2, "food": 6, "aggro": 0.0},
	"bison": {"name": "들소", "side": Side.PREY, "a": 0, "d": 2, "hp": 3, "mp": 1, "food": 12, "aggro": 0.0},
	"boar": {"name": "멧돼지", "side": Side.PREY, "a": 0, "d": 2, "hp": 2, "mp": 1, "food": 8, "aggro": 0.0},
	"wolf": {"name": "늑대", "side": Side.PREDATOR, "a": 1, "d": 1, "hp": 2, "mp": 2, "food": 2, "aggro": 0.6},
	"bear": {"name": "곰", "side": Side.PREDATOR, "a": 2, "d": 2, "hp": 3, "mp": 1, "food": 8, "aggro": 0.5},
	"tiger": {"name": "호랑이", "side": Side.PREDATOR, "a": 3, "d": 1, "hp": 3, "mp": 2, "food": 4, "aggro": 0.9},
}
const ANIMALS := ["deer", "bison", "boar", "wolf", "bear", "tiger"]
## 처음 뿌릴 때 비율 (먹잇감이 더 흔하다)
const ANIMAL_WEIGHT := {"deer": 5, "bison": 3, "boar": 3, "wolf": 2, "bear": 1, "tiger": 1}
const LAND_PER_ANIMAL := 45
const HUNT_RANGE := 3            # 포식자가 부족민을 알아채는 거리 (칸)


class Unit:
	var id: int
	var kind: String
	var tile: int
	var hp: int
	var mp: int
	var carry: int = 0
	var acted: bool = false      # 이번 턴에 움직이거나 싸우거나 채집했는지 (안 했으면 다음 턴 회복)
	var path: Array = []         # 목적지까지 남은 칸들 (여러 턴에 걸친 이동)

	func info() -> Dictionary:
		return KINDS[kind]

	func side() -> int:
		return KINDS[kind]["side"]

	func name() -> String:
		return KINDS[kind]["name"]


class Camp:
	var id: int
	var tile: int
	var pop: int = 1
	var food: int = 0
	var name: String = ""


var gen: WorldGen
var hs: HexSphere
var rng := RandomNumberGenerator.new()
var turn: int = 1
var res_kind := PackedByteArray()
var res_amt := PackedByteArray()
var res_wait := PackedByteArray()   # 다 거둔 자원이 다시 차오르기까지 남은 턴
var units: Array = []            # Unit
var occ := {}                    # 칸 -> 그 칸의 유닛들 (Array)
var camps: Array = []            # Camp
var camp_tiles := {}             # 칸 -> Camp
var events: Array = []              # 최근 사건 (문자열)
var fights: Array = []              # 아직 화면에 보여 주지 않은 전투 기록 (game.gd 가 한 합씩 재생하고 비운다)
var start_tile: int = -1
var animal_target: int = 0
var _next_id: int = 1
var _camp_names := ["강가", "언덕", "큰나무", "바위", "샘", "들판", "갈대", "소나무", "모래톱", "붉은흙"]
var game_over := false


func setup(world: WorldGen, seed_v: int) -> void:
	gen = world
	hs = world.hs
	rng.seed = seed_v
	res_kind.resize(gen.n)
	res_amt.resize(gen.n)
	res_wait.resize(gen.n)
	_place_resources()
	_pick_start()
	_place_animals()
	_ensure_start_food()
	for _k in START_UNITS:
		spawn("tribe", start_tile)
	note("부족민 %d명이 새 땅에 닿았습니다. 한 명이 야영지를 세우고, 다른 한 명은 식량을 모아 오세요." % START_UNITS)


## 받침에 맞는 조사를 붙인다. p 는 "이", "을", "은", "과", "으로" 중 하나.
static func josa(word: String, p: String) -> String:
	var has_final := false
	if word.length() > 0:
		var c: int = word.unicode_at(word.length() - 1)
		if c >= 0xAC00 and c <= 0xD7A3:
			has_final = (c - 0xAC00) % 28 != 0
		elif c >= 48 and c <= 57:
			has_final = "013678".contains(char(c))
	var pairs := {"이": ["이", "가"], "을": ["을", "를"], "은": ["은", "는"], "과": ["과", "와"], "으로": ["으로", "로"]}
	return word + (pairs[p][0] if has_final else pairs[p][1])


func note(msg: String) -> void:
	events.append("[%d턴] %s" % [turn, msg])
	if events.size() > 40:
		events.pop_front()


# ---------------------------------------------------------------- 지형 판정

func is_land(i: int) -> bool:
	return gen.base[i] == L.Base.LAND


func move_cost(i: int) -> int:
	if gen.relief[i] == 2:
		return 3
	var v: int = gen.veg[i]
	if gen.relief[i] == 1 or v == L.Veg.FOREST or v == L.Veg.WETLAND or v == L.Veg.ICE:
		return 2
	return 1


## 문명3 방어 보정: 구릉 +50%, 산지 +100%, 숲·밀림·습지 +25%, 강변 +25%
func terrain_defense(i: int) -> float:
	var m: float = 1.0
	if gen.relief[i] == 1:
		m += 0.5
	elif gen.relief[i] == 2:
		m += 1.0
	var v: int = gen.veg[i]
	if v == L.Veg.FOREST or v == L.Veg.WETLAND:
		m += 0.25
	if gen.is_river[i] == 1:
		m += 0.25
	return m


func neighbors(i: int) -> PackedInt32Array:
	return hs.nb_list.slice(hs.nb_offsets[i], hs.nb_offsets[i + 1])


func is_adjacent(a: int, b: int) -> bool:
	return neighbors(a).has(b)


## 칸 a 에서 depth 칸 이내 (땅·물 구분 없이)
func within(a: int, depth: int) -> Dictionary:
	var seen := {a: 0}
	var frontier: Array = [a]
	for dd in depth:
		var nxt: Array = []
		for t in frontier:
			for j in neighbors(t):
				if not seen.has(j):
					seen[j] = dd + 1
					nxt.append(j)
		frontier = nxt
	return seen


func habitat_ok(kind: String, i: int) -> bool:
	if not is_land(i) or gen.relief[i] == 2:
		return false
	var v: int = gen.veg[i]
	var tb: int = gen.temp_band[i]
	match kind:
		"deer":
			return (v == L.Veg.FOREST or v == L.Veg.GRASS) and (tb == L.TempBand.TEMPERATE or tb == L.TempBand.BOREAL)
		"bison":
			return v == L.Veg.GRASS and gen.relief[i] == 0 and tb != L.TempBand.POLAR
		"boar":
			return v == L.Veg.FOREST and (tb == L.TempBand.TEMPERATE or tb == L.TempBand.TROPICAL)
		"wolf":
			return (v == L.Veg.FOREST or v == L.Veg.GRASS or v == L.Veg.BARE) and tb != L.TempBand.TROPICAL
		"bear":
			return v == L.Veg.FOREST and (tb == L.TempBand.TEMPERATE or tb == L.TempBand.BOREAL)
		"tiger":
			return (v == L.Veg.FOREST or v == L.Veg.WETLAND) and (tb == L.TempBand.TROPICAL or tb == L.TempBand.TEMPERATE)
	return false


# ---------------------------------------------------------------- 배치

func _res_for(i: int) -> int:
	var b: int = gen.base[i]
	if b == L.Base.LAND:
		var v: int = gen.veg[i]
		var tb: int = gen.temp_band[i]
		if gen.relief[i] == 2 or tb == L.TempBand.POLAR:
			return Res.NONE
		if v == L.Veg.GRASS and tb == L.TempBand.TEMPERATE and gen.moist[i] != L.Moist.ARID \
				and rng.randf() < (0.05 if gen.moist[i] == L.Moist.SEMI else 0.03):
			return Res.WHEAT
		if gen.temperature[i] >= 16.0 and gen.moist[i] == L.Moist.HUMID and gen.relief[i] == 0 \
				and (v == L.Veg.WETLAND or (v == L.Veg.GRASS and gen.is_river[i] == 1)) and rng.randf() < 0.18:
			return Res.RICE
		if v == L.Veg.FOREST and rng.randf() < 0.06:
			return Res.BERRY
		return Res.NONE
	if gen.temp_band[i] == L.TempBand.POLAR or gen.veg[i] == L.Veg.ICE:
		return Res.NONE
	if b == L.Base.LAKE:
		return Res.FISH if rng.randf() < 0.15 else Res.NONE
	if b == L.Base.SHALLOW:
		var coast := false
		for j in neighbors(i):
			coast = coast or is_land(j)
		if coast and rng.randf() < 0.06:
			return Res.SHELL
		if rng.randf() < 0.05:
			return Res.FISH
	return Res.NONE


func _place_resources() -> void:
	for i in gen.n:
		var r: int = _res_for(i)
		res_kind[i] = r
		res_amt[i] = RES_MAX[r]


func _land_count() -> int:
	var c: int = 0
	for i in gen.n:
		if is_land(i):
			c += 1
	return c


func _pick_start() -> void:
	var best: int = -1
	var best_score: float = -1.0
	for _t in 600:
		var i: int = rng.randi() % gen.n
		if not is_land(i) or gen.relief[i] != 0 or gen.veg[i] == L.Veg.WETLAND or gen.veg[i] == L.Veg.ICE:
			continue
		var tb: int = gen.temp_band[i]
		if tb != L.TempBand.TEMPERATE and tb != L.TempBand.TROPICAL:
			continue
		var area: Dictionary = within(i, 4)
		var land: int = 0
		var food: float = 0.0
		for j in area:
			if is_land(j):
				land += 1
			if res_kind[j] != Res.NONE and area[j] <= 3:
				food += 1.0
			if is_land(j) and area[j] <= 2:
				food += L.yields(gen, j).x * 0.3
		if land < 40:
			continue
		var score: float = food + land * 0.05
		if score > best_score:
			best_score = score
			best = i
	if best < 0:
		for i in gen.n:
			if is_land(i) and gen.relief[i] == 0:
				best = i
				break
	start_tile = best


func _place_animals() -> void:
	animal_target = maxi(_land_count() / LAND_PER_ANIMAL, 20)
	var tries: int = 0
	while count_animals() < animal_target and tries < animal_target * 40:
		tries += 1
		_try_spawn_animal(true)
	# 시작 지점 가까이에는 포식자를 두지 않고, 먹잇감은 두 마리 이상 둔다
	var near: Dictionary = within(start_tile, 3)
	for u in units.duplicate():
		if u.side() == Side.PREDATOR and near.has(u.tile):
			remove_unit(u)
	var prey: int = 0
	for u in units:
		if u.side() == Side.PREY and within(start_tile, 4).has(u.tile):
			prey += 1
	var ring: Dictionary = within(start_tile, 4)
	for j in ring:
		if prey >= 2:
			break
		if ring[j] >= 2 and is_land(j) and unit_at(j) == null and gen.relief[j] != 2:
			var kind: String = "deer"
			if habitat_ok("bison", j):
				kind = "bison"
			elif habitat_ok("boar", j):
				kind = "boar"
			spawn(kind, j)
			prey += 1


func _ensure_start_food() -> void:
	var near: Dictionary = within(start_tile, 2)
	var have: int = 0
	for j in near:
		if res_kind[j] != Res.NONE and j != start_tile:
			have += 1
	for j in near:
		if have >= 3:
			break
		if j == start_tile or res_kind[j] != Res.NONE:
			continue
		var r: int = Res.NONE
		if is_land(j) and gen.relief[j] != 2:
			if gen.veg[j] == L.Veg.FOREST:
				r = Res.BERRY
			elif gen.veg[j] == L.Veg.GRASS:
				r = Res.WHEAT if gen.temperature[j] < 18.0 else Res.RICE
		elif gen.base[j] == L.Base.SHALLOW:
			r = Res.SHELL
		elif gen.base[j] == L.Base.LAKE:
			r = Res.FISH
		if r != Res.NONE:
			res_kind[j] = r
			res_amt[j] = RES_MAX[r]
			have += 1


func count_animals() -> int:
	var c: int = 0
	for u in units:
		if u.side() != Side.PLAYER:
			c += 1
	return c


func _pick_animal_kind() -> String:
	var total: int = 0
	for k in ANIMAL_WEIGHT:
		total += ANIMAL_WEIGHT[k]
	var r: int = rng.randi() % total
	for k in ANIMAL_WEIGHT:
		r -= ANIMAL_WEIGHT[k]
		if r < 0:
			return k
	return "deer"


## 무작위 칸 하나에 동물을 세운다. 부족민이나 야영지 곁(4칸 이내)은 initial 이 아니면 피한다.
func _try_spawn_animal(initial: bool) -> bool:
	var i: int = rng.randi() % gen.n
	var kind: String = _pick_animal_kind()
	if not habitat_ok(kind, i) or unit_at(i) != null or camp_at(i) != null:
		return false
	if not initial:
		var c: Vector3 = hs.centers[i]
		var lim: float = cos(hs.spacing * 4.5)
		for u in units:
			if u.side() == Side.PLAYER and hs.centers[u.tile].dot(c) > lim:
				return false
		for cp in camps:
			if hs.centers[cp.tile].dot(c) > lim:
				return false
	spawn(kind, i)
	return true


func spawn(kind: String, tile: int) -> Unit:
	var u := Unit.new()
	u.id = _next_id
	_next_id += 1
	u.kind = kind
	u.tile = tile
	u.hp = KINDS[kind]["hp"]
	u.mp = KINDS[kind]["mp"]
	units.append(u)
	_occ_add(u)
	return u


func _occ_add(u: Unit) -> void:
	if not occ.has(u.tile):
		occ[u.tile] = []
	occ[u.tile].append(u)


func _occ_del(u: Unit) -> void:
	var arr: Array = occ.get(u.tile, [])
	arr.erase(u)
	if arr.is_empty():
		occ.erase(u.tile)


func remove_unit(u: Unit) -> void:
	if units.has(u):
		_occ_del(u)
		units.erase(u)


func _move_to(u: Unit, j: int) -> void:
	_occ_del(u)
	u.tile = j
	_occ_add(u)


# ---------------------------------------------------------------- 조회

## 그 칸의 동물 (한 칸에 한 마리)
func animal_at(i: int) -> Unit:
	for u in occ.get(i, []):
		if u.side() != Side.PLAYER:
			return u
	return null


func players_at(i: int) -> Array:
	var out: Array = []
	for u in occ.get(i, []):
		if u.side() == Side.PLAYER:
			out.append(u)
	return out


func unit_at(i: int) -> Unit:
	var arr: Array = occ.get(i, [])
	return arr[0] if not arr.is_empty() else null


func camp_at(i: int) -> Camp:
	return camp_tiles.get(i, null)


func player_units() -> Array:
	var out: Array = []
	for u in units:
		if u.side() == Side.PLAYER:
			out.append(u)
	return out


func population() -> int:
	var p: int = player_units().size()
	for c in camps:
		p += c.pop
	return p


# ---------------------------------------------------------------- 야영지

func camp_block_reason(u: Unit) -> String:
	var i: int = u.tile
	if not is_land(i):
		return "땅이 아님"
	if gen.veg[i] == L.Veg.ICE:
		return "빙설 위에는 세울 수 없음"
	if camp_at(i) != null:
		return "이미 야영지가 있음"
	var near: Dictionary = within(i, CAMP_MIN_GAP)
	for c in camps:
		if near.has(c.tile):
			return "다른 야영지와 너무 가까움 (%d칸 이내)" % CAMP_MIN_GAP
	return ""


## 부족민이 그 자리에 야영지를 세우고 야영지 인구 1이 된다. 들고 있던 식량은 야영지 창고로 간다.
func found_camp(u: Unit) -> Camp:
	if camp_block_reason(u) != "":
		return null
	var c := Camp.new()
	c.id = _next_id
	_next_id += 1
	c.tile = u.tile
	c.pop = 1
	c.food = u.carry
	c.name = _camp_names[camps.size() % _camp_names.size()] + " 야영지"
	camps.append(c)
	camp_tiles[c.tile] = c
	remove_unit(u)
	if L.can_build(gen, c.tile, L.Struct.CAMP):
		L.build(gen, c.tile, L.Struct.CAMP)
		gen.refresh_biome(c.tile)
	note("%s 세웠습니다. 부족민 1명이 야영지 인구가 되었습니다." % josa(c.name, "을"))
	return c


func join_block_reason(u: Unit) -> String:
	var c: Camp = camp_at(u.tile)
	if c == null:
		return "야영지 안에 있어야 함"
	if c.pop >= CAMP_MAX_POP:
		return "야영지 인구가 가득 참 (최대 %d)" % CAMP_MAX_POP
	return ""


func join_camp(u: Unit) -> bool:
	if join_block_reason(u) != "":
		return false
	var c: Camp = camp_at(u.tile)
	c.food += u.carry
	c.pop += 1
	remove_unit(u)
	note("부족민이 %s에 합류했습니다 (인구 %d)." % [c.name, c.pop])
	return true


func release_block_reason(c: Camp) -> String:
	if c.pop < 1:
		return "인구가 없음"
	return ""


## 야영지 인구 1을 부족민 1명으로 내보낸다. 마지막 1명이 나가면 야영지는 사라지고,
## 창고의 식량은 나가는 부족민이 들 수 있는 만큼 들고 간다.
func release_unit(c: Camp) -> Unit:
	if release_block_reason(c) != "":
		return null
	c.pop -= 1
	var u: Unit = spawn("tribe", c.tile)
	if c.pop > 0:
		note("%s에서 부족민 1명이 나왔습니다 (인구 %d)." % [c.name, c.pop])
		return u
	u.carry = mini(c.food, CARRY_MAX)
	camps.erase(c)
	camp_tiles.erase(c.tile)
	if gen.structure[c.tile] == L.Struct.CAMP:
		L._remove_structure(gen, c.tile)
		gen.refresh_biome(c.tile)
	note("%s의 마지막 사람이 떠나 야영지가 사라졌습니다 (식량 %d 챙김)." % [c.name, u.carry])
	return u


## 야영지 사람들이 일하는 칸: 야영지 칸 + 인구 수 - 1 만큼 둘레에서 식량이 많은 칸
func camp_worked(c: Camp) -> Array:
	var out: Array = [c.tile]
	var cand: Array = []
	for j in neighbors(c.tile):
		if is_land(j) and camp_at(j) == null:
			cand.append([L.yields(gen, j).x, j])
	cand.sort_custom(func(a, b): return a[0] > b[0])
	for k in mini(c.pop - 1, cand.size()):
		out.append(cand[k][1])
	return out


## 야영지의 턴당 식량 (일하는 칸 산출 + 모닥불 - 먹는 양)
func camp_net(c: Camp) -> int:
	var f: int = CAMP_BONUS
	for j in camp_worked(c):
		f += L.yields(gen, j).x
	f -= FOOD_PER_POP * c.pop
	# 혼자 남은 야영지도 둘레를 뒤져 조금씩은 모은다 (부족민을 다 잃어도 다시 일어설 수 있게)
	if c.pop == 1:
		f = maxi(f, 1)
	return f


# ---------------------------------------------------------------- 채집

## 부족민이 채집할 수 있는 칸: 자기 칸, 없으면 둘레의 물 칸 (물고기·조개)
func gather_target(u: Unit) -> int:
	if res_kind[u.tile] != Res.NONE and res_amt[u.tile] > 0:
		return u.tile
	var best: int = -1
	for j in neighbors(u.tile):
		if not is_land(j) and res_kind[j] != Res.NONE and res_amt[j] > 0:
			if best < 0 or res_amt[j] > res_amt[best]:
				best = j
	return best


func gather_block_reason(u: Unit) -> String:
	if u.mp <= 0:
		return "이번 턴 이동력을 다 씀"
	if u.carry >= CARRY_MAX:
		return "더 들 수 없음 (야영지에 내려놓으세요)"
	if gather_target(u) < 0:
		var t: int = u.tile
		if res_kind[t] != Res.NONE:
			return "%s 다 거둠 (%d턴 뒤 다시 자람)" % [josa(RES_NAMES[res_kind[t]], "은"), res_wait[t]]
		return "이 칸이나 둘레 물가에 채집할 식량이 없음"
	return ""


## 채집하면 남은 이동력을 모두 쓴다. 얻은 양을 돌려준다.
func gather(u: Unit) -> int:
	if gather_block_reason(u) != "":
		return 0
	var t: int = gather_target(u)
	var got: int = mini(res_amt[t], CARRY_MAX - u.carry)
	res_amt[t] = 0
	res_wait[t] = REGROW_TURNS[res_kind[t]]
	u.carry += got
	u.mp = 0
	u.acted = true
	u.path.clear()
	var c: Camp = camp_at(u.tile)
	if c != null:
		_deposit(u, c)
	note("%s 식량 %d 거뒀습니다 (%d턴 뒤 다시 자람)." % [RES_NAMES[res_kind[t]] + "에서", got, res_wait[t]])
	return got


func _deposit(u: Unit, c: Camp) -> void:
	if u.carry <= 0:
		return
	c.food += u.carry
	note("식량 %d, %s에 내려놓았습니다 (창고 %d/%d)." % [u.carry, c.name, c.food, growth_need(c.pop)])
	u.carry = 0


# ---------------------------------------------------------------- 이동

## 플레이어 부족민이 칸 j 로 들어갈 수 있는가 (동물이 있으면 공격 대상이지 이동 대상이 아님)
func can_enter(u: Unit, j: int) -> bool:
	if not is_land(j):
		return false
	if u.side() == Side.PLAYER:
		return animal_at(j) == null
	# 동물: 서식지 안에서만, 야영지와 다른 유닛이 있는 칸은 들어가지 않는다
	return habitat_ok(u.kind, j) and unit_at(j) == null and camp_at(j) == null


## 이웃 칸으로 한 칸 움직인다. 이동력이 조금이라도 남아 있으면 들어갈 수 있다 (모자라면 0이 된다).
func step(u: Unit, j: int) -> bool:
	if u.mp <= 0 or not is_adjacent(u.tile, j) or not can_enter(u, j):
		return false
	_move_to(u, j)
	u.mp = maxi(u.mp - move_cost(j), 0)
	u.acted = true
	if u.side() == Side.PLAYER:
		var c: Camp = camp_at(j)
		if c != null:
			_deposit(u, c)
	return true


## 땅 위 최단 경로 (이동 비용 기준). 목적지에 동물이 있으면 그 곁까지.
func find_path(u: Unit, goal: int) -> Array:
	if goal == u.tile or not is_land(goal):
		return []
	var dist := {u.tile: 0}
	var prev := {}
	var open: Array = [[0, u.tile]]
	var gc: Vector3 = hs.centers[goal]
	var lim: int = 6000
	while not open.is_empty() and lim > 0:
		lim -= 1
		var cur: int = _heap_pop(open)
		if cur == goal:
			break
		for j in neighbors(cur):
			if not is_land(j):
				continue
			if j != goal and animal_at(j) != null:
				continue
			var nd: int = dist[cur] + move_cost(j)
			if not dist.has(j) or nd < dist[j]:
				dist[j] = nd
				prev[j] = cur
				var hcost: float = acos(clampf(hs.centers[j].dot(gc), -1.0, 1.0)) / hs.spacing
				_heap_push(open, [nd + hcost, j])
	if not prev.has(goal):
		return []
	var path: Array = []
	var t: int = goal
	while t != u.tile:
		path.push_front(t)
		t = prev[t]
	return path


static func _heap_push(h: Array, item: Array) -> void:
	h.append(item)
	var k: int = h.size() - 1
	while k > 0:
		var p: int = (k - 1) >> 1
		if h[p][0] <= h[k][0]:
			break
		var t: Array = h[p]
		h[p] = h[k]
		h[k] = t
		k = p


static func _heap_pop(h: Array) -> int:
	var top: int = h[0][1]
	var last: Array = h.pop_back()
	if not h.is_empty():
		h[0] = last
		var k: int = 0
		var n: int = h.size()
		while true:
			var l: int = k * 2 + 1
			var r: int = l + 1
			var m: int = k
			if l < n and h[l][0] < h[m][0]:
				m = l
			if r < n and h[r][0] < h[m][0]:
				m = r
			if m == k:
				break
			var t: Array = h[m]
			h[m] = h[k]
			h[k] = t
			k = m
	return top


## 목적지로 가는 길을 정하고 이번 턴 이동력만큼 간다. 목적지가 이웃한 동물이면 공격한다.
## 결과 문자열 (빈 문자열이면 아무 일도 없음)
func order_move(u: Unit, goal: int) -> String:
	var a: Unit = animal_at(goal)
	if a != null and is_adjacent(u.tile, goal):
		if u.mp <= 0:
			return "이번 턴 이동력을 다 씀"
		return attack(u, a)
	u.path = find_path(u, goal)
	if u.path.is_empty():
		return "갈 수 있는 길이 없음"
	follow_path(u)
	return ""


func follow_path(u: Unit) -> void:
	while u.mp > 0 and not u.path.is_empty():
		var nxt: int = u.path[0]
		if animal_at(nxt) != null:
			# 길이 막혔다. 목적지의 동물이면 곁에 닿은 것이니 공격은 직접 시킨다.
			u.path.clear()
			break
		if not step(u, nxt):
			u.path.clear()
			break
		u.path.pop_front()


# ---------------------------------------------------------------- 전투 (문명3 방식)

func defense_of(u: Unit) -> float:
	var d: float = float(u.info()["d"]) * terrain_defense(u.tile)
	if u.side() == Side.PLAYER and camp_at(u.tile) != null:
		d *= 1.25
	return d


## 한 합에 공격자가 이길 확률 p 로, 체력 ha 대 hd 의 싸움에서 공격자가 이길 확률
static func win_chance(p: float, ha: int, hd: int) -> float:
	# f[a][d] = 공격자 체력 a, 방어자 체력 d 남았을 때 공격자 승리 확률
	var f: Array = []
	for a in ha + 1:
		var row: Array = []
		row.resize(hd + 1)
		f.append(row)
	for a in ha + 1:
		for d in hd + 1:
			if d == 0 and a > 0:
				f[a][d] = 1.0
			elif a == 0:
				f[a][d] = 0.0
			else:
				f[a][d] = 0.0
	for a in range(1, ha + 1):
		for d in range(1, hd + 1):
			f[a][d] = p * f[a][d - 1] + (1.0 - p) * f[a - 1][d]
	return f[ha][hd]


func attack_odds(att: Unit, def: Unit) -> float:
	var a: float = float(att.info()["a"])
	if a <= 0.0:
		return 0.0
	var d: float = defense_of(def)
	return win_chance(a / (a + d), att.hp, def.hp)


## 공격자가 이기면 true 대신 결과 문장을 돌려준다. 진 쪽은 사라진다.
func attack(att: Unit, def: Unit) -> String:
	var a: float = float(att.info()["a"])
	if a <= 0.0 or att.mp <= 0:
		return ""
	var d: float = defense_of(def)
	var p: float = a / (a + d)
	var rounds: int = 0
	# 화면에서 한 합씩 보여 주도록 합마다 누가 맞았는지 남긴다 (true = 방어 쪽이 한 칸 깎임)
	var fight := {"att": att.id, "def": def.id, "att_tile": att.tile, "def_tile": def.tile,
			"att_hp": att.hp, "def_hp": def.hp, "rounds": []}
	while att.hp > 0 and def.hp > 0 and rounds < 100:
		rounds += 1
		var hit: bool = rng.randf() < p
		fight["rounds"].append(hit)
		if hit:
			def.hp -= 1
		else:
			att.hp -= 1
	fights.append(fight)
	att.mp = maxi(att.mp - 1, 0)
	att.acted = true
	def.acted = true   # 공격받은 턴은 쉰 것으로 치지 않는다
	att.path.clear()
	var msg: String
	var winner: Unit = att if def.hp <= 0 else def
	var loser: Unit = def if def.hp <= 0 else att
	remove_unit(loser)
	if winner.side() == Side.PLAYER:
		if winner == att:
			msg = "%s %s 쓰러뜨렸습니다" % [josa(winner.name(), "이"), josa(loser.name(), "을")]
		else:
			msg = "%s 덮쳐 왔지만 %s 물리쳤습니다" % [josa(loser.name(), "이"), josa(winner.name(), "이")]
		msg += " (남은 체력 %d/%d)." % [winner.hp, winner.info()["hp"]]
		var got: int = _take_meat(winner, int(loser.info()["food"]))
		if got > 0:
			msg += " 고기 %d 얻었습니다." % got
	elif winner == att:
		msg = "%s %s 덮쳐 쓰러뜨렸습니다." % [josa(winner.name(), "이"), josa(loser.name(), "을")]
	else:
		msg = "%s %s에게 덤볐다가 쓰러졌습니다." % [josa(loser.name(), "이"), winner.name()]
	note(msg)
	return msg


## 사냥한 고기를 사냥꾼과 같은 칸의 부족민들이 나눠 든다. 남는 것은 버린다.
func _take_meat(hunter: Unit, food: int) -> int:
	var got: int = 0
	var carriers: Array = [hunter]
	for o in players_at(hunter.tile):
		if o != hunter:
			carriers.append(o)
	for c in carriers:
		var take: int = mini(food - got, CARRY_MAX - c.carry)
		c.carry += take
		got += take
	var cp: Camp = camp_at(hunter.tile)
	if cp != null:
		for c in carriers:
			_deposit(c, cp)
	return got


# ---------------------------------------------------------------- 턴

## 플레이어가 턴을 마친다: 야영지 성장, 동물 행동, 재생, 다음 턴 준비.
func end_turn() -> void:
	_camps_grow()
	_animals_act()
	_regrow()
	turn += 1
	_start_player_turn()
	if population() == 0 and not game_over:
		game_over = true
		note("부족이 모두 사라졌습니다.")


func _camps_grow() -> void:
	for c in camps:
		var need: int = growth_need(c.pop)
		c.food += camp_net(c)
		if c.food < 0:
			if c.pop > 1:
				c.pop -= 1
				c.food = 0
				note("%s에 식량이 모자라 인구가 줄었습니다 (인구 %d)." % [c.name, c.pop])
			else:
				c.food = 0
		elif c.food >= need:
			if c.pop < CAMP_MAX_POP:
				c.food -= need
				c.pop += 1
				note("%s의 인구가 늘었습니다 (인구 %d)." % [c.name, c.pop])
			else:
				c.food = need
		if c.pop >= CAMP_MAX_POP and c.food >= growth_need(c.pop):
			c.food = growth_need(c.pop)


func _animals_act() -> void:
	for u in units.duplicate():
		if not units.has(u) or u.side() == Side.PLAYER:
			continue
		u.mp = u.info()["mp"]
		if u.side() == Side.PREDATOR:
			_predator_act(u)
		else:
			_prey_act(u)
		if units.has(u):
			u.hp = mini(u.hp + 1, int(u.info()["hp"]))


func _prey_act(u: Unit) -> void:
	var threatened := false
	for j in neighbors(u.tile):
		if not players_at(j).is_empty():
			threatened = true
	# 사슴은 부족민이 곁에 오면 달아나려 한다
	if threatened and u.kind == "deer" and rng.randf() < 0.5:
		for _s in u.mp:
			var best: int = -1
			var best_d: float = 99.0
			for j in neighbors(u.tile):
				if can_enter(u, j):
					var dsum: float = 0.0
					for p in player_units():
						dsum -= hs.centers[p.tile].dot(hs.centers[j])
					if best < 0 or dsum < best_d:
						best = j
						best_d = dsum
			if best >= 0:
				step(u, best)
		return
	if rng.randf() < 0.4:
		var opts: Array = []
		for j in neighbors(u.tile):
			if can_enter(u, j):
				opts.append(j)
		if not opts.is_empty():
			step(u, opts[rng.randi() % opts.size()])


func _predator_act(u: Unit) -> void:
	for _s in 3:
		if u.mp <= 0:
			return
		# 곁의 부족민 (야영지 안은 불 때문에 덤비지 않는다)
		for j in neighbors(u.tile):
			var ps: Array = players_at(j)
			if ps.is_empty() or camp_at(j) != null:
				continue
			if rng.randf() < float(u.info()["aggro"]):
				var def: Unit = ps[0]
				for p in ps:
					if defense_of(p) * p.hp > defense_of(def) * def.hp:
						def = p
				attack(u, def)
			return
		# 가까운 부족민 쪽으로 다가간다
		var area: Dictionary = within(u.tile, HUNT_RANGE)
		var target: int = -1
		for p in player_units():
			if area.has(p.tile) and camp_at(p.tile) == null:
				if target < 0 or area[p.tile] < area[target]:
					target = p.tile
		if target < 0:
			if rng.randf() < 0.4:
				var opts: Array = []
				for j in neighbors(u.tile):
					if can_enter(u, j):
						opts.append(j)
				if not opts.is_empty():
					step(u, opts[rng.randi() % opts.size()])
			return
		var best: int = -1
		var bd: float = -2.0
		for j in neighbors(u.tile):
			if can_enter(u, j):
				var dd: float = hs.centers[j].dot(hs.centers[target])
				if dd > bd:
					bd = dd
					best = j
		if best < 0 or not step(u, best):
			return


func _regrow() -> void:
	for i in gen.n:
		if res_wait[i] > 0:
			res_wait[i] -= 1
			if res_wait[i] == 0:
				res_amt[i] = RES_MAX[res_kind[i]]
	var missing: int = animal_target - count_animals()
	if missing > 0:
		var want: int = maxi(1, missing / 10)
		var tries: int = 0
		while want > 0 and tries < 200:
			tries += 1
			if _try_spawn_animal(false):
				want -= 1


func _start_player_turn() -> void:
	for u in player_units():
		var full: int = u.info()["hp"]
		# 제자리에서 쉬면 (이번 턴에 움직이지도 싸우지도 채집하지도 않았으면) 한 턴에 한 칸이 찬다
		if not u.acted:
			u.hp = mini(u.hp + 1, full)
		u.mp = u.info()["mp"]
		u.acted = false
	for u in player_units():
		if not u.path.is_empty():
			follow_path(u)
