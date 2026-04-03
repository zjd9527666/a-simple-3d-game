extends SpringArm3D
@export var event_delta:float=0.01

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass
func _input(event:InputEvent)->void:
	var p := get_parent()
	if p and p.has_method("is_control_enabled") and not p.call("is_control_enabled"):
		return

	if event is InputEventMouseMotion:
		var mouse_delta=event.relative
		rotation.y -= mouse_delta.x * event_delta
		rotation.x -= mouse_delta.y * event_delta
		rotation.x=clamp(rotation.x,-PI/2,PI/4)

	if event is InputEventKey:
		if event.keycode==KEY_TAB and event.pressed:
			if Input.mouse_mode== Input.MOUSE_MODE_CAPTURED:
				Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
