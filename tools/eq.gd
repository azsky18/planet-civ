extends SceneTree
func _init() -> void:
	var hs := HexSphere.new()
	hs.build(6)
	var g := WorldGen.new()
	g.seed_value = 1
	g.generate(hs)
	var W := 720
	var H := 360
	for which in ["precip", "biome", "wind"]:
		var img := Image.create(W, H, false, Image.FORMAT_RGB8)
		var last := 0
		for y in H:
			for x in W:
				var lat := (0.5 - (y + 0.5) / H) * PI
				var lon := ((x + 0.5) / W - 0.5) * TAU
				var p := Vector3(cos(lat) * sin(lon), sin(lat), cos(lat) * cos(lon))
				var t := hs.find_tile(p, last)
				last = t
				var c: Color
				if which == "precip":
					c = PlanetView.precip_color(g.precip[t])
					if g.elevation[t] < 0.0: c = c.darkened(0.6)
				elif which == "biome":
					c = WorldGen.BIOME_COLORS[g.biome[t]]
				else:
					c = Color(0.5 + g.pressure[t]*0.3, 0.5, 0.5 - g.pressure[t]*0.3)
				img.set_pixel(x, y, c)
		img.save_png("/tmp/eq_%s.png" % which)
	quit()
