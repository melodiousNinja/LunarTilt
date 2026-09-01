extends SceneTree

const TableWorldScript := preload("res://scripts/game/table_world.gd")
const CameraRigScript := preload("res://scripts/game/camera_rig.gd")

## CameraRig maths probe: at which distance does the frame actually fit?
## Reproduces _reframe_camera exactly and prints per-point frustum margins,
## so a "dist=16 (fit never succeeds)" is either a math bug or a probe bug.

func _init() -> void:
	var pts: Array = TableWorldScript.frame_points()
	var aspect := 0.5625
	var fov_v := 62.0
	var pitch := CameraRigScript.pitch_for_aspect(aspect)
	var look := Vector3(0.0, 0.02, 0.98)
	print("pitch=", pitch, " fov=", fov_v, " aspect=", aspect)
	for dist in [3.0, 4.0, 6.0, 8.0, 16.0]:
		var cp := CameraRigScript.cam_pos(pitch, dist, look)
		var basis := CameraRigScript.cam_basis(look, cp)
		var ok := CameraRigScript.fits(pts, look, cp, basis, fov_v, aspect)
		print("dist=", dist, " cam_pos=", cp, " fits=", ok)
	var cp := CameraRigScript.cam_pos(pitch, 16.0, look)
	var basis := CameraRigScript.cam_basis(look, cp)
	var inv := basis.inverse()
	for pt in pts:
		var rel: Vector3 = inv * ((pt as Vector3) - cp)
		print("pt=", pt, " rel.z=", roundf(rel.z * 1000.0) / 1000.0, " rel.x=", roundf(rel.x * 1000.0) / 1000.0, " rel.y=", roundf(rel.y * 1000.0) / 1000.0)
	quit(0)