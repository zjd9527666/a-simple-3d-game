extends Area3D

enum CollectibleType {DIAMOND, COIN, CHERRY}
@export var type: CollectibleType

@export var Dimaond_model:PackedScene
@export var Coin_model:PackedScene
@export var Cherry_model:PackedScene

@export var rotation_speed: float=0.5
@export var floating_speed: float=0.01
@export var floating_magnitude: float=0.05
var original_y:float

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	original_y=position.y # Replace with function body.
	@warning_ignore("int_as_enum_without_cast")
	type=randi_range(0,2)
	var model:PackedScene
	match type:
		CollectibleType.DIAMOND:
			model=Dimaond_model
			print('dimaond')
		CollectibleType.COIN:
			model=Coin_model
			print('coin')
		CollectibleType.CHERRY:
			model=Cherry_model
			print('cherry')
	var node=model.instantiate()
	add_child(node)

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	rotation.y += rotation_speed * delta
	position.y = original_y + sin(Time.get_ticks_msec()*floating_speed)*floating_magnitude


func _on_body_entered(body: Node3D) -> void:
	if body is CharacterBody3D:
		queue_free()
		GameManager.instance.collect_item(type)
