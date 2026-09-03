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
		_expect(pt.z >= -0.3 and pt.z <= 2.4, "frame z in range: %s" % pt)
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

# --- D. Slot lanes stay inside the table (v3 regression: plates once hung
	# off a 1.2 m board because the X pitch was 0.42 m) ---
	var w_half: float = TableWorldScript.TABLE_WID * (0.5)
	_expect(TableWorldScript.slot_center_x(0) >= -w_half,
		"leftmost slot inside the table (x=%.3f)" % TableWorldScript.slot_center_x(0))
	_expect(TableWorldScript.slot_center_x(6) <= w_half,
		"rightmost slot inside the table (x=%.3f)" % TableWorldScript.slot_center_x(6))
	var span: float = TableWorldScript.slot_center_x(6) - TableWorldScript.slot_center_x(0)
	_expect(absf(span - 6.0 * TableWorldScript.SLOT_PITCH) < (0.001),
		"lane X spacing even (span=%.3f)" % span)
	var lane_half: float = TableWorldScript.SLOT_PITCH * (0.5)
	_expect(absf(TableWorldScript.slot_center_x(0)) >= lane_half,
		"edge lane fully on the felt (center minus half-width)")
	# Visual-only teeth must sit inside the playable width too.
	_expect(TableWorldScript.slot_center_x(6) + (0.06) <= w_half,
		"outer tooth hook stays on the table (x=%.3f)" % (TableWorldScript.slot_center_x(6) + (0.06)))
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
