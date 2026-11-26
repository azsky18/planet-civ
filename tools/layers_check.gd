extends SceneTree

const L := preload("res://scripts/tile_layers.gd")
## 타일 레이어 규칙 점검: godot --headless -s tools/layers_check.gd
## 식생 비율, 산출량 예시, 건설 규칙, 천이를 출력하고 기대와 다르면 FAIL 을 찍는다.

var fails: int = 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("ok   " if ok else "FAIL ") + what)


func find(g: WorldGen, pred: Callable) -> int:
	for i in g.n:
		if pred.call(i):
			return i
	return -1


func _init() -> void:
	var hs := HexSphere.new()
	hs.build(6)
	var g := WorldGen.new()
	g.seed_value = 1
	g.generate(hs)


	# 식생 비율
	var counts := {}
	var land: int = 0
	for i in g.n:
		if g.base[i] == L.Base.LAND:
			land += 1
			counts[g.veg[i]] = counts.get(g.veg[i], 0) + 1
	var out := "육지 식생: "
	for v in counts:
		out += "%s %d%%, " % [L.VEG_NAMES[v], int(100.0 * counts[v] / land)]
	print(out)

	# 표시 지형이 레이어에서 나오는지
	var mismatch: int = 0
	for i in g.n:
		if g.biome[i] != L.display_biome(g, i):
			mismatch += 1
	check(mismatch == 0, "표시 지형 = 레이어 조합")

	# 산출량: 문명3 기본값과 맞는지
	var flat := func(i): return g.base[i] == L.Base.LAND and g.relief[i] == 0 and g.is_river[i] == 0
	var gl := find(g, func(i): return flat.call(i) and g.biome[i] == WorldGen.B.GRASSLAND)
	check(L.yields(g, gl) == Vector3i(2, 0, 0), "초원(온대 습윤 초지) 2/0/0 -> %s" % L.yields(g, gl))
	var pl := find(g, func(i): return flat.call(i) and g.biome[i] == WorldGen.B.PLAINS)
	check(L.yields(g, pl) == Vector3i(1, 1, 0), "평원(반건조 초지) 1/1/0 -> %s" % L.yields(g, pl))
	var de := find(g, func(i): return flat.call(i) and g.biome[i] == WorldGen.B.DESERT)
	check(L.yields(g, de) == Vector3i(0, 1, 0), "사막(건조 맨땅) 0/1/0 -> %s" % L.yields(g, de))
	var tu := find(g, func(i): return flat.call(i) and g.biome[i] == WorldGen.B.TUNDRA)
	check(L.yields(g, tu) == Vector3i(1, 0, 0), "툰드라(한대 초지) 1/0/0 -> %s" % L.yields(g, tu))
	var hf := find(g, func(i): return g.base[i] == L.Base.LAND and g.relief[i] == 1 and g.is_river[i] == 0 and g.biome[i] == WorldGen.B.FOREST and g.moist[i] == L.Moist.HUMID)
	check(L.yields(g, hf) == Vector3i(0, 3, 0), "구릉 숲 0/3/0 -> %s" % L.yields(g, hf))

	# 도로는 숲과 공존
	var fo := find(g, func(i): return flat.call(i) and g.veg[i] == L.Veg.FOREST and g.temp_band[i] == L.TempBand.TEMPERATE)
	check(L.build_road(g, fo) and g.veg[fo] == L.Veg.FOREST, "숲에 도로: 식생 그대로")
	# 숲에 경작지는 벌목 먼저
	check(not L.can_build(g, fo, L.Struct.FARM), "숲에 경작지 불가: " + L.build_block_reason(g, fo, L.Struct.FARM))
	check(L.clear_forest(g, fo) > 0 and g.veg[fo] == L.Veg.BARE, "벌목: 숲 -> 맨땅")
	check(L.build(g, fo, L.Struct.FARM), "벌목 뒤 경작지 건설")
	check(L.yields(g, fo).x == 3, "경작지 식량 3 -> %s" % L.yields(g, fo))
	g.refresh_biome(fo)

	# 습지는 배수 먼저
	var we := find(g, func(i): return g.veg[i] == L.Veg.WETLAND and g.temp_band[i] != L.TempBand.POLAR and g.relief[i] < 2)
	check(not L.build_road(g, we), "습지에 도로 불가: " + L.road_block_reason(g, we))
	check(not L.can_build(g, we, L.Struct.FARM), "습지에 경작지 불가")
	check(L.drain(g, we) and g.veg[we] == L.Veg.GRASS, "배수: 습지 -> 초지")
	check(L.build_road(g, we), "배수 뒤 도로")

	# 건조 지대 경작지는 강이 필요
	check(not L.can_build(g, de, L.Struct.FARM), "강 없는 사막에 경작지 불가")
	var rd := find(g, func(i): return g.base[i] == L.Base.LAND and g.moist[i] == L.Moist.ARID and g.is_river[i] == 1 and g.relief[i] == 0 and g.temp_band[i] != L.TempBand.POLAR)
	if rd >= 0:
		check(L.can_build(g, rd, L.Struct.FARM), "강변 사막에 경작지 가능")
		L.build(g, rd, L.Struct.FARM)
		check(L.yields(g, rd) == Vector3i(3, 0, 1), "강변 건조 경작지 3/0/1 -> %s" % L.yields(g, rd))

	# 천이: 경작지 방치 -> 사라짐 -> 맨땅 -> 초지 -> 숲, 배수한 습지는 다시 습지
	var used := PackedByteArray()
	used.resize(g.n)
	for t in 80:
		L.advance_turn(g, used)
	check(g.structure[fo] == L.Struct.NONE, "버려진 경작지가 사라짐")
	check(g.veg[fo] == L.Veg.FOREST, "버려진 땅에 숲이 돌아옴 -> %s" % L.VEG_NAMES[g.veg[fo]])
	check(g.veg[we] == L.Veg.WETLAND, "배수한 습지를 버려두면 다시 습지 -> %s" % L.VEG_NAMES[g.veg[we]])
	check(g.road[fo] == 1, "도로는 남음")

	# 구역은 방치 -> 폐허, 폐허 아래로 천이
	var ds := find(g, func(i): return flat.call(i) and g.veg[i] == L.Veg.GRASS and g.potential_veg[i] == L.Veg.GRASS and g.structure[i] == 0)
	L.build(g, ds, L.Struct.DISTRICT)
	check(g.veg[ds] == L.Veg.BARE, "구역은 식생을 대체")
	for t in 50:
		L.advance_turn(g, used)
	check(g.structure_state[ds] == L.State.RUIN, "버려진 구역이 폐허가 됨")
	check(g.veg[ds] == L.Veg.GRASS, "폐허 아래로 초지가 자람 -> %s" % L.VEG_NAMES[g.veg[ds]])

	print("결과: %s" % ("모두 통과" if fails == 0 else "%d개 실패" % fails))
	quit(1 if fails > 0 else 0)
