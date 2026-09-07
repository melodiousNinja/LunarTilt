extends SceneTree
## Video frame analyzer: classifies pixels in extracted video frames to
## measure the real Star Cluster Ball table layout and ball motion.
## Output per frame: marble extent, wood bands (fans), ball centroids.
func _initialize() -> void:
	var dir := DirAccess.open("res://artifacts/vframes")
	if dir == null:
		print("ANALYZER_NO_DIR")
		quit(1)
		return
	var files := []
	for f in dir.get_files():
		if f.ends_with(".jpg"):
			files.append(f)
	files.sort()
	print("FRAMES_TOTAL=", files.size())
	var out := []
	for fi in range(files.size()):
		var img := Image.load_from_file("res://artifacts/vframes/" + files[fi])
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var marble_rows := {}
		var wood_rows := {}
		var red_xs := 0.0
		var red_ys := 0.0
		var red_n := 0
		var dark_xs := 0.0
		var dark_ys := 0.0
		var dark_n := 0
		var marble_n := 0
		var wood_n := 0
		var min_my := h
		var max_my := 0
		for y in range(0, h, 4):
			for x in range(0, w, 4):
				var c := img.get_pixel(x, y)
				var r := c.r * 255.0
				var g := c.g * 255.0
				var b := c.b * 255.0
				if r > 135.0 and g > 125.0 and b > 110.0 and absf(r - g) < 55.0:
					marble_n += 1
					marble_rows[y] = int(marble_rows.get(y, 0)) + 1
					if y < min_my:
						min_my = y
					if y > max_my:
						max_my = y
					if r < 90.0 and g < 90.0 and b < 90.0:
						dark_xs += x
						dark_ys += y
						dark_n += 1
				elif r > 70.0 and r > g * 1.25 and r > b * 1.35 and g > b:
					wood_n += 1
					wood_rows[y] = int(wood_rows.get(y, 0)) + 1
				elif r > 90.0 and r > g * 1.7 and r > b * 1.7:
					red_xs += x
					red_ys += y
					red_n += 1
				elif r < 70.0 and g < 70.0 and b < 70.0 and y > int(h * 0.15) and y < int(h * 0.8):
					dark_xs += x
					dark_ys += y
					dark_n += 1
		var wood_bands := []
		if wood_n > 40:
			var keys := wood_rows.keys()
			keys.sort()
			var band_start := -1
			var prev := -10
			for k in keys:
				if int(wood_rows[k]) >= 6:
					if band_start < 0:
						band_start = k
					prev = k
				else:
					if band_start >= 0 and prev - band_start >= 4:
						wood_bands.append(str(band_start) + "-" + str(prev))
					band_start = -1
			if band_start >= 0 and prev - band_start >= 4:
				wood_bands.append(str(band_start) + "-" + str(prev))
		var line: String = str(files[fi]) + " marble_y=" + str(min_my) + ".." + str(max_my) \
			+ " wood_bands=" + str(wood_bands)
		if red_n >= 3:
			line += " red=(" + str(int(red_xs / red_n)) + "," + str(int(red_ys / red_n)) + ")x" + str(red_n)
		if dark_n >= 6:
			line += " dark=(" + str(int(dark_xs / dark_n)) + "," + str(int(dark_ys / dark_n)) + ")x" + str(dark_n)
		out.append(line)
	var f := FileAccess.open("res://artifacts/video_analysis.txt", FileAccess.WRITE)
	for l in out:
		f.store_line(l)
	f.close()
	print("ANALYZER_DONE lines=", out.size())
	quit(0)