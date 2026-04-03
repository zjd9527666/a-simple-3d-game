extends Area3D

@export var damage: float = 10.0
@export var lifetime: float = 0.12
@export var target_group: StringName = &"enemy"

var _already_hit := {}

func _ready() -> void:
	monitoring = true
	monitorable = true
	body_entered.connect(_on_body_entered)
	# auto free
	get_tree().create_timer(lifetime).timeout.connect(queue_free)

func _on_body_entered(body: Node) -> void:
	if not body:
		return
	if not body.is_in_group(target_group):
		return
	var id := body.get_instance_id()
	if _already_hit.has(id):
		return
	_already_hit[id] = true

	# Apply damage if the body exposes a take_damage(amount) method.
	if body.has_method("take_damage"):
		body.call("take_damage", damage)
