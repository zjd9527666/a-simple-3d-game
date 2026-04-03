extends CanvasLayer

@onready var player_bar: ProgressBar = $Root/PlayerBar
@onready var enemy_bar: ProgressBar = $Root/EnemyBar
@onready var enemy_name: Label = $Root/EnemyName

var _pending_player_current: float = -1.0
var _pending_player_max: float = -1.0
var _pending_enemy_current: float = -1.0
var _pending_enemy_max: float = -1.0

func _ready() -> void:
	# Pull initial state in case CombatManager emitted before this UI became ready.
	var mgr := get_node_or_null("../CombatManager")
	if mgr:
		if "player_hp" in mgr and "player_max_hp" in mgr:
			set_player_hp(float(mgr.get("player_hp")), float(mgr.get("player_max_hp")))
		if "in_combat" in mgr and bool(mgr.get("in_combat")):
			set_enemy_visible(true)
			if "enemy_hp" in mgr and "enemy_max_hp" in mgr:
				set_enemy_hp(float(mgr.get("enemy_hp")), float(mgr.get("enemy_max_hp")))
		else:
			set_enemy_visible(false)

	# Apply any pending values queued before @onready nodes were valid.
	if _pending_player_max > 0.0:
		player_bar.max_value = _pending_player_max
		player_bar.value = clampf(_pending_player_current, 0.0, _pending_player_max)
	if _pending_enemy_max > 0.0:
		enemy_bar.max_value = _pending_enemy_max
		enemy_bar.value = clampf(_pending_enemy_current, 0.0, _pending_enemy_max)

func set_player_hp(current: float, max_hp: float) -> void:
	if not is_node_ready() or not player_bar:
		_pending_player_current = current
		_pending_player_max = max_hp
		return
	player_bar.max_value = max_hp
	player_bar.value = clampf(current, 0.0, max_hp)

func _on_combat_started(enemy: Node) -> void:
	set_enemy_visible(true)
	set_enemy_name(enemy.get("enemy_display_name") if "enemy_display_name" in enemy else "敌人")

func _on_combat_ended() -> void:
	set_enemy_visible(false)

func set_enemy_visible(should_show: bool) -> void:
	if enemy_bar:
		enemy_bar.visible = should_show
	if enemy_name:
		enemy_name.visible = should_show

func set_enemy_name(display_name: String) -> void:
	if not is_node_ready() or not enemy_name:
		return
	enemy_name.text = display_name

func set_enemy_hp(current: float, max_hp: float) -> void:
	if not is_node_ready() or not enemy_bar:
		_pending_enemy_current = current
		_pending_enemy_max = max_hp
		return
	enemy_bar.max_value = max_hp
	enemy_bar.value = clampf(current, 0.0, max_hp)
