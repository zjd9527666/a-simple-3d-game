extends Node3D

@export var duration: float = 0.18

@onready var arc: MeshInstance3D = $Arc
@onready var particles: GPUParticles3D = $GPUParticles3D

func _ready() -> void:
	# Make arc material instance-local so alpha tween only affects this instance.
	var base_mat := arc.get_active_material(0)
	if base_mat and base_mat is StandardMaterial3D:
		var m := (base_mat as StandardMaterial3D).duplicate()
		arc.set_surface_override_material(0, m)

	arc.scale = Vector3(0.65, 0.65, 0.65)
	arc.rotation_degrees = Vector3(-8, -70, 0)

	var t := create_tween()
	t.tween_property(arc, "rotation_degrees:y", 75.0, duration) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(arc, "scale", Vector3(1.25, 1.0, 1.25), duration) \
		.set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_OUT)
	t.parallel().tween_method(_set_arc_alpha, 1.0, 0.0, duration)
	t.finished.connect(queue_free)

func _set_arc_alpha(a: float) -> void:
	var mat := arc.get_active_material(0)
	if mat and mat is StandardMaterial3D:
		var m := mat as StandardMaterial3D
		var c := m.albedo_color
		c.a = clampf(a, 0.0, 1.0)
		m.albedo_color = c
