extends Node
class_name CombatManager

signal combat_started(enemy: Node)
signal combat_ended()
signal combat_resolved(result: String, enemy: Node)
signal player_hp_changed(current: float, max_hp: float)
signal enemy_hp_changed(current: float, max_hp: float)

@export var player_max_hp: float = 100.0
@export var enemy_max_hp: float = 100.0

var player_hp: float = 100.0
var enemy_hp: float = 100.0

var in_combat := false
var current_enemy: Node
var player: Node

func _ready() -> void:
	player_hp = player_max_hp
	enemy_hp = enemy_max_hp
	emit_signal("player_hp_changed", player_hp, player_max_hp)

func start_combat(enemy: Node, player_node: Node) -> void:
	if in_combat:
		return
	in_combat = true
	current_enemy = enemy
	player = player_node
	enemy_hp = enemy_max_hp
	emit_signal("enemy_hp_changed", enemy_hp, enemy_max_hp)
	emit_signal("combat_started", enemy)

func end_combat() -> void:
	if not in_combat:
		return
	in_combat = false
	current_enemy = null
	player = null
	emit_signal("combat_ended")

func damage_player(amount: float) -> void:
	if not in_combat:
		return
	player_hp = maxf(0.0, player_hp - amount)
	emit_signal("player_hp_changed", player_hp, player_max_hp)
	if player_hp <= 0.0:
		emit_signal("combat_resolved", "enemy_win", current_enemy)
		end_combat()

func damage_enemy(amount: float) -> void:
	if not in_combat:
		return
	enemy_hp = maxf(0.0, enemy_hp - amount)
	emit_signal("enemy_hp_changed", enemy_hp, enemy_max_hp)
	if enemy_hp <= 0.0:
		emit_signal("combat_resolved", "player_win", current_enemy)
		end_combat()

func restore_player_full_hp() -> void:
	player_hp = player_max_hp
	emit_signal("player_hp_changed", player_hp, player_max_hp)
