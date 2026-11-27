extends SceneTree
## 채집·인구 순환 규칙 점검: godot --headless -s tools/game_check.gd
## 시작 배치, 야영지, 채집, 성장, 내보내기, 전투 확률, 턴 진행을 돌려 보고 기대와 다르면 FAIL 을 찍는다.

const GameRules := preload("res://scripts/game_rules.gd")

var fails: int = 0


func check(ok: bool, what: String) -> void:
	if not ok:
		fails += 1
	print(("ok   " if ok else "FAIL ") + what)


func _init() -> void:
	var hs := HexSphere.new()
	hs.build(6)
	var g := WorldGen.new()
	g.seed_value = 3
	g.generate(hs)
	var t0: int = Time.get_ticks_msec()
	var gr := GameRules.new()
	gr.setup(g, 3)
	print("setup %d ms" % (Time.get_ticks_msec() - t0))
	var counts := {}
	for r in GameRules.Res.size():
		counts[GameRules.RES_NAMES[r]] = 0
	for i in g.n:
		counts[GameRules.RES_NAMES[gr.res_kind[i]]] += 1
	print("자원: ", counts)
	var kinds := {}
	for u in gr.units:
		kinds[u.kind] = kinds.get(u.kind, 0) + 1
	print("유닛: ", kinds, " 목표 동물 수 ", gr.animal_target)
	check(gr.player_units().size() == 2, "시작 부족민 2명")
	check(gr.population() == 2, "시작 인구 2")
	check(gr.is_land(gr.start_tile), "시작 칸이 땅")
	for k in ["deer", "bison", "boar", "wolf", "bear", "tiger"]:
		check(kinds.get(k, 0) > 0, "동물 배치: " + k)
	for r in range(1, GameRules.Res.size()):
		check(counts[GameRules.RES_NAMES[r]] > 0, "식량 자원 배치: " + GameRules.RES_NAMES[r])

	# 전투 확률
	check(absf(GameRules.win_chance(0.5, 3, 3) - 0.5) < 1e-6, "같은 힘, 같은 체력이면 50%")
	check(GameRules.win_chance(0.25, 3, 3) < 0.2, "방어가 셋 배면 승률 낮음")

	# 야영지
	var a: GameRules.Unit = gr.player_units()[0]
	var b: GameRules.Unit = gr.player_units()[1]
	var camp: GameRules.Camp = gr.found_camp(a)
	check(camp != null and camp.pop == 1, "야영지 설치, 인구 1")
	check(gr.population() == 2, "설치해도 총 인구 그대로 (유닛 1 = 인구 1)")
	check(gr.camp_block_reason(b) != "", "같은 칸에 또 설치 불가")

	# 채집: 가까운 식량 칸으로 가서 모아 오기
	var res_tile: int = -1
	var near: Dictionary = gr.within(camp.tile, 2)
	for j in near:
		if gr.is_land(j) and gr.res_kind[j] != GameRules.Res.NONE and j != camp.tile:
			res_tile = j
			break
	check(res_tile >= 0, "야영지 둘레 2칸 안에 땅 위 식량 자원")
	var gathered: int = 0
	var turns: int = 0
	var grew := false
	while turns < 40:
		turns += 1
		if b.tile != res_tile and b.carry < 6:
			gr.order_move(b, res_tile)
		elif b.tile == res_tile and b.carry < 6:
			gathered += gr.gather(b)
		else:
			gr.order_move(b, camp.tile)
		gr.end_turn()
		if not gr.units.has(b):
			print("부족민이 쓰러짐 (턴 %d)" % turns)
			break
		if camp.pop >= 2:
			grew = true
			break
	print("채집 %d, %d턴, 야영지 인구 %d 식량 %d/%d, 턴당 %+d" % [gathered, turns, camp.pop, camp.food, GameRules.growth_need(camp.pop), gr.camp_net(camp)])
	check(gathered > 0, "채집해서 식량을 얻음")
	check(grew, "야영지 인구가 2로 늘어남")
	if grew:
		var u2: GameRules.Unit = gr.release_unit(camp)
		check(u2 != null and camp.pop == 1, "인구 2에서 부족민 내보내기")
		check(gr.join_camp(u2) and camp.pop == 2, "부족민이 다시 합류")

	# 사냥: 체력을 붙여 둔 부족민으로 사슴 공격
	var hunter: GameRules.Unit = gr.spawn("tribe", camp.tile)
	var deer: GameRules.Unit = null
	for j in gr.neighbors(camp.tile):
		if gr.unit_at(j) == null and gr.is_land(j):
			deer = gr.spawn("deer", j)
			break
	if deer != null:
		var odds: float = gr.attack_odds(hunter, deer)
		print("사슴 사냥 승률 %.0f%%" % (odds * 100))
		var msg: String = gr.order_move(hunter, deer.tile)
		print(msg)
		check(msg != "", "곁의 동물을 누르면 공격")
		check(not gr.units.has(deer) or not gr.units.has(hunter), "전투 뒤 한쪽이 쓰러짐")

	# 인구 1 야영지에서 내보내면 야영지가 사라진다
	var lone := gr.spawn("tribe", camp.tile)
	var far: int = -1
	for j in gr.within(camp.tile, 6):
		if gr.is_land(j) and gr.unit_at(j) == null and gr.within(j, 2).keys().all(func(t): return gr.camp_at(t) == null):
			far = j
			break
	if far >= 0:
		gr._move_to(lone, far)
		lone.carry = 4
		var c2 = gr.found_camp(lone)
		var before: int = gr.population()
		var out = gr.release_unit(c2)
		check(out != null and gr.camp_at(far) == null and not gr.camps.has(c2), "인구 1 야영지에서 내보내면 야영지가 사라짐")
		check(gr.population() == before, "야영지가 사라져도 총 인구 그대로")
		check(out.carry == 4, "창고 식량을 들고 나옴")

	# 턴 여러 번 돌려도 오류 없이 동물 수 유지
	for _t in 30:
		gr.end_turn()
	print("30턴 뒤 동물 %d / 목표 %d, 턴 %d" % [gr.count_animals(), gr.animal_target, gr.turn])
	check(gr.count_animals() > gr.animal_target * 0.7, "동물이 다시 생겨 수를 유지")
	for line in gr.events.slice(-8):
		print("  ", line)
	print("FAILS: %d" % fails)
	quit(1 if fails > 0 else 0)
