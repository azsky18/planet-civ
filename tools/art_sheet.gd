extends SceneTree
## 타일 그림 아틀라스를 PNG로 저장해 그림이 제대로 읽히는지 확인한다.
## godot --headless -s tools/art_sheet.gd -- 저장경로.png

func _init() -> void:
	var art := TileArt.new()
	art.load_all()
	var out: String = "user://tile_art_atlas.png"
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		out = args[0]
	art.atlas.get_image().save_png(out)
	print("그림 %d장: %s -> %s" % [art.keys.size(), ", ".join(art.keys), out])
	quit()
