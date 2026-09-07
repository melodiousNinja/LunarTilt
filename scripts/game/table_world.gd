class_name TableWorld
extends Node3D

## TableWorld V3 - builds and owns the entire Star Cluster Ball table.
##
## Phase-1 changes that fixed "buggy, unplayable, clunky":
##   * REAL POCKETS. Each Astrolabe position is a star-edged recessed trough
##     cut into the felt - horizontal well floor, tall wood back-stop, pointed
##     star teeth on the front lip that HOOK the ball and hold it. Gone are the
##     flat emissive rectangles the ball could just sit on top of.
##   * SETTLE-BASED CAPTURE. Capture no longer fires at the instant a pocket is
##     entered (which missed balls that arrived fast and THEN settled). A ball
##     is captured only when it comes to rest inside a pocket area, every
##     physics frame. No more phantom scores / "ball sits in pocket doing
##     nothing".
##   * BIGGER BALLS. SCBBall.RADIUS_M = 0.030 (60 mm) so the ball is readable
##     on a phone. Rack channels, tray, and pockets sized for it.
##   * Returned-ball rule: balls that roll back off the player end land in the
##     front tray and are returned to the shooter's rack.

signal ball_scored(ball: SCBBall, band: int, keep_shooting: bool)
signal ball_guttered(ball: SCBBall)
signal ball_returned(ball: SCBBall)
signal ball_displaced(ball: SCBBall)
signal ball_grouped(ball: SCBBall)

const TABLE_LEN := 2.9      # Z axis (player end at Z=0, far end at Z=2.9)
const TABLE_WID := 1.2      # X axis
const TILT_DEG := 4.99
const BOARD_THICK := 0.06
const RAIL_T := 0.04
## Full height of the rail backstops (physics bodies).
const RAIL_H_TOTAL := 0.30
## World Y of the top face of the side rails (hand-ball racks rest on these).
const RAIL_TOP_Y := -0.03 + RAIL_H_TOTAL * 0.5

const SLOTS_PER_POS := 7              # deprecated alias (band 0 slit count)
const POS_Z := [1.35, 1.75, 2.15]     # astrolabe fan centres - CLUSTERED in
                                      # the upper half per the reference video
                                      # (long open run-up from the throw line,
                                      # small gaps between the three fans)
const MEDAL_R := 0.155                # deprecated alias
const CLUSTER_R := 0.096              # deprecated alias
const SOCKET_R := 0.037               # deprecated alias (ball r = 0.030)
## v13 FAN ASTROLABES (2026-09-06 close-up of the real table): each scoring
## position is a raised wooden FAN - solid blades with open GROOVE SLITS
## between them, mouths facing the thrower, standing on pins. A ball that
## rolls into a slit is caught by its walls + back wall (real geometry, no
## funnel); a ball that clips a blade DEFLECTS off the raised edge. Slit
## counts from the close-up: near fan 7 (1 pt), middle 5 "C B A C B" (2 pt),
## far 3 "B A B" (3 pt).
const FAN_GAPS := [7, 5, 3]
const FAN_POINTS := [1, 2, 3]
const FAN_MOUTH := [0.070, 0.078, 0.090]   # slit width at the mouth (ball dia 0.060)
const FAN_BLADE := [0.026, 0.032, 0.042]   # solid wood between slits
const FAN_DEPTH := [0.15, 0.16, 0.17]      # mouth-to-back depth
const FAN_H := 0.016                       # platform height above the marble
const PLATE_H := 0.010
const PLATE_NAMES := ["ONE", "TWO", "THREE"]
const POCKET_X_HALF := 0.60             # playable half-width the bands span
const PLAY_LINE_Z := 0.35
const LAUNCH_Z := 0.22                # ball spawn behind the play line

const BALLS_PER_COLOR := 12

# --- Hand-ball racks (visual side channels, player end) ---
const RACK_X_CENTER := 0.72        # channel center X per side (on the rail tops)
const RACK_W := 0.30               # channel width (X)
const RACK_D := 0.60               # channel depth (Z)
const RACK_Z_START := 0.02
const RACK_PITCH := 0.048          # (60 mm ball + 12 mm gap)

## A ball that has slowed below this while inside a scoring pocket is caught.
const SLOT_CAPTURE_SPEED := 0.35
## v12 DECISIVE CUP CAPTURE (2026-09 device session: 8 shots, 0 scores -
## the old funnel pulled with mass*1.6 and damped 1.5%/frame, so a ball
## crossing the 10 cm well zone at 0.4 m/s sailed through in 6 frames).
## A ball inside a well zone slower than this DROPS INTO THE CUP; faster
## balls are hauled by the strong funnel until they drop below it.
const CAPTURE_SPEED := 0.9
## Physics frames a ball must linger near-rest before the pocket claims it.
const SETTLE_FRAMES := 3
## True-rest thresholds (2026-09 live feedback): a ball decelerating up the
## slope hovers near zero speed at its arc apex for ~0.8 s; the old blanket
## "slow for 3 frames = settled" resolved it MID-FLIGHT, which is why balls
## vanished and never rolled back. Now only decisive zones (socket / tray /
## gutter) settle in SETTLE_FRAMES; the open felt demands TRUE rest so the
## full up-and-back path plays out and stopped balls persist as obstacles.
const FELT_REST_SPEED := 0.06
const FELT_SETTLE_FRAMES := 24

var board: StaticBody3D
var slots: Array = []        # [{ band:int, area:Area3D, color:String }]
var gutter: Area3D
var _tray_zone: Area3D
var _tray_floor: StaticBody3D
var hand_balls: Dictionary = {"red": [], "black": []}    # frozen in-rack balls

## Live balls the settle-detector tracks (main registers each launched ball).
var live_balls: Array = []
var _tracked: Array = []     # [{ball, frames}] settle-state per live ball
var _any_moving := false     # true if any tracked ball was moving last frame


## World-space height of the board's top surface at (x, z).
## Exact geometry: the box center sits at y=-BOARD_THICK/2, z=TABLE_LEN/2,
## rotated -TILT_DEG around X.
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
	return surface_y_static(x, z) + SCBBall.RADIUS_M + 0.002


# ------------------------------------------------------------- pure layout --

static func rack_x(color: String) -> float:
	return -RACK_X_CENTER if color == "red" else RACK_X_CENTER


static func _rack_floor_y(_x: float) -> float:
	return RAIL_TOP_Y + 0.004


## World position of rack ball #index for a color. Pure math so unit tests can
## verify spacing without constructing a physics scene.
static func rack_spot(color: String, index: int) -> Vector3:
	var x := rack_x(color)
	var z := RACK_Z_START + index * RACK_PITCH
	return Vector3(x, _rack_floor_y(x) + SCBBall.RADIUS_M, z)


## Width of fan `bi`: (G+1) blades + G slit mouths.
static func fan_width(bi: int) -> float:
	var b := clampi(bi, 0, 2)
	return float(FAN_GAPS[b] + 1) * FAN_BLADE[b] + float(FAN_GAPS[b]) * FAN_MOUTH[b]

## World XZ of groove gap `si` (0 = leftmost) of fan `bi` - the gap centre
## between spike `si` and spike `si+1` on the arc. Callers add surface height.
static func socket_pos(bi: int, si: int) -> Vector3:
	var b := clampi(bi, 0, 2)
	var cz: float = POS_Z[b]
	var g: int = FAN_GAPS[b]
	var col := clampi(si, 0, g - 1)
	var fw := fan_width(b)
	var gx := -fw * 0.5 + (float(col) + 0.5) / float(g) * fw
	return Vector3(gx, 0.0, cz)


## 8 corners of the visual frame we care about (racks + tray + table + gutter).
static func frame_points() -> Array:
	var pts: Array = []
	# v6 (2026-09 live feedback "table is so small"): frame the BOARD, not the
	# board + side racks. The racks sit on the rail tops off the play area;
	# including them ate ~40% of the portrait width. x half-extent is now the
	# playable width + rails (0.60 + 0.10), z spans tray to past the far rail.
	for x in [-0.70, 0.70]:
		for z in [-0.26, 2.55]:
			for y in [-0.06, 0.16]:
				pts.append(Vector3(x, y, z))
	return pts
## Walnut frame material: procedural Simplex noise baked once as a wood-grain
## albedo (no asset files needed, stays small for mobile).
func _wood_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	# Deep walnut; the grain texture (greyscale noise) modulates it.
	mat.albedo_color = Color(0.20, 0.115, 0.065)
	mat.roughness = 0.38
	mat.metallic = 0.0
	mat.clearcoat_enabled = true
	mat.clearcoat = 0.7
	mat.clearcoat_roughness = 0.22
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


## Factory-spec playing surface: polished white marble with wandering
## grey-blue veins (the real YoTyan table is marble). Procedural shader, so
## it stays crisp at any resolution and needs no texture assets.
func _surface_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/marble.gdshader")
	# Modern broadcast palette: deep slate body with teal veining (player and
	# ball colours pop against it; brass lines read as inlays).
	mat.set_shader_parameter("vein_scale", 4.0)
	# Satin stone, not mirror: at the camera's grazing angle a low-roughness
	# surface Fresnel-reflects the bright sky and washes the body out to white.
	mat.set_shader_parameter("body_col", Color(0.16, 0.20, 0.22))
	mat.set_shader_parameter("vein_col", Color(0.13, 0.40, 0.38))
	mat.set_shader_parameter("rough_min", 0.34)
	mat.set_shader_parameter("rough_max", 0.55)
	return mat


## Short turned pedestal leg under the table (visual only).
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
	var top_y := surface_y_at(vx, vz) - 0.055
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
	var wood_mat := _wood_material()
	var surface_mat := _surface_material()

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

	var body_mesh := MeshInstance3D.new()
	var body_bm := BoxMesh.new()
	body_bm.size = Vector3(TABLE_WID, BOARD_THICK, TABLE_LEN)
	body_mesh.mesh = body_bm
	body_mesh.material_override = wood_mat
	body_mesh.position = board.position
	body_mesh.rotation.x = board.rotation.x
	add_child(body_mesh)

	# --- Felt playing surface ---
	var felt_mesh := MeshInstance3D.new()
	var felt_bm := BoxMesh.new()
	felt_bm.size = Vector3(TABLE_WID, 0.006, TABLE_LEN)
	felt_mesh.mesh = felt_bm
	felt_mesh.material_override = surface_mat
	var felt_center := surface_y_at(0.0, TABLE_LEN * 0.5) + 0.0035
	felt_mesh.position = Vector3(0.0, felt_center, TABLE_LEN * 0.5)
	felt_mesh.rotation.x = board.rotation.x
	add_child(felt_mesh)

	# --- Guard lines (factory look): brass boundary inlays along both side
	# rails plus a white foul line at the shooting end, laid ON the marble ---
	var brass_inlay := StandardMaterial3D.new()
	brass_inlay.albedo_color = Color(0.72, 0.58, 0.28)
	brass_inlay.metallic = 0.9
	brass_inlay.roughness = 0.28
	var white_inlay := StandardMaterial3D.new()
	white_inlay.albedo_color = Color(0.93, 0.91, 0.86)
	white_inlay.roughness = 0.5
	for side in [-1.0, 1.0]:
		var gl := MeshInstance3D.new()
		var gm := BoxMesh.new()
		gm.size = Vector3(0.012, 0.0025, TABLE_LEN - 0.12)
		gl.mesh = gm
		gl.material_override = brass_inlay
		var gz := (TABLE_LEN - 0.12) * 0.5 + 0.06
		gl.position = Vector3(side * (TABLE_WID / 2.0 - 0.024),
			surface_y_at(0.0, gz) + 0.0045, gz)
		gl.rotation.x = board.rotation.x
		add_child(gl)
	var foul := MeshInstance3D.new()
	var fm2 := BoxMesh.new()
	fm2.size = Vector3(TABLE_WID - 0.10, 0.0025, 0.016)
	foul.mesh = fm2
	foul.material_override = white_inlay
	var fz := 0.45
	foul.position = Vector3(0.0, surface_y_at(0.0, fz) + 0.0045, fz)
	foul.rotation.x = board.rotation.x
	add_child(foul)

	for lx in [-0.46, 0.46]:
		for lz in [0.32, 0.95, 1.88]:
			add_child(_leg(lx, lz))

	# --- Rails (tall backstops + wood visuals) ---
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

	# --- Front tray (the Returned-Ball rule needs a place to land!) ---
	# LIVE-PROVEN (2026-09 device + bisect): _tray_zone/_tray_floor were
	# declared but NEVER built, so every ball that rolled back off the player
	# end free-fell into the void. The served ball also creeps back down the
	# slope while the player aims and vanishes the same way - the "invisible
	# ball" report. The tray gives returned balls a physical home.
	_build_tray()

	# --- Scoring sockets: three brass astrolabe medallions (THE factory look) ---
	_build_astrolabes()
	_build_guardlines()
const POS_GLOW := [Color(0.93, 0.75, 0.22), Color(0.82, 0.85, 0.92), Color(0.78, 0.25, 0.22)]
const CLAIM_GLOW := {"red": Color(0.95, 0.25, 0.18), "black": Color(0.55, 0.58, 0.65)}


func _brass_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.72, 0.58, 0.28)
	mat.metallic = 0.95
	mat.roughness = 0.28
	return mat


## Procedural half-disc plank: flat edge at local +Z (the back), arc bulging
## toward local -Z (the bowl mouth facing the thrower).
func _half_disc_mesh(radius: float, thick: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segs := 16
	var y0 := -thick * 0.5
	var y1 := thick * 0.5
	var prev := Vector3(radius, 0, 0)
	for i in range(1, segs + 1):
		var a := PI * float(i) / float(segs)
		var nxt := Vector3(cos(a) * radius, 0, -sin(a) * radius)
		# top face fan
		st.add_vertex(Vector3(0, y1, 0))
		st.add_vertex(prev + Vector3(0, y1, 0))
		st.add_vertex(nxt + Vector3(0, y1, 0))
		# bottom face fan (reversed)
		st.add_vertex(Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y0, 0))
		st.add_vertex(prev + Vector3(0, y0, 0))
		# arc rim wall
		st.add_vertex(prev + Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y1, 0))
		st.add_vertex(prev + Vector3(0, y0, 0))
		st.add_vertex(nxt + Vector3(0, y1, 0))
		st.add_vertex(prev + Vector3(0, y1, 0))
		prev = nxt
	# flat back face (the diameter)
	st.add_vertex(Vector3(-radius, y0, 0))
	st.add_vertex(Vector3(radius, y0, 0))
	st.add_vertex(Vector3(radius, y1, 0))
	st.add_vertex(Vector3(-radius, y0, 0))
	st.add_vertex(Vector3(radius, y1, 0))
	st.add_vertex(Vector3(-radius, y1, 0))
	st.generate_normals()
	return st.commit()


## v14 FAN ASTROLABES - built exactly to the user's spec from the close-up:
## a semi-circular wooden base plank ("the bowl"), a TRIANGULAR plank on top
## of it (centre ridge highest), and equal-length wooden spikes standing on
## that plank along the arc - so the spike TIPS form a slight slant with the
## centre spike proudest. Balls roll up-slope, pass between the spike comb,
## and nest on the plank between two spikes, where the slit area claims them.
func _build_astrolabes() -> void:
	var wood := _wood_material()
	for bi in range(POS_Z.size()):
		var cz: float = POS_Z[bi]
		var g: int = FAN_GAPS[bi]
		var m: float = FAN_MOUTH[bi]
		var depth: float = FAN_DEPTH[bi]
		var half_w := fan_width(bi) * 0.5
		var w := half_w * 2.0
		var sy: float = surface_y_at(0.0, cz)
		# one physics body per fan, tilted with the board
		var fan := StaticBody3D.new()
		fan.collision_layer = 1
		fan.collision_mask = 2
		fan.position = Vector3(0.0, sy, cz)
		fan.rotation.x = -deg_to_rad(TILT_DEG)
		# --- semi-circular base plank (the bowl) ---
		var bmat := _wood_material()
		bmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		var base_mi := MeshInstance3D.new()
		base_mi.mesh = _half_disc_mesh(half_w, 0.012)
		base_mi.material_override = bmat
		base_mi.position = Vector3(0.0, 0.006, depth * 0.2)
		fan.add_child(base_mi)
		var bcs := CollisionShape3D.new()
		var bshape := BoxShape3D.new()
		bshape.size = Vector3(w, 0.012, depth * 0.95)
		bcs.shape = bshape
		bcs.position = Vector3(0.0, 0.006, depth * 0.2)
		fan.add_child(bcs)
		# --- triangular plank on top: gabled roof, centre ridge highest,
		# surface also rising slightly toward the back where balls rest ---
		var ridge_h := 0.018
		var back_h := 0.014
		var slope := atan2(ridge_h, half_w)
		for side in [-1.0, 1.0]:
			var roof := CollisionShape3D.new()
			var rshape := BoxShape3D.new()
			rshape.size = Vector3(half_w * 1.02, 0.014, depth * 0.92)
			roof.shape = rshape
			roof.position = Vector3(side * half_w * 0.5, 0.012 + ridge_h * 0.5, depth * 0.16)
			roof.rotation = Vector3(atan2(back_h, depth), 0.0, -side * slope)
			fan.add_child(roof)
			var rmi := MeshInstance3D.new()
			var rmesh := BoxMesh.new()
			rmesh.size = rshape.size
			rmi.mesh = rmesh
			rmi.material_override = wood
			rmi.position = roof.position
			rmi.rotation = roof.rotation
			fan.add_child(rmi)
		# --- spike comb along the arc: equal-length pins standing on the
		# gabled plank - tips slant down from the proudest centre spike ---
		var spike_len := 0.030
		for i in range(g + 1):
			var fx := -half_w + (float(i) / float(g)) * w
			var arc := 1.0 - pow(fx / half_w, 2.0)
			var sz := -depth * 0.5 + (1.0 - arc) * depth * 0.55
			var roof_h := 0.012 + ridge_h * (1.0 - absf(fx) / half_w) \
				+ back_h * clampf((sz + depth * 0.5) / depth, 0.0, 1.0)
			var sp := CollisionShape3D.new()
			var scShape := CylinderShape3D.new()
			scShape.radius = 0.005
			scShape.height = spike_len
			sp.shape = scShape
			sp.position = Vector3(fx, roof_h + spike_len * 0.5 - 0.003, sz)
			fan.add_child(sp)
			var smi := MeshInstance3D.new()
			var scm := CylinderMesh.new()
			scm.top_radius = 0.0045
			scm.bottom_radius = 0.0055
			scm.height = spike_len
			smi.mesh = scm
			smi.material_override = _brass_material()
			smi.position = sp.position
			fan.add_child(smi)
		# --- back wall: the flat edge balls finally rest against ---
		var wcs := CollisionShape3D.new()
		var wshape := BoxShape3D.new()
		wshape.size = Vector3(w, 0.030, 0.012)
		wcs.shape = wshape
		wcs.position = Vector3(0.0, 0.015, depth * 0.5)
		fan.add_child(wcs)
		var wmesh := MeshInstance3D.new()
		var wbmm := BoxMesh.new()
		wbmm.size = wshape.size
		wmesh.mesh = wbmm
		wmesh.material_override = wood
		wmesh.position = wcs.position
		fan.add_child(wmesh)
		add_child(fan)
		# --- per-gap: capture area + claim-glow floor + mouth letter ---
		for si in range(g):
			var fx0 := -half_w + (float(si) / float(g)) * w
			var fx1 := -half_w + (float(si + 1) / float(g)) * w
			var gx := (fx0 + fx1) * 0.5
			var arc0 := 1.0 - pow(fx0 / half_w, 2.0)
			var arc1 := 1.0 - pow(fx1 / half_w, 2.0)
			var gz := -depth * 0.5 + (1.0 - (arc0 + arc1) * 0.5) * depth * 0.55 + depth * 0.2
			var roof_h := 0.012 + ridge_h * (1.0 - absf(gx) / half_w) \
				+ back_h * clampf((gz + depth * 0.5) / depth, 0.0, 1.0)
			var area := Area3D.new()
			var cs := CollisionShape3D.new()
			var sb := BoxShape3D.new()
			sb.size = Vector3(m * 0.9, 0.06, depth * 0.7)
			cs.shape = sb
			area.add_child(cs)
			area.position = Vector3(gx, 0.03, gz)
			area.collision_layer = 0
			area.collision_mask = 2
			area.monitoring = true
			fan.add_child(area)
			# dark claim-glow strip lying on the plank between the spikes
			var cup_mat := StandardMaterial3D.new()
			cup_mat.albedo_color = Color(0.05, 0.05, 0.06)
			cup_mat.roughness = 0.85
			var slit_floor := MeshInstance3D.new()
			var sfm := BoxMesh.new()
			sfm.size = Vector3(m * 0.8, 0.004, depth * 0.5)
			slit_floor.mesh = sfm
			slit_floor.material_override = cup_mat
			slit_floor.position = Vector3(gx, roof_h + 0.006, gz)
			fan.add_child(slit_floor)
			# letter etched at the slit mouth (A at the centre, outward B, C..)
			var letter_idx := clampi(int(absf(float(si) - float(g - 1) * 0.5)), 0, 5)
			var llbl := Label3D.new()
			llbl.text = "ABCDEF".substr(letter_idx, 1)
			llbl.modulate = Color(0.85, 0.83, 0.78)
			llbl.font_size = 40
			llbl.pixel_size = 0.0006
			llbl.outline_size = 0
			llbl.rotation_degrees = Vector3(-84.0, 0.0, 0.0)
			llbl.position = Vector3(gx, roof_h + 0.004, -depth * 0.5 - 0.024)
			fan.add_child(llbl)
			slots.append({"band": bi, "col": si, "area": area, "color": "",
				"cup": cup_mat})
		# point value painted on the marble just past the fan's back wall
		var lbl := Label3D.new()
		lbl.text = str(FAN_POINTS[bi])
		lbl.modulate = Color(0.78, 0.16, 0.14)
		lbl.font_size = 110
		lbl.pixel_size = 0.0006
		lbl.outline_size = 0
		lbl.rotation_degrees = Vector3(-84.0, 0.0, 0.0)
		lbl.position = Vector3(0.0, sy + 0.004, cz + depth * 0.5 + 0.030)
		add_child(lbl)


## Brass guardline inlays up both edges of the playfield (the factory table's
## etched border lines). Segmented so each piece hugs the 5-degree tilt.
func _build_guardlines() -> void:
	var brass := _brass_material()
	var y_far := surface_y_at(0.0, TABLE_LEN)
	var y_near := surface_y_at(0.0, 0.0)
	var slope := atan2(y_far - y_near, TABLE_LEN)
	var segs := 8
	var seg_len := (TABLE_LEN - 0.20) / float(segs)
	for side in [-1.0, 1.0]:
		var x_edge: float = side * (TABLE_WID / 2.0 - 0.035)
		for i in range(segs):
			var z_mid := 0.10 + seg_len * (float(i) + 0.5)
			var seg := MeshInstance3D.new()
			var bm := BoxMesh.new()
			bm.size = Vector3(0.010, 0.0025, seg_len)
			seg.mesh = bm
			seg.material_override = brass
			seg.position = Vector3(x_edge, surface_y_at(x_edge, z_mid) + 0.002, z_mid)
			seg.rotation.x = -slope
			add_child(seg)
## The player-end tray: returned balls land here and are re-racked.
## Floor top at y=-0.13 (the height test A's comment always assumed), walls
## on all open sides so a returned ball rests instead of escaping.
func _build_tray() -> void:
	var wood_mat := _wood_material()
	var bodies := [
		# floor: x -0.64..0.64, top at -0.13, z -0.26..0.0
		{"size": Vector3(1.28, 0.04, 0.26), "pos": Vector3(0.0, -0.15, -0.13)},
		# front wall (player side)
		{"size": Vector3(1.28, 0.12, 0.04), "pos": Vector3(0.0, -0.09, -0.24)},
		# side walls
		{"size": Vector3(0.04, 0.12, 0.26), "pos": Vector3(-0.62, -0.09, -0.13)},
		{"size": Vector3(0.04, 0.12, 0.26), "pos": Vector3(0.62, -0.09, -0.13)},
	]
	for r in bodies:
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
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = r.size
		mi.mesh = bm
		mi.material_override = wood_mat
		mi.position = r.pos
		add_child(mi)
	# Return-detection zone hovering over the tray floor.
	_tray_zone = Area3D.new()
	var zs := CollisionShape3D.new()
	var zb := BoxShape3D.new()
	zb.size = Vector3(1.2, 0.10, 0.22)
	zs.shape = zb
	_tray_zone.add_child(zs)
	_tray_zone.position = Vector3(0.0, -0.10, -0.13)
	_tray_zone.collision_layer = 0
	_tray_zone.collision_mask = 2
	_tray_zone.monitoring = true
	add_child(_tray_zone)
	# Deep GUTTER (official rule: a ball that overshoots the last astrolabe is
	# lost). SESSION-PROVEN (2026-09-05, 29-shot live session): balls reached
	# z=3.09 past the far rail but the gutter was never built (the var stayed
	# null) so zero shots ever guttered - they all came back as returned.
	# Full-width catch volume: z 2.50..3.45, y -0.40..+0.32 (catches rolling
	# AND flying balls that clear the deep end).
	gutter = Area3D.new()
	var gs := CollisionShape3D.new()
	var gb := BoxShape3D.new()
	# Tall catch volume: overpowered balls cross the gutter line while still
	# AIRBORNE (sweep: y up to 0.66) - the volume must reach up to ~0.85 so
	# the claim fires wherever the ball dies in the channel.
	gb.size = Vector3(1.34, 1.30, 0.95)
	gs.shape = gb
	gutter.add_child(gs)
	gutter.position = Vector3(0.0, 0.20, 2.975)
	gutter.collision_layer = 0
	gutter.collision_mask = 2
	gutter.monitoring = true
	add_child(gutter)
	# Physical trench under the gutter volume: floor + back wall + side walls.
	# Without a floor, a ball that flew past Jupiter void-fell below the world
	# (y < -0.5) where the escape guard mis-rated it as a RETURNED ball. With
	# the trench, it visibly lands in the channel and is claimed as guttered.
	var trench := [
		{"size": Vector3(1.34, 0.04, 1.10), "pos": Vector3(0.0, -0.12, 2.95)},
		# Tall backstop + high side walls: overpowered balls (sweep p=6.4)
		# crossed the old 0.18 m wall AIRBORNE (y up to 0.66) and escaped past
		# the world, where the escape guard mis-rated them as returned. The
		# real table's far end is a tall wooden cabinet - match it.
		{"size": Vector3(1.34, 1.00, 0.04), "pos": Vector3(0.0, 0.33, 3.48)},
		{"size": Vector3(0.04, 0.60, 1.10), "pos": Vector3(-0.65, 0.18, 2.95)},
		{"size": Vector3(0.04, 0.60, 1.10), "pos": Vector3(0.65, 0.18, 2.95)},
	]
	for r in trench:
		var tb := StaticBody3D.new()
		var tcs := CollisionShape3D.new()
		var tbs := BoxShape3D.new()
		tbs.size = r.size
		tcs.shape = tbs
		tb.add_child(tcs)
		tb.position = r.pos
		tb.collision_layer = 1
		tb.collision_mask = 2
		add_child(tb)
		# VISIBLE trench: the channel used to be colliders-only - an invisible
		# void the ball simply fell into. A dark channel floor + wood walls
		# read as the real game's deep gutter cabinet.
		var tm := MeshInstance3D.new()
		var tbm := BoxMesh.new()
		tbm.size = r.size
		tm.mesh = tbm
		var tmat := StandardMaterial3D.new()
		if (r["pos"] as Vector3).y < -0.05:
			tmat.albedo_color = Color(0.10, 0.11, 0.13)
			tmat.roughness = 0.85
		else:
			tmat.albedo_color = Color(0.30, 0.20, 0.12)
			tmat.roughness = 0.75
		tm.material_override = tmat
		tm.position = r.pos
		add_child(tm)


func _physics_process(_delta: float) -> void:
	# Adopt any live ball that lost its tracker (a ball knocked loose out of
	# a slit by a later shot, for example) so EVERY ball stays watched until
	# it reaches a terminal state - no more orphaned balls stuck mid-board.
	for lb in live_balls:
		if lb == null or not is_instance_valid(lb) or (lb as SCBBall).freeze:
			continue
		var known := false
		for t in _tracked:
			if t.get("ball") == lb:
				known = true
				break
		if not known:
			_tracked.append({"ball": lb, "frames": 0, "anchor": null, "nudges": 0})
	if _tracked.size() == 0:
		return
	_any_moving = false
	var still: Array = []
	for t in _tracked:
		var b: Variant = t.get("ball")
		if b == null or not is_instance_valid(b):
			continue
		var bb := b as SCBBall
		if bb.freeze:
			continue
		# ESCAPE GUARD FIRST: anything beyond the trench (z > 3.5), below the
		# world, or way off-line is an overpowered/lost ball - snap it into
		# the channel and claim GUTTERED. This must precede the deep-zone
		# altitude gate, else a flyer past z=3.5 lands in that branch, finds
		# no gutter overlap at its far position, and comes back as a bogus
		# "returned" ball (sweep p=6.4: end=(0, 0.054, 5.26)).
		if bb.position.z > 3.5 or bb.position.y < -0.5 or absf(bb.position.x) > 3.0:
			bb.position.x = clampf(bb.position.x, -0.55, 0.55)
			bb.position.z = clampf(bb.position.z, 2.60, 3.40)
			bb.position.y = -0.10 + SCBBall.RADIUS_M + 0.002
			_freeze_in_place(bb)
			ball_guttered.emit(bb)
			continue
		# Deep-zone rule: anything past the last astrolabe (z > 2.5) is in the
		# gutter. But an OVERPOWERED ball crosses that line while still AIRBORNE
		# (sweep: y up to 0.66) - resolving it there froze the ball mid-wall.
		# Altitude gate: flying balls keep flying into the trench and are
		# claimed the moment they land (or die) inside the gutter volume.
		if bb.position.z > 2.5:
			if bb.position.y < 0.10 or bb.linear_velocity.length() < 0.05:
				_resolve_ball(t)
			else:
				_any_moving = true
				still.append(t)
			continue
		var spd := bb.linear_velocity.length()
		if spd > (0.03):
			_any_moving = true
		# v13 SLIT CAPTURE: the grooves are real geometry now - walls + back
		# wall catch the ball, wood friction holds it against the slope. No
		# funnel forces. A ball inside a slit area slower than CAPTURE_SPEED
		# is claimed by _resolve_ball (official claim / grouping / block);
		# faster balls skim across the open slits or deflect off the blades.
		if spd < CAPTURE_SPEED and not _socket_overlapping(bb).is_empty():
			_resolve_ball(t)
			continue
		# Zone-aware settle (see FELT_REST_SPEED above): decisive zones settle
		# fast; open felt requires true rest so roll-backs finish their arc.
		if spd > FELT_REST_SPEED:
			t["frames"] = 0
			t["anchor"] = bb.position
			still.append(t)
			continue
		t["frames"] = int(t["frames"]) + 1
		if t.get("anchor") == null:
			t["anchor"] = bb.position
		# OPEN FELT: the sport's path rule - a ball that fails to reach a
		# groove keeps its FULL arc: it rolls back down to the player's tray.
		# We never freeze a ball mid-board. If the engine's static friction
		# pins it on the slope (mu > tan 5 deg), nudge it down-slope; only a
		# ball still pinned after 3 nudges is resolved (as a returned ball).
		if _socket_overlapping(bb).is_empty() \
				and not (_tray_zone != null and _tray_zone.overlaps_body(b)) \
				and not (gutter != null and gutter.overlaps_body(b)):
			var anchor: Variant = t.get("anchor")
			var pinned := anchor != null \
					and (bb.position - (anchor as Vector3)).length() <= 0.004
			if not pinned:
				t["frames"] = 0
				t["anchor"] = bb.position
				t["nudges"] = 0
				still.append(t)
				continue
			t["nudges"] = int(t.get("nudges", 0)) + 1
			if int(t["nudges"]) <= 5:
				# hop + push: break static contact so the ball visibly
				# struggles free and finishes its roll-back to the tray
				bb.sleeping = false
				bb.apply_central_impulse(Vector3(0.0, 0.10, -0.7) * bb.mass)
				t["frames"] = 0
				t["anchor"] = bb.position
				still.append(t)
				continue
			_resolve_ball(t)
			continue
		if int(t["frames"]) >= SETTLE_FRAMES:
			_resolve_ball(t)
			continue
		still.append(t)
	_tracked = still


func _inside_slot_area(b: SCBBall) -> bool:
	for sd in slots:
		if (sd["area"] as Area3D).overlaps_body(b):
			return true
	return false


## Force-resolve every tracked ball right now(((safety: main calls this when a shot
## stalls without emitting outcome signals,and every trailing ball needs a terminal
## state so the turn can pass. Balls resting in a slot score; anything else
## is treated as a returned ball per the sport's rule.
func flush_live() -> void:
	var pending: Array = _tracked.duplicate()
	for t in pending:
		_resolve_ball(t)
## Resolve a settled ball with the OFFICIAL outcome precedence:
##   1. Gutter            -> lost, turn passes.
##   2. Tray (rolled back)-> Returned-Ball rule, back to the rack, free shot.
##   3. Socket            -> official GROUPING rules via RulesEngine:
##        claim empty socket  -> ball STAYS as a blocker, scored, turn passes
##        adjacent own ball   -> that ball returns to its rack (displacement),
##                               shooter KEEPS shooting
##        walled by opponent  -> ball rests as a grouping wall, turn passes
##   4. Open felt         -> Returned-Ball rule (never-scored balls roll back).
## Every branch gives the ball a terminal state, so a turn can never hang.
func _resolve_ball(t: Dictionary) -> void:
	var b: Variant = t.get("ball")
	if b == null or not is_instance_valid(b) or (b as SCBBall).freeze:
		return
	var bb: SCBBall = b as SCBBall
	var is_returned := _tray_zone != null and _tray_zone.overlaps_body(b)
	var is_guttered := gutter != null and gutter.overlaps_body(b)
	if is_guttered:
		# Snap INTO the trench channel, not onto the extrapolated felt plane:
		# ball_rest_y() has no knowledge of the trench cut-out (z>2.55), so
		# snapping to it froze balls floating 19 cm above the channel (sweep
		# p=4.4: end y=0.0898). Trench floor top is y=-0.10; rest = floor +
		# radius + lip.
		bb.position.x = clampf(bb.position.x, -0.55, 0.55)
		bb.position.z = clampf(bb.position.z, 2.60, 3.40)
		bb.position.y = -0.10 + SCBBall.RADIUS_M + 0.002
		_freeze_in_place(bb)
		ball_guttered.emit(bb)
		return
	if is_returned:
		reinsert_hand_ball(bb)
		ball_returned.emit(bb)
		return
	var sd := _socket_overlapping(b)
	if not sd.is_empty():
		# v14 BOOKED SLOTS ARE PERMANENT (2026-09 user rule): a gap holding
		# a ball can never be recaptured or displaced - later balls simply
		# bounce off the sitting one (it is a solid frozen body) and rest
		# against it as a grouping wall. Only an EMPTY gap can be claimed.
		if String(sd["color"]) != "":
			_freeze_in_place(bb)
			ball_grouped.emit(bb)
			return
		_claim_socket(sd, bb)
		ball_scored.emit(bb, int(sd["band"]), false)
		return
	# Open felt: a 5-degree slope cannot hold a ball - the real sport never
	# lets one rest mid-board (2026-09 user feedback: stuck balls "very
	# annoying"). The settle-detector nudged it 5 times already; resolve it
	# now by the sport's Returned-Ball rule: back to the rack, free shot.
	reinsert_hand_ball(bb)
	ball_returned.emit(bb)


## Safe sound hook: the Sfx autoload is absent in headless test runs, so
## resolve it lazily instead of by global identifier (keeps tests parseable).
func _sfx(name: String, pitch := 1.0, vol_db := 0.0) -> void:
	var snd := get_node_or_null("/root/Sfx")
	if snd != null:
		snd.play(name, pitch, vol_db)


## ---- official socket ownership / grouping helpers (2026-09 rules pass) ----

## "band:col" -> the SCBBall currently claiming that socket.
var socket_balls := {}

func _socket_overlapping(b: SCBBall) -> Dictionary:
	for sd in slots:
		if (sd["area"] as Area3D).overlaps_body(b):
			return sd
	return {}

func _socket_at(band: int, col: int) -> Dictionary:
	for sd in slots:
		if int(sd["band"]) == band and int(sd["col"]) == col:
			return sd
	return {}

## Occupancy of one position's 7 sockets, in column order (creation order).
func _occupancy(band: int) -> Array:
	var occ: Array = []
	for sd in slots:
		if int(sd["band"]) == band:
			occ.append(String(sd["color"]))
	return occ

func _socket_key(band: int, col: int) -> String:
	return "%d:%d" % [band, col]

## Removes the ball claiming a socket (returns it; caller re-racks it) and
## frees the socket for a new claim.
func _take_socket_ball(band: int, col: int) -> SCBBall:
	var key := _socket_key(band, col)
	var ball_v: Variant = socket_balls.get(key)
	socket_balls.erase(key)
	if ball_v != null and is_instance_valid(ball_v):
		var sd := _socket_at(band, col)
		if not sd.is_empty():
			sd["color"] = ""
			_recolor_plate(sd, "")
		return ball_v as SCBBall
	return null

## A claimed socket: the ball freezes IN the pocket as a permanent blocker
## and the socket glows in the owner's colour.
func _claim_socket(sd: Dictionary, b: SCBBall) -> void:
	sd["color"] = b.color
	_recolor_plate(sd, b.color)
	socket_balls[_socket_key(int(sd["band"]), int(sd["col"]))] = b
	# NO teleport (v14 user rule - nothing "magically" moves): the ball
	# stays exactly where physics settled it and is frozen in its groove.
	_freeze_in_place(b)

func _freeze_in_place(b: SCBBall) -> void:
	b.freeze = true
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	# KEEP collision layers (2026-09 live feedback: frozen balls were ghosts -
	# live shots flew straight through every claimed ball). A frozen body is
	# static; layer 2 / mask 3 keeps it a solid, hittable obstacle so later
	# shots clack into it, knock it around, and the board reads as a real game.
	b.collision_layer = 2
	b.collision_mask = 3

func _recolor_plate(sd: Dictionary, color: String) -> void:
	var mat_v: Variant = sd.get("cup")
	if mat_v == null or not (mat_v is StandardMaterial3D):
		return
	var m := mat_v as StandardMaterial3D
	if color == "":
		m.albedo_color = Color(0.05, 0.05, 0.06)
		m.emission_enabled = false
	else:
		m.albedo_color = CLAIM_GLOW[color] * 0.55
		m.emission_enabled = true
		m.emission = CLAIM_GLOW[color]
		m.emission_energy_multiplier = 0.9


## Track a freshly-launched ball so the settle-detector resolves it.
func track_live(b: SCBBall) -> void:
	if b != null and not _tracked.has(b):
		live_balls.append(b)
		_tracked.append({"ball": b, "frames": 0})


## True while any tracked (live) ball is still moving. main waits for this
## before resolving a shot.
func any_moving() -> bool:
	return _any_moving


func lane_at(band: int) -> int:
	return SLOTS_PER_POS


func slot_at(index: int) -> Dictionary:
	return slots[index]


func _slot_area_index(a: Area3D) -> int:
	for i in range(slots.size()):
		if slots[i]["area"] == a:
			return i
	return -1


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
	if not is_instance_valid(b):
		return
	b.freeze = true
	b.collision_layer = 0
	b.collision_mask = 0
	b.linear_velocity = Vector3.ZERO
	b.angular_velocity = Vector3.ZERO
	var arr: Array = hand_balls[b.color]
	if not arr.has(b):
		arr.append(b)
	b.position = rack_spot(b.color, arr.size() - 1)
	b.rotation = Vector3.ZERO


## Serve lane alternation (2026-09 live feedback / duel feel): each serve
## flips side, so the player shoots from the bottom-left lane, then the
## bottom-right, alternating like the real sport's lane rule.
var serve_side := 1.0

## Serves an in-hand ball as a FROZEN MARKER at the launch point.
## LIVE-PROVEN (2026-09 device telemetry + headless bisect): a LIVE ball at
## the launch spot creeps back down the 5-degree slope while the player aims,
## rolls off the board's front edge (there was no tray), and free-falls into
## the void - the "invisible ball" that every shot then fired at (y -15 m and
## -92 m at release). The marker cannot move; launch_hand_ball turns it into
## a fresh live ball at the exact same transform at release time.
func take_hand_ball(color: String) -> SCBBall:
	if hand_balls[color].is_empty():
		return null
	var pooled: SCBBall = hand_balls[color].pop_back()
	if pooled != null and is_instance_valid(pooled):
		pooled.queue_free()
	var b := SCBBall.create(color)
	b.freeze = true          # display marker - cannot creep, cannot fall
	b.collision_layer = 0
	b.collision_mask = 0
	# TRANSFORM BEFORE add_child (Jolt must register it at the launch spot).
	serve_side = -serve_side
	var sx := 0.40 * serve_side
	b.position = Vector3(sx, ball_rest_y(sx, LAUNCH_Z), LAUNCH_Z)
	b.rotation = Vector3.ZERO
	add_child(b)
	print("SCB serve %s marker side=%.1f at %s" % [color, serve_side, b.position])
	return b


## Fires the shot: replaces the frozen marker with a FRESH live ball at the
## same transform and gives it its velocity on the very first frame (the
## pattern test A proves safe). Returns the live ball, already tracked by
## the settle-detector. A fresh body never carries stale physics state.
func launch_hand_ball(marker: SCBBall, velocity: Vector3) -> SCBBall:
	if marker == null or not is_instance_valid(marker):
		return null
	var pos: Vector3 = marker.position
	var ball_color: String = marker.color
	marker.queue_free()
	var b := SCBBall.create(ball_color)
	b.position = pos
	add_child(b)
	b.linear_velocity = velocity
	b.angular_velocity = Vector3.ZERO
	track_live(b)
	print("SCB launch fresh at %s v=%s" % [pos, velocity])
	return b
