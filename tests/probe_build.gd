extends SceneTree
func _initialize() -> void:
print("PROBE: creating world")
var w: TableWorld = load("res://scripts/game/table_world.gd").new()
root.add_child(w)
print("PROBE: world built, slots=%d" % w.slots.size())
for i in 30:
await physics_frame
print("PROBE: 30 physics frames ok")
quit(0)
