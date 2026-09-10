class_name SCBBall
extends RigidBody3D

## Phenolic resin tournament ball. V2 (Phase 1) sizing: 60 mm / 100 g -
## the ball is the star of the show on a phone screen; tests/test_physics.gd
## and docs/PHYSICS_SPEC.md have been updated to match.
## Free bodies that rest ON the tilted board: gravity's tangential component
## decelerates them up the 4.99-degree slope, and static friction
## (0.49 >> tan(4.99 deg) ~ 0.087) holds resting balls in place.

const RADIUS_M := 0.042
const MASS_KG := 0.010  # 10 g - scaled with the bigger 4.35 x 1.8 board
const ROLL_DAMP := 0.05  # smooth phenolic roll; resistance comes from the
# 5-degree slope's gravity component, not artificial braking


var color: String = "red"

var _mesh_instance: MeshInstance3D = null
var _mat: StandardMaterial3D = null

## Broadcast highlight: when true the ball pulses a warm emission so the
## player always knows exactly which ball is in hand.
var is_active := false:
	set(value):
		is_active = value
		_sync_emphasis()


func _ready() -> void:
	# Everything is configured in create() before entering the tree.
	# IMPORTANT: never rebuild physics properties after the body is inside the
	# physics space (Jolt re-registers the body, and if it is a hair's width
	# inside the board it tunnels straight through).
	# 8-ball-style contact audio (2026-09 live feedback: balls made no sound
	# and no contact feel). contact_monitor is already on; this translates
	# each reported contact into a synthesized clack, volume- and pitch-
	# scaled by impact speed, rate-limited so rolling chains don't machine-gun.
	body_entered.connect(_on_body_entered)


var _last_clack_ms := 0

func _on_body_entered(_body: Node) -> void:
	var now := Time.get_ticks_msec()
	if now - _last_clack_ms < 70:
		return
	_last_clack_ms = now
	var impact := linear_velocity.length()
	if impact < 0.25:
		return
	var snd := get_node_or_null("/root/Sfx")
	if snd == null:
		return
	var vol: float = clampf(-20.0 + impact * 7.0, -20.0, -1.0)
	var pitch: float = clampf(0.85 + impact * 0.09, 0.85, 1.5)
	snd.play("pop", pitch, vol)


func _process(_delta: float) -> void:
	if is_active and _mat != null:
		# v17: subtle own-colour pulse only - the old gold emission at high
		# energy washed the ball out to WHITE on the cream table (owner bug
		# report: "the starting ball is always white").
		var pulse := 0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006)
		_mat.emission_energy_multiplier = 0.25 + pulse * 0.25


func _sync_emphasis() -> void:
	if _mat == null:
		return
	if is_active:
		_mat.emission_enabled = true
		# the ball's OWN colour, gently lifted - never a white/gold wash
		_mat.emission = _mat.albedo_color
		_mat.emission_energy_multiplier = 0.35
	else:
		_mat.emission_enabled = false


func configure_material() -> void:
	# Visual mesh + the REQUIRED collision shape (a RigidBody3D has none
	# implicitly - without this the ball would fall through the table).
	var cs := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = RADIUS_M
	cs.shape = sp
	add_child(cs)

	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = RADIUS_M
	sm.height = RADIUS_M * 2.0
	sm.radial_segments = 48
	sm.rings = 24
	var mat := StandardMaterial3D.new()
	if color == "red":
		# Deep tournament crimson (the factory set's lacquered cherry red).
		mat.albedo_color = Color(0.66, 0.075, 0.045)
	else:
		# Obsidian black with a hint of blue so it reads on dark stages.
		mat.albedo_color = Color(0.035, 0.037, 0.045)
	# Show-billiard finish: near-mirror lacquer, strong clearcoat glint and a
	# rim term so the sphere silhouette always separates from the marble.
	mat.roughness = 0.07
	mat.metallic = 0.0
	mat.clearcoat = 0.9
	mat.clearcoat_roughness = 0.06
	mat.rim_enabled = true
	mat.rim = 0.45
	mat.rim_tint = 0.25
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mesh.mesh = sm
	mesh.material_override = mat
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(mesh)
	_mesh_instance = mesh
	_mat = mat
	_sync_emphasis()


func set_mass_properties() -> void:
	mass = MASS_KG
	collision_layer = 2
	collision_mask = 3
	contact_monitor = true
	max_contacts_reported = 8
	# CCD is DISABLED: with the 60 Hz fixed step our max shot (3.4 m/s) moves
	# only 5.7 cm per frame - far below the 2.2 m board.
	continuous_cd = false
	angular_damp = ROLL_DAMP
	linear_damp = 0.10
	# Godot 4: bounce/friction live on a PhysicsMaterial, not the body.
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.30
	pm.friction = 0.49
	physics_material_override = pm


static func create(color_name: String) -> SCBBall:
	var b := SCBBall.new()
	b.color = color_name
	b.configure_material()    # shape + visuals BEFORE tree entry
	b.set_mass_properties()   # all physics properties BEFORE tree entry
	return b