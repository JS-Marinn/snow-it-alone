extends Control

# Main menu: Continue, New Game and three save slots.
#
# The layout is built in code on purpose: the menu is mostly data-driven rows and
# keeping it here avoids a scene file that has to be kept in sync with the slots.

const LEVEL_SCENE: String = "res://scenes/main.tscn"
const LocalizationManagerScript = preload("res://scripts/localization_manager.gd")
const SettingsSystemScript = preload("res://scripts/settings_system.gd")
const InputBindingsScript = preload("res://scripts/input_bindings.gd")

static func _cleanup_scratch_files() -> void:
	for f in ["user://scratch_settings.json", "user://scratch_bindings.json"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
			DirAccess.remove_absolute(f)

var _slot_buttons: Array[Button] = []
var _continue_button: Button
var _new_button: Button
var _delete_button: Button
var _quit_button: Button
var _dev_button: Button
var _title_label: Label
var _subtitle_label: Label
var _slots_title_label: Label
var _hint_label: Label
var _status: Label
var _selected_slot: int = 0
var _confirm_overwrite: bool = false
var _confirm_timer: float = 0.0

func _ready() -> void:
	var is_shot := false
	for arg in OS.get_cmdline_user_args():
		if arg.ends_with("-shot"):
			is_shot = true
			break
	if is_shot:
		SettingsSystemScript.path = "user://scratch_settings.json"
		InputBindingsScript.path = "user://scratch_bindings.json"

	LocalizationManagerScript.ensure_loaded()
	LocalizationManagerScript.add_listener(refresh_text)
	if OS.get_cmdline_user_args().has("--pseudo-locale"):
		LocalizationManagerScript.set_language("en_XA")

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
		"--impact-lab", "--impact-matrix", "--plow-demo", "--save-roundtrip",
		"--pause-shot", "--settings-shot", "--rebind-shot", "--i18n-check",
		"--diagnostics-harmless",
	]
	for flag in demo_flags:
		if OS.get_cmdline_user_args().has(flag):
			if flag == "--save-roundtrip":
				_run_save_battery()
				return
			if flag == "--i18n-check":
				_run_i18n_battery()
				return
			if flag == "--diagnostics-harmless":
				_run_diagnostics_harmless_battery()
				return
			_start_level()
			return

	_build_ui()
	refresh_text()
	# Start with the most recent slot selected so Continue is one press away.
	var latest := SaveSystem.latest_slot()
	_select_slot(latest if latest >= 0 else 0)
	if _slot_buttons.size() > 0:
		_slot_buttons[_selected_slot].grab_focus()

	# UI smoke test: render one frame, save it and exit.
	if OS.get_cmdline_user_args().has("--menu-shot"):
		SettingsSystemScript.path = "user://scratch_settings.json"
		InputBindingsScript.path = "user://scratch_bindings.json"
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img:
				img.save_png("res://main_menu.png")
				print("[Menu] screenshot saved (size=%s)" % str(img.get_size()))
		_cleanup_scratch_files()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--pseudo-menu-shot"):
		SettingsSystemScript.path = "user://scratch_settings.json"
		InputBindingsScript.path = "user://scratch_bindings.json"
		LocalizationManagerScript.set_language("en_XA")
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			if img:
				img.save_png("res://main_menu_pseudo.png")
				print("[Menu] pseudo screenshot saved (size=%s)" % str(img.get_size()))
		_cleanup_scratch_files()
		get_tree().quit()
	elif OS.get_cmdline_user_args().has("--cjk-shot"):
		SettingsSystemScript.path = "user://scratch_settings.json"
		InputBindingsScript.path = "user://scratch_bindings.json"
		_title_label.text = "スノー・イット・トゥゲザー"
		_subtitle_label.text = "除雪クルー - プロトタイプ"
		_slots_title_label.text = "セーブスロット"
		_continue_button.text = "コンティニュー"
		_new_button.text = "新しいゲーム"
		_delete_button.text = "スロット削除"
		_quit_button.text = "終了"
		_hint_label.text = "WASD 移動 - 左クリック 作業 - 右クリック 投げる"
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img_ja := get_viewport().get_texture().get_image()
			if img_ja:
				img_ja.save_png("res://main_menu_ja.png")
				print("[CJK] ja screenshot saved (size=%s)" % str(img_ja.get_size()))
		_title_label.text = "눈을 치우자 함께"
		_subtitle_label.text = "제설 작업반 - 프로토타입"
		_slots_title_label.text = "저장 슬롯"
		_continue_button.text = "이어하기"
		_new_button.text = "새 게임"
		_delete_button.text = "슬롯 삭제"
		_quit_button.text = "종료"
		_hint_label.text = "WASD 이동 - 좌클릭 작업 - 우클릭 던지기"
		if DisplayServer.get_name() != "headless":
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img_ko := get_viewport().get_texture().get_image()
			if img_ko:
				img_ko.save_png("res://main_menu_ko.png")
				print("[CJK] ko screenshot saved (size=%s)" % str(img_ko.get_size()))
		print("[CJK] Japanese and Korean visual test complete")
		_cleanup_scratch_files()
		get_tree().quit()

func _exit_tree() -> void:
	LocalizationManagerScript.remove_listener(refresh_text)

func _process(delta: float) -> void:
	if _confirm_overwrite:
		_confirm_timer -= delta
		if _confirm_timer <= 0.0:
			_confirm_overwrite = false
			_new_button.text = tr("MENU_NEW_GAME")

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

	_title_label = Label.new()
	_title_label.text = tr("MENU_TITLE")
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title_label.add_theme_font_size_override("font_size", 44)
	column.add_child(_title_label)

	_subtitle_label = Label.new()
	_subtitle_label.text = tr("MENU_SUBTITLE")
	_subtitle_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_subtitle_label.modulate = Color(0.75, 0.82, 0.92)
	column.add_child(_subtitle_label)

	column.add_child(_spacer(18.0))

	_slots_title_label = Label.new()
	_slots_title_label.text = tr("MENU_SLOTS_TITLE")
	column.add_child(_slots_title_label)

	for slot in range(SaveSystem.SLOT_COUNT):
		var button := Button.new()
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size = Vector2(0.0, 44.0)
		button.pressed.connect(_on_slot_pressed.bind(slot))
		column.add_child(button)
		_slot_buttons.append(button)

	column.add_child(_spacer(14.0))

	_continue_button = Button.new()
	_continue_button.text = tr("MENU_CONTINUE")
	_continue_button.custom_minimum_size = Vector2(0.0, 46.0)
	_continue_button.pressed.connect(_on_continue)
	column.add_child(_continue_button)

	_new_button = Button.new()
	_new_button.text = tr("MENU_NEW_GAME")
	_new_button.custom_minimum_size = Vector2(0.0, 46.0)
	_new_button.pressed.connect(_on_new_game)
	column.add_child(_new_button)

	_delete_button = Button.new()
	_delete_button.text = tr("MENU_DELETE_SLOT")
	_delete_button.custom_minimum_size = Vector2(0.0, 46.0)
	_delete_button.pressed.connect(_on_delete)
	column.add_child(_delete_button)

	_quit_button = Button.new()
	_quit_button.text = tr("MENU_QUIT")
	_quit_button.custom_minimum_size = Vector2(0.0, 46.0)
	_quit_button.pressed.connect(func(): get_tree().quit())
	column.add_child(_quit_button)

	# Development builds only. The Playground is a measuring bench, not content, so it
	# must never sit in front of a player: Continue and New Game always open the level.
	# Debug-only keeps it one click away while developing without shipping it.
	if OS.is_debug_build():
		column.add_child(_spacer(10.0))
		_dev_button = Button.new()
		_dev_button.text = tr("MENU_PLAYGROUND_DEV")
		_dev_button.custom_minimum_size = Vector2(0.0, 38.0)
		_dev_button.tooltip_text = tr("MENU_PLAYGROUND_TOOLTIP")
		_dev_button.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/playground.tscn"))
		column.add_child(_dev_button)

	column.add_child(_spacer(18.0))

	_status = Label.new()
	_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status.modulate = Color(0.85, 0.9, 0.98)
	column.add_child(_status)

	_hint_label = Label.new()
	_hint_label.text = tr("MENU_HINT")
	_hint_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint_label.add_theme_font_size_override("font_size", 12)
	_hint_label.modulate = Color(0.6, 0.68, 0.78)
	column.add_child(_hint_label)

func refresh_text() -> void:
	if _title_label:
		_title_label.text = tr("MENU_TITLE")
	if _subtitle_label:
		_subtitle_label.text = tr("MENU_SUBTITLE")
	if _slots_title_label:
		_slots_title_label.text = tr("MENU_SLOTS_TITLE")
	if _continue_button:
		_continue_button.text = tr("MENU_CONTINUE")
	if _new_button and not _confirm_overwrite:
		_new_button.text = tr("MENU_NEW_GAME")
	if _delete_button:
		_delete_button.text = tr("MENU_DELETE_SLOT")
	if _quit_button:
		_quit_button.text = tr("MENU_QUIT")
	if _dev_button:
		_dev_button.text = tr("MENU_PLAYGROUND_DEV")
		_dev_button.tooltip_text = tr("MENU_PLAYGROUND_TOOLTIP")
	if _hint_label:
		_hint_label.text = tr("MENU_HINT")
	_refresh_slots()

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
	_new_button.text = tr("MENU_NEW_GAME")
	_refresh_slots()

func _on_slot_pressed(slot: int) -> void:
	_select_slot(slot)

func _on_continue() -> void:
	var slot := _selected_slot
	if not SaveSystem.slot_exists(slot):
		slot = SaveSystem.latest_slot()
	if slot < 0 or not SaveSystem.load_slot(slot):
		_status.text = tr("MENU_SLOT_UNREADABLE")
		_refresh_slots()
		return
	_start_level()

func _on_new_game() -> void:
	if SaveSystem.slot_exists(_selected_slot) and not _confirm_overwrite:
		# Two-step confirm so a stray click does not wipe a run.
		_confirm_overwrite = true
		_confirm_timer = 3.0
		_new_button.text = tr("MENU_OVERWRITE_SLOT") % (_selected_slot + 1)
		return
	SaveSystem.new_game(_selected_slot)
	_start_level()

func _on_delete() -> void:
	if not SaveSystem.slot_exists(_selected_slot):
		return
	SaveSystem.delete_slot(_selected_slot)
	_status.text = tr("MENU_SLOT_DELETED") % (_selected_slot + 1)
	_refresh_slots()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_tree().quit()

func _start_level() -> void:
	get_tree().call_deferred("change_scene_to_file", LEVEL_SCENE)

func _run_save_battery() -> void:
	var battery := Node.new()
	battery.set_script(load("res://scripts/save_roundtrip_demo.gd"))
	battery.name = "SaveRoundtripDemo"
	add_child(battery)

func _run_i18n_battery() -> void:
	var battery := Node.new()
	battery.set_script(load("res://scripts/i18n_check_demo.gd"))
	battery.name = "I18nCheckDemo"
	add_child(battery)

func _run_diagnostics_harmless_battery() -> void:
	var battery := Node.new()
	battery.set_script(load("res://scripts/diagnostics_harmless_demo.gd"))
	battery.name = "DiagnosticsHarmlessDemo"
	add_child(battery)

