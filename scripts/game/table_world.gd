class_name TableWorld
extends Node3D

## Procedurally builds the physical Star Cluster Ball table (Lunar Tilt).
## Real-world specs from docs/PHYSICS_SPEC.md (YoTyan reference table):
##   2.2 m x 1.2 m board, 4.99-degree tilt, three 7-slot Astrolabe positions,
##   gutter strip beyond the far position.

signal ball_captured(ball: SCBBall, slot_index: int)
signal ball_guttered(ball: SCBBall)

const TABLE_LEN := 2.2      # Z axis (player end at Z=0, far end at Z=2.2)
const TABLE_WID := 1.2      # X axis
const TILT_DEG := 4.99
const BOARD_THICK := 0.06
const RAIL_H := 0.08
const RAIL_T := 0.04

const SLOTS_PER_POS := 7
const POS_Z := [0.62, 1.10, 1.58]     # slot-strip centers (closest..furthest)
const SLOT_W := 0.13                  # slot pocket width (X)
const SLOT_D := 0.24                  # slot pocket depth (Z)

const BALLS_PER_COLOR := 12
const LAUNCH_Z := 0.20

## A ball moving faster than this is NOT captured by a scoring slot (it rolls
## over the pocket band and keeps traveling up-table). Tuned so that a
## 1.2 m/s shot settles in the Pos2 band while a 2.0 m/s shot crosses Pos1/2
## into the deep zone / gutter.
const SLOT_CAPTURE_SPEED := 0.5

var board: StaticBody3D
var slots: Array = []        # [{ pos:int, area:Area3D, color:String }]
var gutter: Area3D
var hand_balls: Dictionary = {"red": [], "black": []}   # frozen tray balls


## World-space height of the board's top surface at (x, z).
## Exact geometry: the box center sits at y=-BOARD_THICK/2, z=TABLE_LEN/2,
## rotated -TILT_DEG around X. Rotating the top face (+h local) moves its
## anchor to yP = h*(cos(t)-1) and zP = L/2 - h*sin(t); the plane normal is
## (0, cos(t), -sin(t)). Verified against a physics raycast in-engine.
func surface_y_at(_x: float, z: float) -> float:
	var h: float = BOARD_THICK * 0.5
	var th: float = deg_to_rad(TILT_DEG)
	var cos_t := cos(th)
	var sin_t := sin(th)
	var yp: float = h * (cos_t - 1.0)
	var zp: float = TABLE_LEN * 0.5 - h * sin_t
	return yp + tan(th) * (z - zp)


func ball_rest_y(x: float, z: float) -> float:
	return surface_y_at(x, z) + 0.021   # radius + small rest clearance


func _ready() -> void:
	build()


func build() -> void:
	# --- Board (4.99 deg tilt: +Z end raised) ---
	board = StaticBody3D.new()
	var bs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TABLE_WID, BOARD_THICK, TABLE_LEN)
	bs.shape = box
	board.add_child(bs)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = Color(0.55, 0.36, 0.20)      # red oak
	board_mat.roughness = 0.72
	board_mat.metallic = 0.0
	var board_mesh := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(TABLE_WID, BOARD_THICK, TABLE_LEN)
	board_mesh.mesh = bm
	board_mesh.material_override = board_mat
	board.position = Vector3(0.0, -BOARD_THICK * 0.5, TABLE_LEN * 0.5)
	board_mesh.position = board.position
	board.rotation.x = -deg_to_rad(TILT_DEG)
	board_mesh.rotation.x = board.rotation.x
	board.collision_layer = 1
	board.collision_mask = 2
	add_child(board)
	add_child(board_mesh)

	# --- Rails (tall vertical backstops covering the full slope range) ---
	# The board surface varies from y=-0.126 (player end) to y=+0.066 (far end);
	# rails must stand from below the lowest ball center to above the highest.
	var RAIL_H_TOTAL := 0.30
	var rails := [
		{"size": Vector3(RAIL_T, RAIL_H_TOTAL, TABLE_LEN), "pos": Vector3(-TABLE_WID / 2.0 - RAIL_T / 2.0, -0.03, TABLE_LEN / 2.0)},
		{"size": Vector3(RAIL_T, RAIL_H_TOTAL, TABLE_LEN), "pos": Vector3(TABLE_WID / 2.0 + RAIL_T / 2.0, -0.03, TABLE_LEN / 2.0)},
		{"size": Vector3(TABLE_WID + RAIL_T * 2.0, RAIL_H_TOTAL, RAIL_T), "pos": Vector3(0.0, -0.03, TABLE_LEN + RAIL_T / 2.0)},
	]
	for r in rails:
		var st := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var rb := BoxShape3D.new()
		rb.size = r.size
		cs.shape = rb
		st.add_child(cs)
		st.position = r.pos
		st.collision_layer = 1
		st.collision_mask = 2
		add_child(st)

	# --- Front return tray ---
	# Balls that roll back down (the sport's "Returned Ball" rule) come off the
	# leading edge of the board into a shallow tray instead of falling forever.
	var tray_floor := StaticBody3D.new()
	var tf_cs := CollisionShape3D.new()
	var tf_b := BoxShape3D.new()
	tf_b.size = Vector3(TABLE_WID - 0.05, 0.02, 0.26)
	tf_cs.shape = tf_b
	tray_floor.add_child(tf_cs)
	tray_floor.position = Vector3(0.0, -0.140, -0.07)
	tray_floor.collision_layer = 1
	tray_floor.collision_mask = 2
	add_child(tray_floor)
	var tray_lip := StaticBody3D.new()
	var tl_cs := CollisionShape3D.new()
	var tl_b := BoxShape3D.new()
	tl_b.size = Vector3(TABLE_WID - 0.05, 0.12, 0.04)
	tl_cs.shape = tl_b
	tray_lip.add_child(tl_cs)
	tray_lip.position = Vector3(0.0, -0.085, -0.20)
	tray_lip.collision_layer = 1
	tray_lip.collision_mask = 2
	add_child(tray_lip)

	# --- Play line (visual only) ---
	var line := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(TABLE_WID - 0.1, 0.004, 0.008)
	line.mesh = lm
	var line_mat := StandardMaterial3D.new()
	line_mat.albedo_color = Color(0.85, 0.75, 0.5)
	line_mat.emission_enabled = true
	line_mat.emission = Color(0.6, 0.5, 0.3)
	line_mat.emission_energy_multiplier = 1.2
	line.material_override = line_mat
	line.position = Vector3(0.0, 0.004, 0.35)
	line.rotation.x = board.rotation.x
	add_child(line)

	# --- 21 scoring slots (3 positions x 7 across the width) ---
	for pi in range(POS_Z.size()):
		for si in range(SLOTS_PER_POS):
			var x := lerpf(-0.45, 0.45, float(si) / maxf(SLOTS_PER_POS - 1, 1))
			var s := Area3D.new()
			var cs := CollisionShape3D.new()
			var sb := BoxShape3D.new()
			sb.size = Vector3(SLOT_W, 0.05, SLOT_D)
			cs.shape = sb
			s.add_child(cs)
			s.position = Vector3(x, surface_y_at(x, POS_Z[pi]) + 0.010, POS_Z[pi])
			s.rotation.x = board.rotation.x
			s.collision_layer = 0
			s.collision_mask = 2
			s.monitoring = true
			var idx := slots.size()
			s.name = "Slot_p%d_%d" % [pi, si]
			s.body_entered.connect(_on_slot_entered.bind(idx))
			add_child(s)
			slots.append({"pos": pi, "area": s, "color": ""})

	# --- Gutter strip past the far position ---
	gutter = Area3D.new()
	var gcs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	gb.size = Vector3(TABLE_WID, 0.05, 0.35)
	gcs.shape = gb
	gutter.add_child(gcs)
	gutter.position = Vector3(0.0, surface_y_at(0.0, TABLE_LEN - 0.18) + 0.010, TABLE_LEN - 0.18)
	gutter.rotation.x = board.rotation.x
	gutter.collision_layer = 0
	gutter.collision_mask = 2
	gutter.monitoring = true
	gutter.body_entered.connect(_on_gutter_entered)
	add_child(gutter)


## Spawns a frozen ball into a side tray (in-hand). Color: "red"/"black".
func spawn_hand_ball(color: String) -> SCBBall:
	var b := SCBBall.create(color)
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	var n: int = int((hand_balls[color] as Array).size())
	var pos := Vector3(-0.46 if color == "red" else 0.46,
		ball_rest_y(0.0, 0.12) + n * 0.003, 0.12)
	b.position = pos
	add_child(b)
	hand_balls[color].append(b)
	return b


## Unfreezes and returns an in-hand ball placed at the launch point.
func take_hand_ball(color: String) -> SCBBall:
	if hand_balls[color].is_empty():
		return null
	var b: SCBBall = hand_balls[color].pop_back()
	b.freeze = false
	b.collision_layer = 2
	b.collision_mask = 3
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	b.position = Vector3(0.0, ball_rest_y(0.0, LAUNCH_Z), LAUNCH_Z)
	b.rotation = Vector3.ZERO
	return b


func _on_slot_entered(body: Node3D, slot_index: int) -> void:
	var b := body as SCBBall
	if b == null or b.freeze:
		return
	# A slot only captures a ball that SETTLES into it (speed below threshold);
	# fast balls roll over the band and continue up the table, matching the
	# real table where pockets catch near-rest balls.
	if b.linear_velocity.length() > SLOT_CAPTURE_SPEED:
		return
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	slots[slot_index]["color"] = b.color
	ball_captured.emit(b, slot_index)


func _on_gutter_entered(body: Node3D) -> void:
	var b := body as SCBBall
	if b == null or b.freeze:
		return
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	ball_guttered.emit(b)


## Convenience: hit-test which slot a ball crossed (for tests/telemetry).
func slot_at(index: int) -> Dictionary:
	return slots[index]