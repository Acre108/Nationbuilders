extends RefCounted
## 16^3 RGB cube packed as 16 blue slices into a 256 x 16 lookup image.
static func create() -> ImageTexture:
	var rows: Array = JSON.parse_string(FileAccess.get_file_as_string("res://render/palettes/hearth32.json"))
	var palette: Array[Color] = []
	for hex in rows:
		palette.append(Color.html(hex))
	var image := Image.create(256,16,false,Image.FORMAT_RGB8)
	for b in 16:
		for g in 16:
			for r in 16:
				var sample := Vector3(r,g,b) / 15.0
				var best := palette[0]
				var distance := INF
				for color in palette:
					var delta := sample - Vector3(color.r,color.g,color.b)
					var candidate := delta.x * delta.x * 0.3 + delta.y * delta.y * 0.59 + delta.z * delta.z * 0.11
					if candidate < distance:
						distance = candidate
						best = color
				image.set_pixel(r + b * 16,g,best)
	return ImageTexture.create_from_image(image)
