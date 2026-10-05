extends CanvasLayer

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")
const SettingsSystemScript = preload("res://scripts/settings_system.gd")
const InputBindingsScript = preload("res://scripts/input_bindings.gd")
const LocalizationManagerScript = preload("res://scripts/localization_manager.gd")

## Emitted once when the level reaches the clear target, so the save file can be
## updated without the HUD knowing anything about persistence.
signal level_completed(cleared_pct: float)

@onready var label_title: Label = $MarginContainer/VBoxTop/Title
@onready var progress_bar: ProgressBar = $MarginContainer/VBoxTop/ProgressBar
@onready var label_pct: Label = $MarginContainer/VBoxTop/HBoxInfo/LabelPct
@onready var label_kg: Label = $MarginContainer/VBoxTop/HBoxInfo/LabelKg
@onready var label_coins: Label = $MarginContainer/VBoxTop/HBoxInfo/LabelCoins

@onready var label_tool_name: Label = $VBoxBottom/LabelTool
@onready var shovel_bar: ProgressBar = $VBoxBottom/ShovelBar
@onready var label_toss_hint: Label = $VBoxBottom/LabelTossHint
@onready var victory_panel: PanelContainer = $VictoryPanel
@onready var victory_title: Label = $VictoryPanel/VBox/Title
@onready var victory_sub: Label = $VictoryPanel/VBox/Sub
@onready var panel_controls: PanelContainer = $PanelControls
@onready var label_controls: Label = $PanelControls/Margin/LabelControls

var coins: int = 0
var has_won: bool = false
var player_ref: CharacterBody3D
var _hint_timer: float = 0.0
var _last_pct: float = 0.0
var _last_kg: float = 0.0
## Snow across the face. Sits under the HUD text but over the world.
var _face_overlay: TextureRect
## The pause panel, and the physics frame count when it opened, for the diagnostic.
var _pause_menu: PanelContainer
var _pause_title: Label
var _pause_resume_btn: Button
var _pause_restart_btn: Button
var _pause_settings_btn: Button
var _pause_quit_btn: Button

var _settings_panel: PanelContainer
var _settings_title: Label
var _settings_vol_label: Label
var _settings_sens_label: Label
var _settings_shake_label: Label
var _settings_invert_check: CheckButton
var _settings_face_check: CheckButton
var _settings_lang_label: Label
var _settings_lang_opt: OptionButton
var _settings_back_btn: Button
var _settings_controls_btn: Button
var _settings_reset_btn: Button

var _controls_panel: PanelContainer
var _controls_title: Label
var _control_labels: Dictionary = {}
var _control_buttons: Dictionary = {}
var _controls_back_btn: Button
var _controls_reset_btn: Button
var _listening_for: String = ""
var _physics_frames_at_pause: int = 0

const CLEAR_TARGET_PCT: float = 90.0

func _ready() -> void:
	LocalizationManagerScript.ensure_loaded()
	LocalizationManagerScript.add_listener(refresh_text)
	_build_face_overlay()
	# The HUD has to keep working while the game is paused: it owns the pause menu, so
	# being paused must not stop it from reading the key that unpauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_menu()
	_build_settings_panel()
	SettingsSystemScript.load_from_disk()
	SettingsSystemScript.apply_to_engine()
	refresh_text()
	if OS.get_cmdline_user_args().has("--rebind-shot"):
		_run_rebind_shot()
	if OS.get_cmdline_user_args().has("--settings-shot"):
		_run_settings_shot()
	if victory_panel:
		victory_panel.visible = false
	# The help panel starts hidden so it never covers the scene.
	if panel_controls:
		panel_controls.visible = false
	if OS.get_cmdline_user_args().has("--pause-shot"):
		_run_pause_shot()

func _exit_tree() -> void:
	LocalizationManagerScript.remove_listener(refresh_text)

## Pause that pauses. Until now ESC only released the mouse while the snow kept falling
## behind it, which is not a pause menu, it is a way to lose the mouse.
func _build_pause_menu() -> void:
	# Anchors alone do not centre a panel inside a CanvasLayer, which is why the first
	# version sat low and to the right. A full-rect container does the centring, and it
	# ignores the mouse so it never swallows a click meant for the world.
	var centre := CenterContainer.new()
	centre.name = "PauseCentre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_pause_menu = PanelContainer.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.visible = false
	_pause_menu.custom_minimum_size = Vector2(260.0, 0.0)
	centre.add_child(_pause_menu)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_pause_menu.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	_pause_title = Label.new()
	_pause_title.text = tr("PAUSE_TITLE")
	_pause_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_pause_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_pause_title)

	_pause_resume_btn = _pause_button("PAUSE_RESUME", func() -> void: _set_paused(false))
	column.add_child(_pause_resume_btn)
	_pause_restart_btn = _pause_button("PAUSE_RESTART", func() -> void:
		_set_paused(false)
		get_tree().reload_current_scene())
	column.add_child(_pause_restart_btn)
	_pause_settings_btn = _pause_button("PAUSE_SETTINGS", func() -> void: _show_settings(true))
	column.add_child(_pause_settings_btn)
	_pause_quit_btn = _pause_button("PAUSE_QUIT_MENU", func() -> void:
		_set_paused(false)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn"))
	column.add_child(_pause_quit_btn)

func _pause_button(label_or_key: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = tr(label_or_key)
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(action)
	return button

## The settings screen. Every control writes straight through to the settings file, so
## there is no "apply" button to forget and no state that only exists on screen.
func _build_settings_panel() -> void:
	var centre := CenterContainer.new()
	centre.name = "SettingsCentre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_settings_panel = PanelContainer.new()
	_settings_panel.name = "SettingsPanel"
	_settings_panel.visible = false
	_settings_panel.custom_minimum_size = Vector2(420.0, 0.0)
	centre.add_child(_settings_panel)

	var margin := MarginContainer.new()
	for side in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	for side in ["top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 16)
	_settings_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	_settings_title = Label.new()
	_settings_title.text = tr("SETTINGS_TITLE")
	_settings_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_settings_title)

	var vol_box := _setting_slider("SETTINGS_VOLUME", 0.0, 1.0, 0.01,
		SettingsSystemScript.master_volume,
		func(v: float) -> void:
			SettingsSystemScript.master_volume = v
			SettingsSystemScript.apply_to_engine())
	_settings_vol_label = vol_box.get_child(0) as Label
	column.add_child(vol_box)

	var sens_box := _setting_slider("SETTINGS_SENSITIVITY", 0.1, 3.0, 0.05,
		SettingsSystemScript.mouse_sensitivity,
		func(v: float) -> void: SettingsSystemScript.mouse_sensitivity = v)
	_settings_sens_label = sens_box.get_child(0) as Label
	column.add_child(sens_box)

	var shake_box := _setting_slider("SETTINGS_SHAKE", 0.0, 2.0, 0.05,
		SettingsSystemScript.screen_shake,
		func(v: float) -> void: SettingsSystemScript.screen_shake = v)
	_settings_shake_label = shake_box.get_child(0) as Label
	column.add_child(shake_box)

	_settings_invert_check = _setting_check("SETTINGS_INVERT", SettingsSystemScript.invert_look,
		func(on: bool) -> void: SettingsSystemScript.invert_look = on)
	column.add_child(_settings_invert_check)

	_settings_face_check = _setting_check("SETTINGS_FACE_SNOW", SettingsSystemScript.face_snow_auto_clear,
		func(on: bool) -> void: SettingsSystemScript.face_snow_auto_clear = on)
	column.add_child(_settings_face_check)

	column.add_child(_build_language_row())

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_settings_back_btn = _pause_button("SETTINGS_BACK", func() -> void: _show_settings(false))
	buttons.add_child(_settings_back_btn)
	_settings_controls_btn = _pause_button("SETTINGS_CONTROLS", func() -> void:
		_build_controls_panel()
		_show_controls(true))
	buttons.add_child(_settings_controls_btn)
	_settings_reset_btn = _pause_button("SETTINGS_RESET", func() -> void:
		SettingsSystemScript.defaults()
		SettingsSystemScript.apply_to_engine()
		SettingsSystemScript.save()
		_show_settings(false)
		_show_settings(true))
	buttons.add_child(_settings_reset_btn)

func _build_language_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)

	_settings_lang_label = Label.new()
	_settings_lang_label.text = tr("SETTINGS_LANGUAGE")
	_settings_lang_label.custom_minimum_size = Vector2(180.0, 0.0)
	row.add_child(_settings_lang_label)

	_settings_lang_opt = OptionButton.new()
	_settings_lang_opt.custom_minimum_size = Vector2(180.0, 32.0)
	var langs = LocalizationManagerScript.available_languages()
	var cur = LocalizationManagerScript.current_language()
	var select_idx := 0
	for i in range(langs.size()):
		var entry = langs[i]
		_settings_lang_opt.add_item(entry["name"])
		_settings_lang_opt.set_item_metadata(i, entry["code"])
		if entry["code"] == cur:
			select_idx = i
	_settings_lang_opt.selected = select_idx
	_settings_lang_opt.item_selected.connect(func(idx: int):
		var code: String = _settings_lang_opt.get_item_metadata(idx)
		SettingsSystemScript.language = code
		SettingsSystemScript.save()
		LocalizationManagerScript.set_language(code))
	row.add_child(_settings_lang_opt)
	return row

## A slider that writes through to the settings on every change, then persists.
func _setting_slider(key: String, low: float, high: float, step: float,
		value: float, on_change: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	var text := Label.new()
	text.text = tr(key)
	box.add_child(text)
	var slider := HSlider.new()
	slider.min_value = low
	slider.max_value = high
	slider.step = step
	slider.value = value
	slider.custom_minimum_size = Vector2(0.0, 22.0)
	slider.value_changed.connect(func(v: float) -> void:
		on_change.call(v)
		SettingsSystemScript.save())
	box.add_child(slider)
	return box

func _setting_check(key: String, value: bool, on_change: Callable) -> CheckButton:
	var check := CheckButton.new()
	check.text = tr(key)
	check.button_pressed = value
	check.toggled.connect(func(on: bool) -> void:
		on_change.call(on)
		SettingsSystemScript.save())
	return check

func _show_settings(visible_now: bool) -> void:
	if _settings_panel == null:
		return
	_settings_panel.visible = visible_now
	if _pause_menu:
		_pause_menu.visible = not visible_now
		if visible_now:
			return
		for node in _pause_menu.find_children("*", "Button", true, false):
			(node as Button).grab_focus()
			break

## Diagnostic: prove the values survive a round trip through the file, not merely that
## the screen draws. A settings screen that forgets everything on restart looks perfect.
func _run_settings_shot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	SettingsSystemScript.master_volume = 0.33
	SettingsSystemScript.invert_look = true
	var wrote: bool = SettingsSystemScript.save()
	SettingsSystemScript.defaults()
	var read_back: bool = SettingsSystemScript.load_from_disk()
	SettingsSystemScript.apply_to_engine()
	print("[SETTINGS] wrote=%s read=%s -> %s" % [str(wrote), str(read_back), SettingsSystemScript.describe()])
	var volume_ok: bool = absf(SettingsSystemScript.master_volume - 0.33) < 0.01
	var invert_ok: bool = SettingsSystemScript.invert_look
	print("[SETTINGS] round trip volume=0.33 -> %s, invert=true -> %s" % [
		str(volume_ok), str(invert_ok)])
	_set_paused(true)
	_show_settings(true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var rect := _settings_panel.get_global_rect()
	var want: Vector2 = get_viewport().get_visible_rect().get_center()
	var off := rect.get_center() - want
	var err := get_viewport().get_texture().get_image().save_png("res://settings_menu.png")
	print("[SETTINGS] panel visible=%s, %d controls, centre off by (%.0f, %.0f) px, shot err=%d" % [
		str(_settings_panel.visible), _settings_panel.find_children("*", "Slider", true, false).size() + _settings_panel.find_children("*", "CheckButton", true, false).size(),
		off.x, off.y, err])
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)

func _input(event: InputEvent) -> void:
	# While an action is being rebound the next press IS the binding, and nothing else may
	# react to it: not the pause toggle, not the game.
	if _listening_for != "":
		var usable := false
		if event is InputEventKey:
			usable = (event as InputEventKey).pressed
		elif event is InputEventJoypadButton:
			usable = (event as InputEventJoypadButton).pressed
		elif event is InputEventJoypadMotion:
			usable = absf((event as InputEventJoypadMotion).axis_value) > 0.6
		if usable:
			var action := _listening_for
			_listening_for = ""
			var taken: bool = InputBindingsScript.rebind(action, event)
			_refresh_control_buttons()
			print("[BIND] %s -> %s (accepted=%s)" % [action, InputBindingsScript.binding_label(action), str(taken)])
			get_viewport().set_input_as_handled()
			return
	if event.is_action_pressed("ui_cancel"):
		if _controls_panel and _controls_panel.visible:
			_show_controls(false)
		elif _settings_panel and _settings_panel.visible:
			_show_settings(false)
		else:
			_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if _pause_menu:
		_pause_menu.visible = paused
		if paused:
			# Focus the first action so a controller can drive this without a mouse, the
			# way the Steam Deck and console targets need. Keyboard users keep working
			# exactly as before, because ui_cancel still closes the menu.
			for node in _pause_menu.find_children("*", "Button", true, false):
				(node as Button).grab_focus()
				break
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if paused else Input.MOUSE_MODE_CAPTURED
	print("[PAUSE] paused=%s" % str(paused))

## Diagnostic: prove the menu exists, that the tree really stopped, and what it looks
## like. A pause that only hides the world behind a panel would pass a screenshot test,
## so the world's own clock is checked too.
func _run_pause_shot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	_physics_frames_at_pause = Engine.get_physics_frames()
	_set_paused(true)
	await get_tree().process_frame
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	var err := img.save_png("res://pause_menu.png")
	print("[PAUSE] menu visible=%s, tree paused=%s, physics frames while paused=%d, shot err=%d" % [
		str(_pause_menu.visible), str(get_tree().paused),
		Engine.get_physics_frames() - _physics_frames_at_pause, err])
	# Centring is claimed, so it is measured: the panel's centre against the viewport's.
	var rect := _pause_menu.get_global_rect()
	var want: Vector2 = get_viewport().get_visible_rect().get_center()
	var off := rect.get_center() - want
	print("[PAUSE] panel centre %s vs viewport centre %s: off by (%.0f, %.0f) px" % [
		str(rect.get_center()), str(want), off.x, off.y])
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)

## A hand-drawn snow splat, generated once: no art needed and it scales to any
## resolution. Added first so the HUD text stays readable through it.
func _build_face_overlay() -> void:
	var size := 128
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	img.fill(Color(1.0, 1.0, 1.0, 0.0))
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260105
	# A thick smear across the middle, thinning towards the edges.
	for i in range(90):
		var cx := rng.randf_range(0.05, 0.95) * float(size)
		var cy := (0.5 + (rng.randf_range(-0.5, 0.5) * absf(rng.randf_range(-1.0, 1.0)))) * float(size)
		var r := rng.randf_range(6.0, 26.0)
		var alpha := rng.randf_range(0.25, 0.7)
		for y in range(maxi(int(cy - r), 0), mini(int(cy + r), size)):
			for x in range(maxi(int(cx - r), 0), mini(int(cx + r), size)):
				var d := Vector2(float(x) - cx, float(y) - cy).length()
				if d > r:
					continue
				var falloff := 1.0 - (d / r)
				var a: float = img.get_pixel(x, y).a
				img.set_pixel(x, y, Color(1.0, 1.0, 1.0, minf(a + alpha * falloff, 0.95)))
	var texture := ImageTexture.create_from_image(img)
	_face_overlay = TextureRect.new()
	_face_overlay.texture = texture
	_face_overlay.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_face_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_face_overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	_face_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_face_overlay.modulate = Color(1.0, 1.0, 1.0, 0.0)
	_face_overlay.visible = false
	add_child(_face_overlay)
	move_child(_face_overlay, 0)

func init_hud(player: CharacterBody3D, snow_field: Node3D) -> void:
	player_ref = player
	if snow_field and snow_field.has_signal("progress_updated"):
		snow_field.progress_updated.connect(_on_progress_updated)
		snow_field.snow_tossed_in_bank.connect(_on_snow_tossed)

## Restores the money counter from the loaded save slot.
func set_coins(value: int) -> void:
	coins = value
	if label_coins:
		label_coins.text = tr("HUD_MONEY") % coins

func _process(delta: float) -> void:
	if not player_ref:
		return
	_hint_timer = maxf(_hint_timer - delta, 0.0)
	_update_tool_label()
	_update_face_overlay()
	_update_hint()

func _update_tool_label() -> void:
	if not label_tool_name or not player_ref:
		return
	if "current_tool" in player_ref:
		match player_ref.current_tool:
			0: # SHOVEL
				label_tool_name.text = tr("HUD_TOOL_SHOVEL")
				shovel_bar.visible = true
				if "shovel_current_load" in player_ref:
					shovel_bar.value = player_ref.shovel_current_load
					shovel_bar.max_value = player_ref.shovel_capacity_max
			1: # BLOWER
				label_tool_name.text = tr("HUD_TOOL_BLOWER")
				shovel_bar.visible = false
			2: # SALT
				label_tool_name.text = tr("HUD_TOOL_SALT")
				shovel_bar.visible = false

## Snow across the face, driven by the player's reaction state.
func _update_face_overlay() -> void:
	if _face_overlay == null:
		return
	var amount: float = clampf(float(player_ref.get("face_snow_amount")), 0.0, 1.0)
	_face_overlay.visible = amount > 0.01
	_face_overlay.modulate.a = amount * 0.95

## Contextual physics readouts: jammed blade, what is in your hands, how much
## snow the blade is holding.
func _update_hint() -> void:
	if label_toss_hint == null:
		return
	var text := ""
	if player_ref and float(player_ref.get("face_snow_timer")) > 0.0:
		text = tr("HUD_WIPE_FACE")
	elif player_ref and player_ref.get("is_stuck") == true:
		text = tr("HUD_SHOVEL_JAMMED")
	elif player_ref and player_ref.get("is_ground_pushing") == true:
		text = tr("HUD_GROUND_PUSHING")
	elif player_ref and player_ref.has_method("is_carrying") and player_ref.is_carrying():
		var mass: float = float(player_ref.get("carried_mass"))
		if player_ref.get("carry_two_hands") == true:
			var grip: float = float(player_ref.get("grip_left"))
			if grip < 0.3:
				text = tr("HUD_CARRY_SLIP") % mass
			else:
				text = tr("HUD_CARRY_OVERHEAD") % [
					mass, int(grip * 100.0)]
		else:
			text = tr("HUD_CARRY_ONE_HAND") % mass
	elif player_ref and String(player_ref.get("status_message")) != "" and _hint_timer <= 0.0:
		text = String(player_ref.get("status_message"))
		_hint_timer = 3.0
	elif player_ref and "shovel_current_load" in player_ref and player_ref.shovel_current_load > 5.0:
		if player_ref.shovel_current_load >= float(player_ref.get("shovel_capacity_max")) - 0.5:
			text = tr("HUD_BLADE_FULL_HINT")
		else:
			text = tr("HUD_SHOVEL_LOAD") % player_ref.shovel_current_load
	label_toss_hint.visible = text != ""
	label_toss_hint.text = text

func _on_progress_updated(pct: float, kg_cleared: float, _kg_total: float) -> void:
	_last_pct = pct
	_last_kg = kg_cleared
	progress_bar.value = pct
	label_pct.text = tr("HUD_CLEARED") % int(pct)
	label_kg.text = tr("HUD_SNOW_REMOVED") % kg_cleared

	if pct >= CLEAR_TARGET_PCT and not has_won:
		has_won = true
		_show_victory()
		level_completed.emit(pct)

func _on_snow_tossed(bonus: int, _pos: Vector3) -> void:
	set_coins(coins + bonus)

	var sfx = AudioStreamPlayer.new()
	sfx.stream = SoundEffectsScript.get_sound("coin")
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

func _show_victory() -> void:
	if victory_panel:
		victory_panel.visible = true
	if victory_title:
		victory_title.text = tr("HUD_VICTORY_TITLE")
	if victory_sub:
		victory_sub.text = tr("HUD_VICTORY_SUB")
	var sfx = AudioStreamPlayer.new()
	sfx.stream = SoundEffectsScript.get_sound("victory")
	add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R:
			get_tree().reload_current_scene()
		elif event.keycode == KEY_H:
			if panel_controls:
				panel_controls.visible = not panel_controls.visible

## The controls screen. One row per action, showing what it is bound to right now.
func _build_controls_panel() -> void:
	if _controls_panel != null:
		_refresh_control_buttons()
		return
	var centre := CenterContainer.new()
	centre.name = "ControlsCentre"
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	centre.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(centre)

	_controls_panel = PanelContainer.new()
	_controls_panel.name = "ControlsPanel"
	_controls_panel.visible = false
	_controls_panel.custom_minimum_size = Vector2(460.0, 0.0)
	centre.add_child(_controls_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_controls_panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 7)
	margin.add_child(column)

	_controls_title = Label.new()
	_controls_title.text = tr("CONTROLS_TITLE")
	_controls_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_controls_title.add_theme_font_size_override("font_size", 22)
	column.add_child(_controls_title)

	_control_buttons.clear()
	_control_labels.clear()
	for action in InputBindingsScript.ACTIONS:
		if not InputMap.has_action(action):
			continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		column.add_child(row)
		var label := Label.new()
		label.text = InputBindingsScript.action_label(action)
		label.custom_minimum_size = Vector2(200.0, 0.0)
		row.add_child(label)
		_control_labels[action] = label
		var button := Button.new()
		button.custom_minimum_size = Vector2(200.0, 32.0)
		button.pressed.connect(_start_listening.bind(action))
		row.add_child(button)
		_control_buttons[action] = button

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	column.add_child(buttons)
	_controls_back_btn = _pause_button("CONTROLS_BACK", func() -> void: _show_controls(false))
	buttons.add_child(_controls_back_btn)
	_controls_reset_btn = _pause_button("CONTROLS_RESET", func() -> void:
		InputBindingsScript.reset_to_defaults()
		_refresh_control_buttons())
	buttons.add_child(_controls_reset_btn)
	_refresh_control_buttons()

func _refresh_control_buttons() -> void:
	for action in _control_buttons.keys():
		var button: Button = _control_buttons[action]
		if action == _listening_for:
			button.text = tr("CONTROLS_LISTENING")
		else:
			button.text = InputBindingsScript.binding_label(action)

func _start_listening(action: String) -> void:
	_listening_for = action
	_refresh_control_buttons()
	print("[BIND] listening for %s" % action)

func _show_controls(visible_now: bool) -> void:
	if _controls_panel == null:
		return
	_controls_panel.visible = visible_now
	if _settings_panel:
		_settings_panel.visible = not visible_now
	if _pause_menu and visible_now:
		_pause_menu.visible = false
	if not visible_now:
		_refresh_control_buttons()

func refresh_text() -> void:
	if label_title:
		label_title.text = tr("HUD_TITLE")
	if label_pct:
		label_pct.text = tr("HUD_CLEARED") % int(_last_pct)
	if label_kg:
		label_kg.text = tr("HUD_SNOW_REMOVED") % _last_kg
	if label_coins:
		label_coins.text = tr("HUD_MONEY") % coins
	if label_controls:
		label_controls.text = tr("HELP_CONTROLS")
	if victory_title:
		victory_title.text = tr("HUD_VICTORY_TITLE")
	if victory_sub:
		victory_sub.text = tr("HUD_VICTORY_SUB")

	_update_tool_label()
	_update_hint()

	# Pause menu
	if _pause_title:
		_pause_title.text = tr("PAUSE_TITLE")
	if _pause_resume_btn:
		_pause_resume_btn.text = tr("PAUSE_RESUME")
	if _pause_restart_btn:
		_pause_restart_btn.text = tr("PAUSE_RESTART")
	if _pause_settings_btn:
		_pause_settings_btn.text = tr("PAUSE_SETTINGS")
	if _pause_quit_btn:
		_pause_quit_btn.text = tr("PAUSE_QUIT_MENU")

	# Settings panel
	if _settings_title:
		_settings_title.text = tr("SETTINGS_TITLE")
	if _settings_vol_label:
		_settings_vol_label.text = tr("SETTINGS_VOLUME")
	if _settings_sens_label:
		_settings_sens_label.text = tr("SETTINGS_SENSITIVITY")
	if _settings_shake_label:
		_settings_shake_label.text = tr("SETTINGS_SHAKE")
	if _settings_invert_check:
		_settings_invert_check.text = tr("SETTINGS_INVERT")
	if _settings_face_check:
		_settings_face_check.text = tr("SETTINGS_FACE_SNOW")
	if _settings_lang_label:
		_settings_lang_label.text = tr("SETTINGS_LANGUAGE")
	if _settings_back_btn:
		_settings_back_btn.text = tr("SETTINGS_BACK")
	if _settings_controls_btn:
		_settings_controls_btn.text = tr("SETTINGS_CONTROLS")
	if _settings_reset_btn:
		_settings_reset_btn.text = tr("SETTINGS_RESET")

	if _settings_lang_opt:
		var cur = LocalizationManagerScript.current_language()
		for i in range(_settings_lang_opt.item_count):
			if _settings_lang_opt.get_item_metadata(i) == cur:
				_settings_lang_opt.selected = i
				break

	# Controls panel
	if _controls_title:
		_controls_title.text = tr("CONTROLS_TITLE")
	for action in _control_labels.keys():
		_control_labels[action].text = InputBindingsScript.action_label(action)
	if _controls_back_btn:
		_controls_back_btn.text = tr("CONTROLS_BACK")
	if _controls_reset_btn:
		_controls_reset_btn.text = tr("CONTROLS_RESET")
	_refresh_control_buttons()

## Diagnostic: prove a rebinding survives a restart, which is the only thing that makes it
## useful. Rebinds jump, wipes it deliberately, reloads from disk and checks it came back.
func _run_rebind_shot() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	InputBindingsScript.capture_defaults()
	var before := InputBindingsScript.binding_label("jump")
	var key := InputEventKey.new()
	key.keycode = KEY_J
	var changed := InputBindingsScript.rebind("jump", key)
	var after := InputBindingsScript.binding_label("jump")
	InputMap.action_erase_events("jump")
	var wiped := InputBindingsScript.binding_label("jump")
	var reloaded := InputBindingsScript.load_from_disk()
	var final := InputBindingsScript.binding_label("jump")
	print("[BIND] jump %s -> %s (accepted=%s), wiped to %s, after reload %s (read=%s)" % [
		before, after, str(changed), wiped, final, str(reloaded)])
	print("[BIND] survived the restart: %s" % str(final.contains("J")))
	# Exercise the capture hook the way a button press would, instead of trusting it.
	_listening_for = "sprint"
	var press := InputEventKey.new()
	press.keycode = KEY_K
	press.pressed = true
	_input(press)
	print("[BIND] capture hook: sprint is now %s" % InputBindingsScript.binding_label("sprint"))
	var other := InputBindingsScript.binding_label("interact")
	print("[BIND] a different action is untouched: interact = %s" % other)
	_set_paused(true)
	_build_controls_panel()
	_show_controls(true)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var err := get_viewport().get_texture().get_image().save_png("res://controls_menu.png")
	var rect := _controls_panel.get_global_rect()
	var want: Vector2 = get_viewport().get_visible_rect().get_center()
	var off := rect.get_center() - want
	print("[BIND] controls screen visible=%s, %d rows, centre off by (%.0f, %.0f) px, shot err=%d" % [
		str(_controls_panel.visible), _control_buttons.size(), off.x, off.y, err])
	get_tree().create_timer(0.3).timeout.connect(get_tree().quit)
