extends SceneTree
## 타일 그림 아틀라스를 PNG로 저장해 그림이 제대로 읽히는지 확인한다.
## godot --headless -s tools/art_sheet.gd -- 저장폴더
## 납작한 그림(decals.png), 세운 그림(sprites.png), 바닥 무늬(ground_N.png)를 저장한다.

func _init() -> void:
	var art := TileArt.new()
	art.load_all()
	var out: String = "user://"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0].trim_suffix("/") + "/"
	art.decals.texture.get_image().save_png(out + "decals.png")
	art.sprites.texture.get_image().save_png(out + "sprites.png")
	for k in art.ground_keys.size():
		TileArt.Atlas.load_image(TileArt.GROUND[art.ground_keys[k]], 256).save_png(out + "ground_%s.png" % art.ground_keys[k])
	print("납작한 그림 %d장, 세운 그림 %d장, 바닥 %d장 -> %s" % [art.decals.keys.size(), art.sprites.keys.size(), art.ground_keys.size(), out])
	quit()
