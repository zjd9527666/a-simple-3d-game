extends CharacterBody3D

@export var SPEED :float = 5.0
@export var JUMP_VELOCITY :float = 4.5
@export var camera:Camera3D
@export var model:Node3D
@export var combat_manager_path: NodePath = NodePath("../CombatManager")

@onready var animation_tree = $Player/AnimationTree
@onready var animation_player = $Player/AnimationPlayer
@onready var weapon_anchor: Node3D = get_node_or_null("Player/Rig/Skeleton3D/handslot_r")
const MeleeHitbox := preload("res://scense/code/melee_hitbox.gd")
const SlashVFX := preload("res://scense/vfx/slash_vfx.tscn")
var _hit_sfx: AudioStreamPlayer3D
var _controls_enabled := true
# 连击相关变量
var combo_count := 0          # 0=未攻击, 1=第一击, 2=第二击, 3=第三击
var can_combo := false        # 是否处于连击窗口内（动画结束后的一小段时间）
var combo_timer: Timer

var target_angle: float = PI

func _ready():
	add_to_group("player")
	animation_player.animation_finished.connect(_on_animation_finished)
	animation_tree.active = true
	_setup_hit_sfx()
	
	# 创建连击计时器
	combo_timer = Timer.new()
	combo_timer.one_shot = true
	combo_timer.timeout.connect(_on_combo_timeout)
	add_child(combo_timer)


func _process(delta: float) -> void:
	if not _controls_enabled:
		return
	#var playback = $Player/AnimationTree.get("parameters/playback")
	#print(playback.get_current_node())
	var camera_angle=camera.global_rotation.y
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var input_angle=atan2(input_dir.x, input_dir.y)
	if input_dir != Vector2.ZERO:
		target_angle=camera_angle+input_angle
	model.global_rotation.y=lerp_angle(model.global_rotation.y,target_angle,delta*15)

func _physics_process(delta: float) -> void:
	if not _controls_enabled:
		velocity.x = move_toward(velocity.x, 0.0, SPEED * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, SPEED * 2.0)
		move_and_slide()
		return
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * delta

	# Handle jump.
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var input_dir := Input.get_vector("left", "right", "up", "down")
	var direction := (transform.basis * Vector3(input_dir.x, 0, input_dir.y)).normalized()
	direction=direction.rotated(Vector3.UP,camera.global_rotation.y)
	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
	
func _input(event):
	if not _controls_enabled:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		attempt_attack()

func attempt_attack():
	# 条件：未攻击（combo_count == 0）或者处于连击窗口内（can_combo == true）
	if combo_count == 0 or can_combo:
		combo_count += 1
		
		# 根据连击数选择对应的攻击动画名
		var attack_state = get_attack_state_name(combo_count)
		# 攻击期间先暂停 AnimationTree，由 AnimationPlayer 直接驱动攻击动画
		animation_tree.active = false
		animation_player.play(attack_state)
		_spawn_player_hitbox()
		
		# 关闭连击窗口（动画播放期间不接受新输入）
		can_combo = false
		# 停止之前的计时器
		combo_timer.stop()

func get_attack_state_name(count: int) -> String:
	match count:
		1:
			return "1H_Melee_Attack_Chop"
		2:
			return "1H_Melee_Attack_Slice_Diagonal"
		3:
			return "1H_Melee_Attack_Slice_Horizontal"
		4:
			return "1H_Melee_Attack_Stab"
		_:
			return "1H_Melee_Attack_Chop"

func _on_animation_finished(anim_name: String):
	# 检查刚结束的动画是否是三个攻击动画之一
	var attack_anims := [
		"1H_Melee_Attack_Chop",
		"1H_Melee_Attack_Slice_Diagonal",
		"1H_Melee_Attack_Slice_Horizontal",
		"1H_Melee_Attack_Stab",
	]
	if anim_name in attack_anims:
		if combo_count < 4:
			# 动画结束，开启连击窗口
			can_combo = true
			combo_timer.start(0.4)   # 连击窗口时长（秒），可根据手感调整
		else:
			# 三连击完成，直接重置
			reset_combo()
		
		# 攻击结束，重新启用 AnimationTree，让状态机根据速度/落地状态切回 Idle / Run 等
		animation_tree.active = true
	# 如果还有其他非攻击动画结束，可以忽略

func _on_combo_timeout():
	# 连击窗口超时，重置连击
	reset_combo()

func reset_combo():
	combo_count = 0
	can_combo = false
	combo_timer.stop()

func _spawn_player_hitbox() -> void:
	var attack_basis := model.global_transform.basis
	var spawn_pos := global_position + (attack_basis.z * 1.2) + Vector3.UP * 1.0
	var spawn_basis := attack_basis
	if weapon_anchor:
		spawn_pos = weapon_anchor.global_position
		spawn_basis = weapon_anchor.global_basis

	# Reliable damage: direct range + facing check at swing time.
	_apply_player_melee_damage(spawn_pos, attack_basis.z)

	# VFX
	var vfx := SlashVFX.instantiate()
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = spawn_pos
	vfx.global_basis = spawn_basis
	get_tree().create_timer(0.35).timeout.connect(vfx.queue_free)

func _apply_player_melee_damage(origin: Vector3, forward: Vector3) -> void:
	var enemies := get_tree().get_nodes_in_group("enemy")
	for n in enemies:
		if not (n is Node3D):
			continue
		var enemy := n as Node3D
		var to_enemy := enemy.global_position - origin
		if to_enemy.length() > 2.0:
			continue
		var dir := to_enemy.normalized()
		if forward.normalized().dot(dir) < 0.1:
			continue
		if enemy.has_method("take_damage"):
			enemy.call("take_damage", 12.0)

func take_damage(amount: float) -> void:
	var mgr := get_node_or_null(combat_manager_path)
	if mgr and mgr.has_method("damage_player"):
		mgr.call("damage_player", amount)
	_play_hit_sfx(180.0)

func _setup_hit_sfx() -> void:
	_hit_sfx = AudioStreamPlayer3D.new()
	_hit_sfx.unit_size = 5.0
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = 44100.0
	gen.buffer_length = 0.2
	_hit_sfx.stream = gen
	add_child(_hit_sfx)

func _play_hit_sfx(freq: float) -> void:
	if not _hit_sfx:
		return
	_hit_sfx.play()
	var pb := _hit_sfx.get_stream_playback() as AudioStreamGeneratorPlayback
	if not pb:
		return
	var mix_rate := 44100.0
	var len_sec := 0.08
	var frames := int(len_sec * mix_rate)
	for i in frames:
		var t := float(i) / mix_rate
		var env := 1.0 - (t / len_sec)
		var sample := sin(TAU * freq * t) * env * 0.22
		pb.push_frame(Vector2(sample, sample))

func play_victory_and_recover() -> void:
	# Victory flourish, then recover to full HP.
	var mgr := get_node_or_null(combat_manager_path)
	set_control_enabled(false)

	if animation_player.has_animation("Cheer"):
		animation_tree.active = false
		animation_player.play("Cheer")
		await animation_player.animation_finished
		animation_tree.active = true

	if mgr and mgr.has_method("restore_player_full_hp"):
		mgr.call("restore_player_full_hp")

	set_control_enabled(true)

func set_control_enabled(enabled: bool) -> void:
	_controls_enabled = enabled

func is_control_enabled() -> bool:
	return _controls_enabled
