extends SceneTree
## Measure the REFERENCE frames (Claude's extracts in docs/reference):
## ball cluster sizes vs hook spacing, so FAN_MOUTH can be set so exactly
## one ball fills a hook (owner rule).
func _initialize() -> void:
	for fname in ["full_168.jpg", "full_264.jpg", "full_402.jpg"]:
		var img := Image.load_from_file("res://docs/reference/" + fname)
		if img == null:
			print("MISSING ", fname)
			continue
		var w := img.get_width()
		var h := img.get_height()
		var red_pts := []
		var dark_pts := []
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				var r := c.r * 255.0
				var g := c.g * 255.0
				var b := c.b * 255.0
				if r > 100.0 and r > g * 1.7 and r > b * 1.7:
					red_pts.append(Vector2(x, y))
				elif r < 75.0 and g < 75.0 and b < 75.0 and y > int(h * 0.12) and y < int(h * 0.85):
					dark_pts.append(Vector2(x, y))
		print("== ", fname, " ", w, "x", h, " red_pts=", red_pts.size(), " dark_pts=", dark_pts.size())
		for c in _cluster(red_pts, 12.0):
			print("  RED at (", int(c.x), ",", int(c.y), ") n=", int(c.z))
		for c in _cluster(dark_pts, 12.0):
			if c.z >= 8.0:
				print("  DARK at (", int(c.x), ",", int(c.y), ") n=", int(c.z))
	quit(0)

func _cluster(pts: Array, tol: float) -> Array:
	var clusters: Array = []
	for p in pts:
		var placed := false
		for ci in range(clusters.size()):
			var d := Vector2(clusters[ci].x, clusters[ci].y).distance_to(p)
			if d < tol * 3.0:
				var n: float = clusters[ci].z
				clusters[ci].x = (clusters[ci].x * n + p.x) / (n + 1.0)
				clusters[ci].y = (clusters[ci].y * n + p.y) / (n + 1.0)
				clusters[ci].z = n + 1.0
				placed = true
				break
		if not placed:
			clusters.append(Vector3(p.x, p.y, 1.0))
	var out: Array = []
	for c in clusters:
		if c.z >= 4.0:
			out.append(c)
	out.sort_custom(func(a, b): return a.y < b.y)
	return out