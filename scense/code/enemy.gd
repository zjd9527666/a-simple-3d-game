extends CharacterBody3D

@export var chat_ui_scene: PackedScene
@export var interact_radius: float = 3.0
@export var enemy_display_name: String = "江湖客"
@export var player_path: NodePath = NodePath("../Player")
@export var combat_manager_path: NodePath = NodePath("../CombatManager")
@export var move_speed: float = 2.8
@export var attack_range: float = 2.0
@export var attack_cooldown: float = 1.4
@export var model_facing_offset_y: float = PI
@export var idle_anim: StringName = &"Idle"
@export var run_anim: StringName = &"Running_A"
@export var attack_anim: StringName = &"1H_Melee_Attack_Chop"
@export var death_anim: StringName = &"Death_A"
@export var cheer_anim: StringName = &"Cheer"

@onready var area: Area3D = $InteractArea
@onready var animation_player: AnimationPlayer = $Player/AnimationPlayer
@onready var model: Node3D = $Player
@onready var weapon_anchor: Node3D = get_node_or_null("Player/Rig/Skeleton3D/handslot_r")
@onready var animation_tree: AnimationTree = get_node_or_null("AnimationTree")

var _ui: CanvasLayer
var _combat_manager: Node
var _player: Node
var _attack_cd := 0.0
var _is_attacking := false
var _hit_sfx: AudioStreamPlayer3D
var _result_handled := false

const MeleeHitbox := preload("res://scense/code/melee_hitbox.gd")
const SlashVFX := preload("res://scense/vfx/slash_vfx.tscn")

func _ready() -> void:
	add_to_group("enemy")
	# Enemy animations are driven by AnimationPlayer in this script.
	# Disable scene AnimationTree to avoid it overriding move/attack/death/cheer clips.
	if animation_tree:
		animation_tree.active = false

	area.body_entered.connect(_on_body_entered)
	area.body_exited.connect(_on_body_exited)
	# Ensure radius matches export for convenience
	var shape: Shape3D = $InteractArea/CollisionShape3D.shape
	if shape is SphereShape3D:
		shape.radius = interact_radius

	if chat_ui_scene:
		_ui = chat_ui_scene.instantiate()
		# Defer: current scene may still be building children in _ready().
		get_tree().current_scene.add_child.call_deferred(_ui)
		# Defer UI initialization until it's in the tree (so @onready vars are valid).
		call_deferred("_init_ui")
	
	_combat_manager = get_node_or_null(combat_manager_path)
	_player = get_node_or_null(player_path)
	animation_player.animation_finished.connect(_on_enemy_anim_finished)
	_setup_hit_sfx()
	if _combat_manager and _combat_manager.has_signal("combat_resolved"):
		_combat_manager.connect("combat_resolved", _on_combat_resolved)

func _init_ui() -> void:
	if not _ui:
		return
	if "enemy_display_name" in _ui:
		_ui.set("enemy_display_name", enemy_display_name)
	if _ui.has_method("set_player_in_range"):
		_ui.call("set_player_in_range", false)
	if _ui.has_signal("fight_requested"):
		_ui.connect("fight_requested", _on_fight_requested)

func _on_fight_requested() -> void:
	if _combat_manager and _player and _combat_manager.has_method("start_combat"):
		_result_handled = false
		_combat_manager.call("start_combat", self, _player)

func _physics_process(delta: float) -> void:
	if _attack_cd > 0.0:
		_attack_cd -= delta

	# Combat AI: chase and attack when in combat and this enemy is the active one.
	if not _combat_manager:
		return
	if not ("in_combat" in _combat_manager) or not bool(_combat_manager.get("in_combat")):
		return
	if not ("current_enemy" in _combat_manager) or _combat_manager.get("current_enemy") != self:
		return
	if not _player:
		return

	var to_player: Vector3 = _player.global_position - global_position
	var dist := to_player.length()
	if dist > 0.001:
		var planar := Vector3(to_player.x, 0.0, to_player.z).normalized()
		var target_y := atan2(planar.x, planar.z) + model_facing_offset_y
		model.global_rotation.y = lerp_angle(model.global_rotation.y, target_y, delta * 8.0)

	if dist > attack_range:
		velocity.x = (to_player.normalized().x) * move_speed
		velocity.z = (to_player.normalized().z) * move_speed
		_play_move_anim()
	else:
		velocity.x = move_toward(velocity.x, 0.0, move_speed * 2.0)
		velocity.z = move_toward(velocity.z, 0.0, move_speed * 2.0)
		_play_idle_anim()
		if _attack_cd <= 0.0:
			_do_attack()

	move_and_slide()

func _do_attack() -> void:
	_attack_cd = attack_cooldown
	_is_attacking = true
	var played := false
	# Reuse player-like attack names.
	if animation_player.has_animation(str(attack_anim)):
		animation_player.play(str(attack_anim))
		played = true
	elif animation_player.has_animation("1H_Melee_Attack_Stab"):
		animation_player.play("1H_Melee_Attack_Stab")
		played = true
	if not played:
		_is_attacking = false

	# Spawn hitbox shortly after swing starts.
	get_tree().create_timer(0.18).timeout.connect(_spawn_enemy_hitbox)

func _spawn_enemy_hitbox() -> void:
	if not _combat_manager:
		return
	if not ("in_combat" in _combat_manager) or not bool(_combat_manager.get("in_combat")):
		return
	var attack_basis := model.global_transform.basis
	var spawn_pos := global_position + (attack_basis.z * 1.1) + Vector3.UP * 1.0
	var spawn_basis := attack_basis
	if weapon_anchor:
		spawn_pos = weapon_anchor.global_position
		spawn_basis = weapon_anchor.global_basis

	_apply_enemy_melee_damage(spawn_pos, attack_basis.z)

	var vfx := SlashVFX.instantiate()
	get_tree().current_scene.add_child(vfx)
	vfx.global_position = spawn_pos
	vfx.global_basis = spawn_basis
	get_tree().create_timer(0.35).timeout.connect(vfx.queue_free)

func _apply_enemy_melee_damage(origin: Vector3, forward: Vector3) -> void:
	var players := get_tree().get_nodes_in_group("player")
	for n in players:
		if not (n is Node3D):
			continue
		var player := n as Node3D
		var to_player := player.global_position - origin
		if to_player.length() > 2.0:
			continue
		var dir := to_player.normalized()
		if forward.normalized().dot(dir) < 0.1:
			continue
		if player.has_method("take_damage"):
			player.call("take_damage", 10.0)

func take_damage(amount: float) -> void:
	if _combat_manager and _combat_manager.has_method("damage_enemy"):
		_combat_manager.call("damage_enemy", amount)
	_play_hit_sfx(220.0)

func _on_body_entered(body: Node) -> void:
	if body is CharacterBody3D:
		_set_in_range(true)

func _on_body_exited(body: Node) -> void:
	if body is CharacterBody3D:
		_set_in_range(false)

func _set_in_range(in_range: bool) -> void:
	if _ui and _ui.has_method("set_player_in_range"):
		_ui.call("set_player_in_range", in_range)

func _play_idle_anim() -> void:
	if _is_attacking:
		return
	var anim := str(idle_anim)
	if animation_player.has_animation(anim) and animation_player.current_animation != anim:
		animation_player.play(anim)

func _play_move_anim() -> void:
	if _is_attacking:
		return
	var anim := str(run_anim)
	if animation_player.has_animation(anim) and animation_player.current_animation != anim:
		animation_player.play(anim)

func _on_enemy_anim_finished(anim_name: String) -> void:
	if anim_name == str(attack_anim) or anim_name == "1H_Melee_Attack_Stab":
		_is_attacking = false

func _on_combat_resolved(result: String, enemy_node: Node) -> void:
	if enemy_node != self:
		return
	if _result_handled:
		return
	_result_handled = true

	_is_attacking = false
	velocity = Vector3.ZERO

	if result == "player_win":
		# Enemy is defeated
		if animation_player.has_animation(str(death_anim)):
			animation_player.play(str(death_anim))
		if _ui and _ui.has_method("show_battle_line"):
			_ui.call("show_battle_line", "%s：可恶……竟败在你手里……" % enemy_display_name, 3.0)
		if _player and _player.has_method("play_victory_and_recover"):
			_player.call("play_victory_and_recover")
	elif result == "enemy_win":
		# Enemy wins
		if animation_player.has_animation(str(cheer_anim)):
			animation_player.play(str(cheer_anim))
		if _ui and _ui.has_method("show_battle_line"):
			_ui.call("show_battle_line", "%s：哈哈，江湖路远，你还差得远！" % enemy_display_name, 3.0)
		await get_tree().create_timer(3.0).timeout
		get_tree().reload_current_scene()

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
		var sample := sin(TAU * freq * t) * env * 0.2
		pb.push_frame(Vector2(sample, sample))
