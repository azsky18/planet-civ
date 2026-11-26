extends SceneTree
func _init() -> void:
	var hs := HexSphere.new()
	hs.build(6)
	var g := WorldGen.new()
	g.seed_value = 1
	g.generate(hs)
	var n := hs.count
	var d := PackedInt32Array(); d.resize(n); d.fill(-1)
	var q := PackedInt32Array()
	for i in n:
		if g.elevation[i] < 0.0:
			d[i] = 0; q.append(i)
	var h := 0
	while h < q.size():
		var i := q[h]; h += 1
		for k in range(hs.nb_offsets[i], hs.nb_offsets[i+1]):
			var j := hs.nb_list[k]
			if d[j] == -1:
				d[j] = d[i] + 1; q.append(j)
	var sums := {}
	for i in n:
		var key := mini(d[i], 10)
		if not sums.has(key): sums[key] = [0.0, 0, 0.0, 0.0]
		sums[key][0] += g.precip[i]; sums[key][1] += 1; sums[key][2] += g.wind[i].length(); sums[key][3] += g.temperature[i]
	for k in sums.keys():
		print("dist ", k, " n ", sums[k][1], " P ", int(sums[k][0]/sums[k][1]), " wind ", snappedf(sums[k][2]/sums[k][1], 0.01), " T ", snappedf(sums[k][3]/sums[k][1],0.1))
	quit()
