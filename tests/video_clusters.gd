extends SceneTree
## Clusters red-ball and wood pixels in selected video frames to measure
## exactly where caught balls sit and how wide the fans are.
func _initialize() -> void:
	for fname in ["f030.jpg", "f060.jpg", "f090.jpg", "f130.jpg"]:
		var img := Image.load_from_file("res://artifacts/vframes/" + fname)
		if img == null:
			continue
		var w := img.get_width()
		var h := img.get_height()
		var red_pts := []
		var wood_pts := []
		for y in range(0, h, 2):
			for x in range(0, w, 2):
				var c := img.get_pixel(x, y)
				var r := c.r * 255.0
				var g := c.g * 255.0
				var b := c.b * 255.0
				if r > 100.0 and r > g * 1.7 and r > b * 1.7:
					red_pts.append(Vector2(x, y))
				elif r > 80.0 and r > g * 1.3 and r > b * 1.4 and g > b and g > 45.0:
					wood_pts.append(Vector2(x, y))
		var red_clusters := _cluster(red_pts, 14.0)
		var wood_clusters := _cluster(wood_pts, 16.0)
		print("== ", fname, " == red_pts=", red_pts.size(), " wood_pts=", wood_pts.size())
		for c in red_clusters:
			print("  RED ball at (", int(c.x), ",", int(c.y), ") n=", c.z)
		for c in wood_clusters:
			print("  WOOD blob centre (", int(c.x), ",", int(c.y), ") n=", c.z)
	quit(0)

## Greedy grid clustering: returns array of Vector3(cx, cy, count).
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
		if c.z >= 3.0:
			out.append(c)
	out.sort_custom(func(a, b): return a.y < b.y)
	return out