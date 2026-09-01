class_name TableWorld
extends Node3D

## Procedurally builds the physical Star Cluster Ball table (Lunar Tilt).
## Real-world specs from docs/PHYSICS_SPEC.md (YoTyan reference table):
##   2.2 m x 1.2 m board, 4.99-degree tilt, three 7-slot Astrolabe positions,
##   gutter strip beyond the far position.

signal ball_captured(ball: SCBBall, slot_index: int)
signal ball_guttered(ball: SCBBall)
## A live ball rolled back off the player end into the return tray (real-sport
## rule: the shooter keeps it and flicks again). TableWorld freezes it; main
## calls reinsert_hand_ball() to put it back in the rack.
signal ball_returned(ball: SCBBall)

const TABLE_LEN := 2.2      # Z axis (player end at Z=0, far end at Z=2.2)
const TABLE_WID := 1.2      # X axis
const TILT_DEG := 4.99
const BOARD_THICK := 0.06
const RAIL_H := 0.08
const RAIL_T := 0.04
## Full visible height of the rail backstops (physics body height).
const RAIL_H_TOTAL := 0.30
## World Y of the top face of the side rails (the hand-ball racks rest on these).
const RAIL_TOP_Y := -0.03 + RAIL_H_TOTAL * 0.5

const SLOTS_PER_POS := 7
const POS_Z := [0.62, 1.10, 1.58]     # slot-strip centers (closest..furthest)
const SLOT_W := 0.13                  # slot pocket width (X)
const SLOT_D := 0.24                  # slot pocket depth (Z)

const BALLS_PER_COLOR := 12
const LAUNCH_Z := 0.20

# --- Hand-ball racks (visual side channels, player end) ---
# Each color lives in a wooden channel attached to the board's side rail.
# Balls rest spaced RACK_PITCH apart along Z so the hand count is always
# readable at a glance (v1 stacked 12 balls in one spot - the ugly clump).
const RACK_X_CENTER := 0.68        # channel center X per side (on the rail tops)
const RACK_W := 0.26               # channel width
const RACK_D := 0.55               # channel depth (Z)
const RACK_Z_START := 0.04
const RACK_PITCH := 0.042          # ball spacing (40mm ball + 2mm gap)

## A ball moving faster than this is NOT captured by a scoring slot (it rolls
## over the pocket band and keeps traveling up-table). Tuned so that a
## 1.2 m/s shot settles in the Pos2 band while a 2.0 m/s shot crosses Pos1/2
## into the deep zone / gutter.
const SLOT_CAPTURE_SPEED := 0.5

var board: StaticBody3D
var slots: Array = []        # [{ pos:int, area:Area3D, color:String }]
var gutter: Area3D
var _tray_zone: Area3D
var hand_balls: Dictionary = {"red": [], "black": []}   # frozen tray balls


## World-space height of the board's top surface at (x, z).
## Exact geometry: the box center sits at y=-BOARD_THICK/2, z=TABLE_LEN/2,
## rotated -TILT_DEG around X. Rotating the top face (+h local) moves its
## anchor to yP = h*(cos(t)-1) and zP = L/2 - h*sin(t); the plane normal is
## (0, cos(t), -sin(t)). Verified against a physics raycast in-engine.
static func surface_y_static(_x: float, z: float) -> float:
	var h: float = BOARD_THICK * 0.5
	var th: float = deg_to_rad(TILT_DEG)
	var cos_t := cos(th)
	var sin_t := sin(th)
	var yp: float = h * (cos_t - 1.0)
	var zp: float = TABLE_LEN * 0.5 - h * sin_t
	return yp + tan(th) * (z - zp)


func surface_y_at(x: float, z: float) -> float:
	return surface_y_static(x, z)


func ball_rest_y(x: float, z: float) -> float:
	return surface_y_static(x, z) + 0.021   # radius + small rest clearance


# ------------------------------------------------------------- pure layout --

## Rack channel X center per color (red on the player's left, black right).
static func rack_x(color: String) -> float:
	return -RACK_X_CENTER if color == "red" else RACK_X_CENTER


## Shelf floor height under the rack channel at a given X (rests on the rail tops).
static func _rack_floor_y(_x: float) -> float:
	return RAIL_TOP_Y + 0.008


## World position of rack ball #index for a color. Pure math so unit tests can
## verify spacing without constructing a physics scene.
static func rack_spot(color: String, index: int) -> Vector3:
	var x := rack_x(color)
	var z := RACK_Z_START + index * RACK_PITCH
	return Vector3(x, _rack_floor_y(x) + 0.021, z)


## 8 corners of the visual frame we care about (racks + tray + table + gutter),
## with a tight Y span so the camera doesn't waste portrait screen on floor/void.
## CameraRig fits these inside the FOV, so every device shows the whole play area.
static func frame_points() -> Array:
	var pts: Array = []
	# x: table (1.2) + rails/racks (~0.18 each side); z: tray lip .. far gutter;
	# y: just under the felt .. just above the rack balls (RAIL_TOP ~0.12).
	for x in [-0.78, 0.78]:
		for z in [-0.22, 2.26]:
			for y in [-0.05, 0.17]:
				pts.append(Vector3(x, y, z))
	return pts


# ------------------------------------------------------------ visual helpers --

## Walnut frame material: procedural Simplex noise baked once as a wood-grain
## albedo (no asset files needed, stays small for mobile).
func _wood_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.46, 0.29, 0.17)
	mat.roughness = 0.62
	mat.metallic = 0.0
	var grain := NoiseTexture2D.new()
	var ns := FastNoiseLite.new()
	ns.noise_type = FastNoiseLite.TYPE_SIMPLEX
	ns.frequency = 2.6
	ns.seed = 1337
	grain.noise = ns
	grain.width = 256
	grain.height = 256
	mat.albedo_texture = grain
	return mat


## Tournament felt material with a subtle pile normal (visual only).
func _felt_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.09, 0.27, 0.13)
	mat.roughness = 0.95
	var pile_n := NoiseTexture2D.new()
	var pile := FastNoiseLite.new()
	pile.noise_type = FastNoiseLite.TYPE_SIMPLEX
	pile.frequency = 21.0
	pile.seed = 7
	pile_n.noise = pile
	pile_n.width = 128
	pile_n.height = 128
	mat.normal_enabled = true
	mat.normal_texture = pile_n
	mat.normal_scale = 0.05
	return mat


## Short turned pedestal leg under the table so it reads as furniture on the
## broadcast stage instead of a floating slab. Visual only (no collision).
func _leg(vx: float, vz: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.035
	cm.bottom_radius = 0.05
	cm.height = 0.155
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.30, 0.20, 0.12)
	mat.roughness = 0.55
	mi.mesh = cm
	mi.material_override = mat
	var top_y := surface_y_at(vx, vz) - 0.055   # tucked under the board bottom
	mi.position = Vector3(vx, top_y - 0.0775, vz)
	return mi


## Visible rail cap laid on top of each side rail (visual shelf for the racks).
func _rail_cap(side: float) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.07, 0.008, TABLE_LEN)
	mi.mesh = bm
	mi.material_override = _wood_material()
	mi.position = Vector3(side * (TABLE_WID / 2.0 + RAIL_T / 2.0), RAIL_TOP_Y + 0.004, TABLE_LEN / 2.0)
	return mi


func _ready() -> void:
	build()


func build() -> void:
	# --- Wood + felt materials shared across the build ---
	var wood_mat := _wood_material()
	var felt_mat := _felt_material()

	# --- Board physics (4.99 deg tilt: +Z end raised) ---
	board = StaticBody3D.new()
	var bs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(TABLE_WID, BOARD_THICK, TABLE_LEN)
	bs.shape = box
	board.add_child(bs)
	board.position = Vector3(0.0, -BOARD_THICK * 0.5, TABLE_LEN * 0.5)
	board.rotation.x = -deg_to_rad(TILT_DEG)
	board.collision_layer = 1
	board.collision_mask = 2
	add_child(board)

	# --- Wooden body (visual slab riding the physics board) ---
	var body_mesh := MeshInstance3D.new()
	var body_bm := BoxMesh.new()
	body_bm.size = Vector3(TABLE_WID, BOARD_THICK, TABLE_LEN)
	body_mesh.mesh = body_bm
	body_mesh.material_override = wood_mat
	body_mesh.position = board.position
	body_mesh.rotation.x = board.rotation.x
	add_child(body_mesh)

	# --- Felt playing surface (visual coat just above the wood) ---
	var felt_mesh := MeshInstance3D.new()
	var felt_bm := BoxMesh.new()
	felt_bm.size = Vector3(TABLE_WID, 0.006, TABLE_LEN)
	felt_mesh.mesh = felt_bm
	felt_mesh.material_override = felt_mat
	# Sit the felt top a fraction above the wood top face so balls visually
	# roll ON the felt (no z-fight with the wood).
	var felt_center := surface_y_at(0.0, TABLE_LEN * 0.5) + 0.0035
	felt_mesh.position = Vector3(0.0, felt_center, TABLE_LEN * 0.5)
	felt_mesh.rotation.x = board.rotation.x
	add_child(felt_mesh)

	# --- Pedestal legs (visual only; table reads as furniture, not floating) ---
	for lx in [-0.46, 0.46]:
		for lz in [0.32, 0.95, 1.88]:
			add_child(_leg(lx, lz))

	# --- Rails (tall vertical backstops + matching wood visuals) ---
	# The board surface varies from y=-0.126 (player end) to y=+0.066 (far end);
	# rails must stand from below the lowest ball center to above the highest.
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
		# Visual twin so the walls actually read on camera.
		var rail_mesh := MeshInstance3D.new()
		var rail_bm := BoxMesh.new()
		rail_bm.size = r.size
		rail_mesh.mesh = rail_bm
		rail_mesh.material_override = wood_mat
		rail_mesh.position = r.pos
		add_child(rail_mesh)

	# --- Rail caps (shelves that carry the hand-ball racks) ---
	add_child(_rail_cap(-1.0))
	add_child(_rail_cap(1.0))

	# --- Front return tray (physics + visible felt trough + wood lip) ---
	# Balls that roll back down (the sport's "Returned Ball" rule) come off the
	# leading edge into a shallow tray instead of falling forever - and they must
	# VISIBLY land in a tray, not float in void (v1's grey-screen bug).
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
	# Visible felt floor of the tray.
	var tf_mesh := MeshInstance3D.new()
	var tfm := BoxMesh.new()
	tfm.size = Vector3(TABLE_WID - 0.05, 0.018, 0.26)
	tf_mesh.mesh = tfm
	tf_mesh.material_override = felt_mat
	tf_mesh.position = Vector3(0.0, -0.139, -0.07)
	add_child(tf_mesh)

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
	# Visible wood lip of the tray.
	var tl_mesh := MeshInstance3D.new()
	var tlm := BoxMesh.new()
	tlm.size = Vector3(TABLE_WID - 0.05, 0.12, 0.04)
	tl_mesh.mesh = tlm
	tl_mesh.material_override = wood_mat
	tl_mesh.position = tray_lip.position
	add_child(tl_mesh)

	# --- Returned-ball detector (tray zone above the felt floor) ---
	# A live ball dropping into the tray is NOT lost (v1): it returns to the
	# shooter's rack. TableWorld freezes it and emits ball_returned; main gives
	# it back to the player's hand.
	_tray_zone = Area3D.new()
	var rz_cs := CollisionShape3D.new()
	var rz_b := BoxShape3D.new()
	rz_b.size = Vector3(TABLE_WID - 0.05, 0.16, 0.30)
	rz_cs.shape = rz_b
	_tray_zone.add_child(rz_cs)
	_tray_zone.position = Vector3(0.0, -0.140, -0.075)
	_tray_zone.collision_layer = 0
	_tray_zone.collision_mask = 2
	_tray_zone.monitoring = true
	_tray_zone.body_entered.connect(_on_tray_entered)
	add_child(_tray_zone)

	# --- Hand-ball rack channels (visual side shelves on the rail caps) ---
	# Each color has its own channel of 12 ball divots so the hand count is
	# readable at a glance (v1 stacked them into one ugly clump).
	for color in ["red", "black"]:
		var cx := rack_x(color)
		var side := -1.0 if color == "red" else 1.0
		var floor_y := _rack_floor_y(cx)
		# Channel floor (felt) on top of the rail cap.
		var ch_floor := MeshInstance3D.new()
		var cfm := BoxMesh.new()
		cfm.size = Vector3(RACK_W, 0.012, RACK_D)
		ch_floor.mesh = cfm
		ch_floor.material_override = felt_mat
		ch_floor.position = Vector3(cx, floor_y - 0.006, RACK_Z_START + RACK_D * 0.5)
		add_child(ch_floor)
		# Outer guide wall (wood), keeps balls from rolling off the side edge.
		var wall := MeshInstance3D.new()
		var wbm := BoxMesh.new()
		wbm.size = Vector3(0.025, 0.09, RACK_D)
		wall.mesh = wbm
		wall.material_override = wood_mat
		wall.position = Vector3(cx + side * (RACK_W * 0.5 - 0.0125), floor_y + 0.033, RACK_Z_START + RACK_D * 0.5)
		add_child(wall)

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

			# Visible pocket: a recessed emissive plate per slot so the bands read
			# like the broadcast tables. Color-coded by position (1/2/5 -> gold/silver/red).
			var plate_mesh := MeshInstance3D.new()
			var plate_bm := BoxMesh.new()
			plate_bm.size = Vector3(SLOT_W - 0.020, 0.010, SLOT_D - 0.010)
			plate_mesh.mesh = plate_bm
			plate_mesh.rotation.x = board.rotation.x
			plate_mesh.position = Vector3(x, s.position.y - 0.004, POS_Z[pi])
			var plate_mat := StandardMaterial3D.new()
			var pos_colors := [Color(0.93, 0.75, 0.22), Color(0.82, 0.85, 0.92), Color(0.78, 0.25, 0.22)]
			plate_mat.albedo_color = pos_colors[pi] * 0.6
			plate_mat.metallic = 0.3
			plate_mat.roughness = 0.3
			plate_mat.emission_enabled = true
			plate_mat.emission = pos_colors[pi]
			plate_mat.emission_energy_multiplier = 1.6
			plate_mesh.material_override = plate_mat
			add_child(plate_mesh)

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


## Spawns a frozen ball into its rack channel (in-hand). Color: "red"/"black".
func spawn_hand_ball(color: String) -> SCBBall:
	var b := SCBBall.create(color)
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	var n: int = int((hand_balls[color] as Array).size())
	b.position = rack_spot(color, n)
	add_child(b)
	hand_balls[color].append(b)
	return b


## Re-racks a ball that rolled back into the tray (Returned-Ball rule).
func reinsert_hand_ball(b: SCBBall) -> void:
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	var arr: Array = hand_balls[b.color]
	arr.append(b)
	b.position = rack_spot(b.color, arr.size() - 1)
	b.rotation = Vector3.ZERO


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


func _on_tray_entered(body: Node3D) -> void:
	var b := body as SCBBall
	if b == null or b.freeze:
		return
	# A live ball dropped into the return tray -> freezes and returns to the
	# shooter's rack instead of vanishing (v1's "lost ball" bug).
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	ball_returned.emit(b)


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