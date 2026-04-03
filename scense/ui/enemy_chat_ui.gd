extends CanvasLayer

signal fight_requested

@export var api_key: String = "sk-df885ddf9f794638bda3170e96d896e3" # placeholder; user will replace
const DeepSeek := preload("res://scense/code/deepseek_client.gd")
@export var deepseek_url: String = DeepSeek.DEFAULT_BASE_URL
@export var deepseek_model: String = DeepSeek.DEFAULT_MODEL

@export var enemy_display_name: String = "来者"

@onready var root: Control = $Root
@onready var prompt: Label = $Root/Prompt
@onready var panel: PanelContainer = $Root/Panel
@onready var battle_panel: PanelContainer = $Root/BattlePanel
@onready var battle_text: Label = $Root/BattlePanel/BattleText
@onready var history: RichTextLabel = $Root/Panel/VBox/History
@onready var input: LineEdit = $Root/Panel/VBox/InputRow/Input
@onready var send_btn: Button = $Root/Panel/VBox/InputRow/Send
@onready var http: HTTPRequest = $Root/Panel/VBox/Http

var _player_in_range := false
var _chat_open := false
var _messages: Array = []
var _typing_timer: SceneTreeTimer
var _typing_target_text := ""
var _typing_index := 0

func _ready() -> void:
	panel.visible = false
	prompt.visible = false
	battle_panel.visible = false
	send_btn.pressed.connect(_on_send_pressed)
	input.text_submitted.connect(_on_text_submitted)
	http.request_completed.connect(_on_request_completed)

	_messages = [
		{
			"role": "system",
			"content": "你是一个脾气暴躁的江湖中人，与玩家对话。语言风格参考《逆水寒》：克制、古风、带江湖气与余味；不要现代网络口吻。回答要自然、有情绪留白。"
		}
	]

func set_player_in_range(in_range: bool) -> void:
	_player_in_range = in_range
	# When called before this UI enters the scene tree, @onready vars are still Nil.
	if not is_node_ready():
		return
	if not _chat_open:
		prompt.visible = in_range

func open_chat() -> void:
	if _chat_open:
		return
	_chat_open = true
	panel.visible = true
	battle_panel.visible = false
	prompt.visible = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	input.editable = true
	input.grab_focus()
	_set_player_control(false)

func close_chat() -> void:
	if not _chat_open:
		return
	_chat_open = false
	panel.visible = false
	battle_panel.visible = false
	prompt.visible = _player_in_range
	input.release_focus()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_set_player_control(true)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("chat_close") and _chat_open:
		close_chat()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("interact") and _player_in_range and not _chat_open:
		open_chat()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("chat_send") and _chat_open:
		_on_send_pressed()
		get_viewport().set_input_as_handled()

func _on_text_submitted(_text: String) -> void:
	_on_send_pressed()

func _on_send_pressed() -> void:
	if not _chat_open:
		return
	var text := input.text.strip_edges()
	if text.is_empty():
		return
	input.text = ""
	_append_user(text)
	if await _should_trigger_fight(text):
		_start_battle_sequence()
		return
	_request_ai_reply(text)

func _append_user(text: String) -> void:
	history.append_text("\n[color=sky_blue]你[/color]：%s\n" % _escape_bbcode(text))
	_messages.append({"role": "user", "content": text})

func _append_enemy_typing_begin() -> void:
	history.append_text("\n[color=gold]%s[/color]：" % enemy_display_name)

func _append_enemy_typed_chunk(chunk: String) -> void:
	history.append_text(chunk)

func _append_enemy_done() -> void:
	history.append_text("\n")

func _request_ai_reply(_user_text: String) -> void:
	_append_enemy_typing_begin()

	var body: Dictionary = DeepSeek.build_chat_body(_messages, deepseek_model)
	var json_text: String = JSON.stringify(body)
	var headers: PackedStringArray = DeepSeek.build_request_headers(api_key)

	var err := http.request(deepseek_url, headers, HTTPClient.METHOD_POST, json_text)
	if err != OK:
		_append_enemy_typed_chunk("[color=tomato]（气息一滞：无法发出传书。）[/color]")
		_append_enemy_done()

func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	var body_text := body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		_append_enemy_typed_chunk("[color=tomato]（对方沉默片刻：江湖路远，消息未达。）[/color]")
		_append_enemy_done()
		return

	var parsed: Dictionary = DeepSeek.parse_chat_response(body_text)
	if not parsed.get("ok", false):
		_append_enemy_typed_chunk("[color=tomato]（答复晦涩，听不真切。）[/color]")
		_append_enemy_done()
		return

	var reply := str(parsed.get("content", "")).strip_edges()
	if reply.is_empty():
		reply = "……"

	_messages.append({"role": "assistant", "content": reply})
	_start_typing(reply)

func _start_typing(text: String) -> void:
	_typing_target_text = _escape_bbcode(text)
	_typing_index = 0
	_tick_typing()

func _tick_typing() -> void:
	# typing effect: add a few chars per tick
	var step: int = 3
	var next_i: int = mini(_typing_target_text.length(), _typing_index + step)
	if next_i > _typing_index:
		_append_enemy_typed_chunk(_typing_target_text.substr(_typing_index, next_i - _typing_index))
		_typing_index = next_i

	if _typing_index >= _typing_target_text.length():
		_append_enemy_done()
		return

	_typing_timer = get_tree().create_timer(0.02)
	_typing_timer.timeout.connect(_tick_typing)

static func _escape_bbcode(text: String) -> String:
	return text.replace("[", "\\[").replace("]", "\\]")

func _should_trigger_fight(text: String) -> bool:
	# Keep existing keyword trigger first.
	var t := text
	if t.find("打架") != -1 or t.find("切磋") != -1 or t.find("决斗") != -1 or t.find("比试") != -1:
		return true
	# AI-based intent trigger.
	return await _ai_should_start_fight(t)

func _ai_should_start_fight(user_text: String) -> bool:
	var judge_req := HTTPRequest.new()
	add_child(judge_req)

	var judge_messages := [
		{
			"role": "system",
			"content": "你是一个意图分类器。只判断玩家语句是否表达强烈战斗欲望（例如挑战、挑衅、求战）。仅回答 YES 或 NO。"
		},
		{
			"role": "user",
			"content": user_text
		}
	]
	var body: Dictionary = DeepSeek.build_chat_body(judge_messages, deepseek_model)
	var json_text: String = JSON.stringify(body)
	var headers: PackedStringArray = DeepSeek.build_request_headers(api_key)

	var err := judge_req.request(deepseek_url, headers, HTTPClient.METHOD_POST, json_text)
	if err != OK:
		judge_req.queue_free()
		return false

	var result_data: Array = await judge_req.request_completed
	judge_req.queue_free()
	if result_data.size() < 4:
		return false
	var result: int = int(result_data[0] as int)
	var response_code: int = int(result_data[1] as int)
	var packed: PackedByteArray = result_data[3] as PackedByteArray
	if result != HTTPRequest.RESULT_SUCCESS or response_code < 200 or response_code >= 300:
		return false

	var body_text := packed.get_string_from_utf8()
	var parsed: Dictionary = DeepSeek.parse_chat_response(body_text)
	if not parsed.get("ok", false):
		return false
	var reply := str(parsed.get("content", "")).strip_edges().to_upper()
	if reply.find("YES") != -1:
		return true
	# Tolerate Chinese outputs from model.
	if reply.find("是") != -1 and reply.find("否") == -1:
		return true
	return false

func _start_battle_sequence() -> void:
	# Exit chat first, then show enemy line for 3 seconds.
	close_chat()
	battle_text.text = "%s：哈哈哈，来战！" % enemy_display_name
	battle_panel.visible = true
	await get_tree().create_timer(3.0).timeout
	battle_panel.visible = false
	emit_signal("fight_requested")

func _set_player_control(enabled: bool) -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player and player.has_method("set_control_enabled"):
		player.call("set_control_enabled", enabled)

func show_battle_line(text: String, duration: float = 3.0) -> void:
	battle_text.text = text
	battle_panel.visible = true
	await get_tree().create_timer(duration).timeout
	if battle_text.text == text:
		battle_panel.visible = false
