extends RefCounted

# Key and button rebinding, saved to disk.
#
# The actions listed here are the ones a player would expect to change. Anything not in
# this list is left alone, so a missing action cannot break the game: it is skipped.
#
# Deliberately NOT a `class_name`, for the same reason as SessionMode: that registers a
# global through the editor's class cache and a command-line run before the cache knows
# about it fails to parse. Callers preload this file.
#
# A binding is stored as a plain dictionary rather than as an object, because it has to
# survive JSON. Keys: kind (key, joy_button, joy_axis), plus code, or axis and sign.

const PATH: String = "user://bindings.json"
const VERSION: int = 1

static var path: String = PATH

const ACTIONS: Array[String] = [
	"move_forward", "move_backward", "move_left", "move_right",
	"sprint", "jump", "interact",
	"tool_1", "tool_2", "tool_3",
]

## The bindings the game shipped with, captured once at start-up so Reset is real.
static var _defaults: Dictionary = {}
static var _captured: bool = false

## Human-readable action names for the screen.
static func action_label(action: String) -> String:
	var key := "ACTION_" + action.to_upper()
	var text := TranslationServer.translate(key)
	if text != key:
		return text
	var words := action.replace("_", " ")
	return words.substr(0, 1).to_upper() + words.substr(1)

## Remembers the bindings in force right now. Called before anything is changed.
static func capture_defaults() -> void:
	if _captured:
		return
	_captured = true
	_defaults = to_dictionary()

## Every binding of the actions we manage, in a form JSON can hold.
static func to_dictionary() -> Dictionary:
	var out := {"version": VERSION, "actions": {}}
	for action in ACTIONS:
		if not InputMap.has_action(action):
			continue
		var events: Array = []
		for event in InputMap.action_get_events(action):
			var entry := describe_event(event)
			if not entry.is_empty():
				events.append(entry)
		out["actions"][action] = events
	return out

static func describe_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var k := event as InputEventKey
		# A binding defined by physical position (which is how this project ships them)
		# cannot be rebuilt from a logical keycode. Refusing to describe it means it is
		# never written to the file, so load can never overwrite it with a blank key.
		if k.keycode == 0:
			return {}
		return {"kind": "key", "code": int(k.keycode)}
	if event is InputEventJoypadButton:
		return {"kind": "joy_button", "code": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return {"kind": "joy_axis", "axis": int(motion.axis), "sign": 1 if motion.axis_value >= 0.0 else -1}
	if event is InputEventMouseButton:
		return {"kind": "mouse_button", "code": int((event as InputEventMouseButton).button_index)}
	return {}

static func build_event(entry: Dictionary) -> InputEvent:
	match String(entry.get("kind", "")):
		"key":
			var key := InputEventKey.new()
			key.keycode = int(entry.get("code", 0)) as Key
			return key
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(entry.get("code", 0)) as JoyButton
			return button
		"joy_axis":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(entry.get("axis", 0)) as JoyAxis
			motion.axis_value = float(entry.get("sign", 1))
			return motion
		"mouse_button":
			var mouse_button := InputEventMouseButton.new()
			mouse_button.button_index = int(entry.get("code", 0)) as MouseButton
			return mouse_button
	return null

## A short label for a screen: "Space", "Pad A", "Pad stick".
static func event_label(event: InputEvent) -> String:
	if event is InputEventKey:
		var k := event as InputEventKey
		var code := k.keycode if k.keycode != 0 else k.physical_keycode
		return OS.get_keycode_string(code)
	if event is InputEventJoypadButton:
		return "Pad %d" % int((event as InputEventJoypadButton).button_index)
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		return "Stick %d%s" % [int(motion.axis), "+" if motion.axis_value >= 0.0 else "-"]
	if event is InputEventMouseButton:
		return "Mouse %d" % int((event as InputEventMouseButton).button_index)
	return "?"

static func binding_label(action: String) -> String:
	if not InputMap.has_action(action):
		return "not in this build"
	var parts: Array[String] = []
	for event in InputMap.action_get_events(action):
		parts.append(event_label(event))
	return ", ".join(parts) if not parts.is_empty() else "unbound"

## Rebinds an action to a single event, and removes that event from any other action so
## two actions can never answer to the same key.
static func rebind(action: String, event: InputEvent) -> bool:
	if not InputMap.has_action(action) or event == null:
		return false
	if event is InputEventKey and (event as InputEventKey).keycode == KEY_ESCAPE:
		# Escape is how the menu closes. Taking it would trap the player in the screen.
		return false
	for other in ACTIONS:
		if other == action or not InputMap.has_action(other):
			continue
		if InputMap.action_has_event(other, event):
			InputMap.action_erase_event(other, event)
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, event)
	save()
	return true

static func reset_to_defaults() -> void:
	if _defaults.is_empty():
		return
	apply_dictionary(_defaults)
	save()

static func apply_dictionary(data: Dictionary) -> void:
	var actions: Dictionary = data.get("actions", {})
	for action in actions.keys():
		var name := String(action)
		if not InputMap.has_action(name):
			continue
		var entries: Array = actions[action]
		if entries.is_empty():
			continue
		InputMap.action_erase_events(name)
		for entry in entries:
			var event := build_event(entry)
			if event != null:
				InputMap.action_add_event(name, event)

static func save() -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Bindings: could not write %s" % path)
		return false
	file.store_string(JSON.stringify(to_dictionary(), "\t"))
	file.close()
	return true

static func load_from_disk() -> bool:
	if not FileAccess.file_exists(path):
		return false
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("Bindings: %s is not readable, keeping the current controls" % path)
		return false
	apply_dictionary(parsed)
	return true
