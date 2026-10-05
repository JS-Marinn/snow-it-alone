extends Control

# Main menu: Continue, New Game and three save slots.
#
# The layout is built in code on purpose: the menu is mostly data-driven rows and
# keeping it here avoids a scene file that has to be kept in sync with the slots.

const LEVEL_SCENE: String = "res://scenes/main.tscn"
const GAME_NAME: String = "SNOW IT TOGETHER"
const GAME_SUBTITLE: String = "Snow clearing crew - prototype"
const HINT_TEXT: String = "W A S D move - Left click push/cut - Right click dump/throw - E interact - H help"

var _slot_buttons: Array[Button] = []
var _continue_button: Button
var _new_button: Button
var _delete_button: Button
var _status: Label
var _selected_slot: int = 0
var _confirm_overwrite: bool = false
var _confirm_timer: float = 0.0

func _ready() -> void:
	# Diagnostics never go through the menu, they boot straight into the level. The
	# Playground has a scene of its own, so it is the one flag that goes elsewhere.
	var playground_flags := ["--playground", "--playground-check"]
	for flag in playground_flags:
		if OS.get_cmdline_user_args().has(flag):
			# Deferred: swapping the scene from inside _ready() while the menu is still
			# adding its own children is what makes Godot complain about a busy parent.
			get_tree().call_deferred("change_scene_to_file", "res://scenes/playground.tscn")
			return
	var demo_flags := [
		"--phys-demo", "--carve-quality", "--ball-shape", "--movement-lab",
		"--impact-lab", "--plow-demo", "--save-roundtrip",
	]
	for flag in demo_flags:
		if OS.get_cmdline_user_args().has(flag):
			if flag == "--save-roundtrip":
				_run_save_battery()
				return
			_start_level()
			return

	_build_ui()
	_refresh_slots()
	# Start with the most recent slot selected so Continue is one press away.
	var latest := SaveSystem.latest_slot()
	_select_slot(latest if latest >= 0 else 0)
	if _slot_buttons.size() > 0:
		_slot_buttons[_selected_slot].grab_focus()

	# UI smoke test: render one frame, save it and exit.
	if OS.get_cmdline_user_args().has("--menu-shot"):
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_viewport().get_texture().get_image()
		if img:
			img.save_png("res://main_menu.png")
			print("[Menu] screenshot saved (size=%s)" % str(img.get_size()))
		get_tree().quit()

func _process(delta: float) -> void:
	if _confirm_overwrite:
		_confirm_timer -= delta
		if _confirm_timer <= 0.0:
			_confirm_overwrite = false
			_new_button.text = "New Game"

func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.12, 0.18)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size = Vector2(560.0, 0.0)
	center.add_child(column)

	var title := Label.new()
	title.text = GAME_NAME
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 44)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = GAME_SUBTITLE
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(0.75, 0.82, 0.92)
	column.add_child(subtitle)

	column.add_child(_spacer(18.0))

	var slots_label := Label.new()
	slots_label.text = "Save slots"
	column.add_child(slots_label)

	for slot in range(SaveSystem.SLOT_COUNT):
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		column.add_child(button)
		_slot_buttons.append(button)

	column.add_child(_spacer(14.0))

	_continue_button = Button.new()
	_continue_button.text = "Continue"
	_continue_button.custom_minimum_size = Vector2(0.0, 46.0)
	_continue_button.pressed.connect(_on_continue)
	column.add_child(_continue_button)

	_new_button = Button.new()
	_new_button.text = "New Game"
	_new_button.custom_minimum_size = Vector2(0.0, 46.0)
	_new_button.pressed.connect(_on_new_game)
	column.add_child(_new_button)

	_delete_button = Button.new()
	_delete_button.text = "Delete Slot"
	_delete_button.custom_minimum_size = Vector2(0.0, 46.0)
	_delete_button.pressed.connect(_on_delete)
	column.add_child(_delete_button)

	var quit_button := Button.new()
	quit_button.text = "Quit"
	quit_button.custom_minimum_size = Vector2(0.0, 46.0)
	quit_button.pressed.connect(func(): get_tree().quit())
	column.add_child(quit_button)

	# Development builds only. The Playground is a measuring bench, not content, so it
	# must never sit in front of a player: Continue and New Game always open the level.
	# Debug-only keeps it one click away while developing without shipping it.
	if OS.is_debug_build():
		column.add_child(_spacer(10.0))
		var dev_button := Button.new()
		dev_button.text = "Playground (dev)"
		dev_button.custom_minimum_size = Vector2(0.0, 38.0)
		dev_button.tooltip_text = "Measuring bench: 40 m runway, four surfaces, dummies. Not part of the game."
		dev_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/playground.tscn"))
		column.add_child(dev_button)

	column.add_child(_spacer(18.0))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.85, 0.9, 0.98)
	column.add_child(_status)

	var hint := Label.new()
	hint.text = HINT_TEXT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", 12)
	hint.modulate = Color(0.6, 0.68, 0.78)
	column.add_child(hint)

func _spacer(height: float) -> Control:
	var node := Control.new()
	node.custom_minimum_size = Vector2(0.0, height)
	return node

func _refresh_slots() -> void:
	for slot in range(_slot_buttons.size()):
		_slot_buttons[slot].text = SaveSystem.slot_label(slot)
	var any := SaveSystem.has_any_slot()
	_continue_button.disabled = not any
	_delete_button.disabled = not SaveSystem.slot_exists(_selected_slot)

func _select_slot(slot: int) -> void:
	_selected_slot = clampi(slot, 0, SaveSystem.SLOT_COUNT - 1)
	_confirm_overwrite = false
	_new_button.text = "New Game"
	_refresh_slots()

func _on_slot_pressed(slot: int) -> void:
	_select_slot(slot)

func _on_continue() -> void:
	var slot := _selected_slot
	if not SaveSystem.slot_exists(slot):
		slot = SaveSystem.latest_slot()
	if slot < 0 or not SaveSystem.load_slot(slot):
		_status.text = "That slot could not be read."
		_refresh_slots()
		return
	_start_level()

func _on_new_game() -> void:
	if SaveSystem.slot_exists(_selected_slot) and not _confirm_overwrite:
		# Two-step confirm so a stray click does not wipe a run.
		_confirm_overwrite = true
		_confirm_timer = 3.0
		_new_button.text = "Overwrite slot %d?" % (_selected_slot + 1)
		return
	SaveSystem.new_game(_selected_slot)
	_start_level()

func _on_delete() -> void:
	if not SaveSystem.slot_exists(_selected_slot):
		return
	SaveSystem.delete_slot(_selected_slot)
	_status.text = "Slot %d deleted." % (_selected_slot + 1)
	_refresh_slots()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_tree().quit()

func _start_level() -> void:
	get_tree().change_scene_to_file(LEVEL_SCENE)

func _run_save_battery() -> void:
	var battery := Node.new()
	battery.set_script(load("res://scripts/save_roundtrip_demo.gd"))
	battery.name = "SaveRoundtripDemo"
	add_child(battery)
