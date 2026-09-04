extends SceneTree
## v2 presentation regression tests: aspect-aware camera framing, play-area
## frame box, and rack spacing. Pure math (no physics) so it runs headless.
## Run:  godot --headless --path . --script res://tests/test_v2_layout.gd

const TableWorldScript := preload("res://scripts/game/table_world.gd")
const CameraRigScript := preload("res://scripts/game/camera_rig.gd")

var _failures := 0
var _total := 0


func _initialize() -> void:
	_run()


func _run() -> void:
	# --- A. CameraRig frames the whole play area at every target aspect ---
	var look := Vector3(0.0, 0.02, 0.98)
	for aspect in [0.4615, 0.5625, 1.333, 1.778]:   # 9:19.5, 9:16, 4:3, 16:9
		var pitch := CameraRigScript.pitch_for_aspect(aspect)
		var dist := CameraRigScript.fit_distance(
			TableWorldScript.frame_points(), 62.0, aspect, pitch, look)
		_expect(dist > 0.6 and dist < 10.0, "aspect %.4f framing distance sane (%.2f)" % [aspect, dist])
		var cp := CameraRigScript.cam_pos(pitch, dist, look)
		var basis := CameraRigScript.cam_basis(look, cp)
		_expect(CameraRigScript.fits(TableWorldScript.frame_points(), look, cp, basis, 62.0, aspect),
			"aspect %.4f all frame corners fit inside frustum" % aspect)
		# The look target must sit well in front of the camera (in camera -Z).
		var rel: Vector3 = basis.inverse() * (look - cp)
		_expect(rel.z < -0.5, "aspect %.4f look target in front of camera (depth %.2f)" % [aspect, -rel.z])

	# Pitches: portrait steeper than landscape.
	_expect(CameraRigScript.pitch_for_aspect(0.46) > CameraRigScript.pitch_for_aspect(1.78),
		"portrait pitch steeper than landscape pitch")

	# --- B. Frame box limits (table + rails + racks, no wasted void) ---
	var pts: Array = TableWorldScript.frame_points()
	for pt: Vector3 in pts:
		_expect(pt.x >= -1.0 and pt.x <= 1.0, "frame x in range: %s" % pt)
		_expect(pt.z >= -0.3 and pt.z <= 3.05, "frame z in range: %s" % pt)
		_expect(pt.y >= -0.1 and pt.y <= 0.25, "frame y in range: %s" % pt)

	# --- C. Hand-ball racks: spaced, on correct sides, 12 per color ---
	var red0: Vector3 = TableWorldScript.rack_spot("red", 0)
	var red11: Vector3 = TableWorldScript.rack_spot("red", 11)
	_expect(red0.x < 0.0, "red rack sits on player's left (x=%.2f)" % red0.x)
	_expect(red11.x < 0.0, "red rack consistent (x=%.2f)" % red11.x)
	_expect(TableWorldScript.rack_spot("black", 0).x > 0.0, "black rack sits on player's right")
	var gap: float = (red11 - red0).length()
	_expect(absf(gap - 11.0 * TableWorldScript.RACK_PITCH) < 0.001,
		"rack balls spaced evenly (span %.3f = 11 x pitch)" % gap)
	for idx in 11:
		var a: Vector3 = TableWorldScript.rack_spot("red", idx)
		var b: Vector3 = TableWorldScript.rack_spot("red", idx + 1)
		_expect(absf((b - a).length() - TableWorldScript.RACK_PITCH) < 0.0001,
			"consecutive rack spacing at index %d" % idx)

# --- D. Medallion geometry stays inside the table (v3: plates once hung off
	# the board; v5: three astrolabe medallions down the centreline) ---
	var w_half: float = TableWorldScript.TABLE_WID * (0.5)
	var all_sockets_inside := true
	var max_reach := 0.0
	for bi in range(3):
		for si in range(7):
			var sp: Vector3 = TableWorldScript.socket_pos(bi, si)
			all_sockets_inside = all_sockets_inside and absf(sp.x) <= w_half
			max_reach = maxf(max_reach, absf(sp.x))
	_expect(all_sockets_inside,
		"all 21 sockets inside the table width (max |x|=%.3f)" % max_reach)
	_expect(max_reach + TableWorldScript.SOCKET_R <= w_half,
		"outermost socket cup fully on the marble (reach=%.3f)" % max_reach)
	# Medallions spaced down the length: inside the board, never overlapping.
	var z_ok := true
	for bi in range(3):
		var cz: float = TableWorldScript.POS_Z[bi]
		z_ok = z_ok and cz > 0.3 and cz < TableWorldScript.TABLE_LEN - 0.3
		if bi > 0:
			z_ok = z_ok and (TableWorldScript.POS_Z[bi] - TableWorldScript.POS_Z[bi - 1]) > 2.0 * TableWorldScript.MEDAL_R
	_expect(z_ok, "medallion centres spaced and inside the board length")
	# The socket cluster must fit within its medallion ring.
	_expect(TableWorldScript.CLUSTER_R + TableWorldScript.SOCKET_R <= TableWorldScript.MEDAL_R,
		"hex-flower cluster fits inside the brass ring")
	print("V2_LAYOUT_TEST total=%d failures=%d" % [_total, _failures])
	if _failures == 0:
		print("ALL TESTS PASSED")
		quit(0)
	else:
		printerr("V2_LAYOUT_TEST FAILURES: %d" % _failures)
		quit(1)


func _expect(cond: bool, name: String) -> void:
	_total += 1
	if cond:
		print("  ok: " + name)
	else:
		_failures += 1
		printerr("FAIL: " + name)
		print("FAIL: " + name)
