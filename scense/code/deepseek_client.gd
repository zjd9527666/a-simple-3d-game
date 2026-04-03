extends Node
class_name DeepSeekClient

const DEFAULT_BASE_URL := "https://api.deepseek.com/v1/chat/completions"
const DEFAULT_MODEL := "deepseek-chat"

static func build_request_headers(api_key: String) -> PackedStringArray:
	return PackedStringArray([
		"Content-Type: application/json",
		"Authorization: Bearer %s" % api_key,
	])

static func build_chat_body(messages: Array, model: String = DEFAULT_MODEL) -> Dictionary:
	return {
		"model": model,
		"messages": messages,
		"temperature": 0.8,
		"top_p": 0.9,
		"max_tokens": 512,
	}

static func parse_chat_response(body_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(body_text)
	if typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "error": "Invalid JSON response"}
	var dict := parsed as Dictionary
	if not dict.has("choices"):
		return {"ok": false, "error": "Missing choices in response", "raw": dict}
	var choices: Variant = dict["choices"]
	if typeof(choices) != TYPE_ARRAY or choices.size() == 0:
		return {"ok": false, "error": "Empty choices in response", "raw": dict}
	var message: Variant = (choices[0] as Dictionary).get("message", {})
	var content := ""
	if typeof(message) == TYPE_DICTIONARY:
		content = str((message as Dictionary).get("content", ""))
	return {"ok": true, "content": content, "raw": dict}

