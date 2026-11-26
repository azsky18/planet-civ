extends SceneTree
func _init() -> void:
	var hs := HexSphere.new()
	hs.build(6)
	for sd in [1, 2, 3]:
		var g := WorldGen.new()
		g.seed_value = sd
		g.generate(hs)
		var c: PackedInt32Array = g.stats["counts"]
		var land: int = g.stats["land"]
		var out := "seed %d land %d rivers %d lakes %d marsh %d | " % [sd, land, g.stats["rivers"], g.stats["lakes"], g.stats["marsh"]]
		for b in c.size():
			if b >= 4 and c[b] > 0:
				out += "%s %d%%, " % [WorldGen.BIOME_NAMES[b], int(100.0 * c[b] / land)]
		var lp := 0.0
		for i in hs.count:
			if g.elevation[i] >= 0.0: lp += g.precip[i]
		out += " landP %d" % int(lp / land)
		var arr := PackedFloat32Array()
		for i in hs.count:
			if g.elevation[i] >= 0.0: arr.append(g.precip[i])
		arr.sort()
		out += " p10 %d p50 %d p90 %d" % [arr[arr.size()/10], arr[arr.size()/2], arr[arr.size()*9/10]]
		print(out)
	quit()
