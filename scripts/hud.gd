extends CanvasLayer

const SoundEffectsScript = preload("res://scripts/sound_effects.gd")

## Emitted once when the level reaches the clear target, so the save file can be
## updated without the HUD knowing anything about persistence.
signal level_completed(cleared_pct: float)

@onready var progress_bar: ProgressBar = $MarginContainer/VBoxTop/ProgressBar
@onready var label_pct: Label = $MarginContainer/VBoxTop/HBoxInfo/LabelPct
@onready var label_kg: Label = $MarginContainer/VBoxTop/HBoxInfo/LabelKg
@onready var label_coins: Label = $MarginContainer/VBoxTop/HBoxInfo/LabelCoins

@onready var label_tool_name: Label = $VBoxBottom/LabelTool
@onready var shovel_bar: ProgressBar = $VBoxBottom/ShovelBar
@onready var label_toss_hint: Label = $VBoxBottom/LabelTossHint
@onready var victory_panel: PanelContainer = $VictoryPanel
@onready var panel_controls: PanelContainer = $PanelControls
@onready var label_controls: Label = $PanelControls/Margin/LabelControls

var coins: int = 0
var has_won: bool = false
var player_ref: CharacterBody3D
var _hint_timer: float = 0.0
## Snow across the face. Sits under the HUD text but over the world.
var _face_overlay: TextureRect
## The pause panel, and the physics frame count when it opened, for the diagnostic.
var _pause_menu: PanelContainer
var _physics_frames_at_pause: int = 0

const CLEAR_TARGET_PCT: float = 90.0

const CONTROLS_TEXT := """CONTROLS  (H to hide this panel)
- W, A, S, D: Move (Shift: Sprint)
- Space: Jump
- Left click: Push / cut snow
- Look ahead: the blade shaves thin sheets (sculpting)
- Right click (hold): tilt the blade and DUMP
- Right click (tap): THROW snow
- Q: Tamp and pack the snow down
- E (tap): Pick up objects and balls - pack a snowball
- E (hold): Push a ball along the ground, never lift it
- While carrying: right click throws it, E drops it
- Large ball: both hands overhead, you stagger with it
- Hit in the face: hold E to wipe the snow off
- 1, 2, 3: Shovel / Blower / Salt
- ESC: release mouse - R: restart level - H: hide help"""

func _ready() -> void:
	_build_face_overlay()
	# The HUD has to keep working while the game is paused: it owns the pause menu, so
	# being paused must not stop it from reading the key that unpauses.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_pause_menu()
	if victory_panel:
		victory_panel.visible = false
	# The help panel starts hidden so it never covers the scene.
	if panel_controls:
		panel_controls.visible = false
	if label_controls:
		label_controls.text = CONTROLS_TEXT
	if OS.get_cmdline_user_args().has("--pause-shot"):
		_run_pause_shot()

## Pause that pauses. Until now ESC only released the mouse while the snow kept falling
## behind it, which is not a pause menu, it is a way to lose the mouse.
func _build_pause_menu() -> void:
	_pause_menu = PanelContainer.new()
	_pause_menu.name = "PauseMenu"
	_pause_menu.visible = false
	_pause_menu.set_anchors_preset(Control.PRESET_CENTER)
	_pause_menu.custom_minimum_size = Vector2(260.0, 0.0)
	add_child(_pause_menu)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 18)
	margin.add_theme_constant_override("margin_right", 18)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_bottom", 14)
	_pause_menu.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 22)
	column.add_child(title)

	column.add_child(_pause_button("Resume", func() -> void: _set_paused(false)))
	column.add_child(_pause_button("Restart level", func() -> void:
		_set_paused(false)
		get_tree().reload_current_scene()))
	column.add_child(_pause_button("Quit to menu", func() -> void:
		_set_paused(false)
		get_tree().change_scene_to_file("res://scenes/main_menu.tscn")))

func _pause_button(label: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = label
	button.custom_minimum_size = Vector2(0.0, 40.0)
	button.pressed.connect(action)
	return button

func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		_set_paused(not get_tree().paused)
		get_viewport().set_input_as_handled()

func _set_paused(paused: bool) -> void:
	get_tree().paused = paused
	if _pause_menu:
		_pause_menu.visible = paused
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
		label_coins.text = "Money: $%d" % coins

func _process(delta: float) -> void:
	if not player_ref:
		return
	_hint_timer = maxf(_hint_timer - delta, 0.0)

	if "current_tool" in player_ref:
		match player_ref.current_tool:
			0: # SHOVEL
				label_tool_name.text = "Tool: [1] Snow Shovel"
				shovel_bar.visible = true
				if "shovel_current_load" in player_ref:
					shovel_bar.value = player_ref.shovel_current_load
					shovel_bar.max_value = player_ref.shovel_capacity_max
			1: # BLOWER
				label_tool_name.text = "Tool: [2] Motorized Snow Blower"
				shovel_bar.visible = false
			2: # SALT
				label_tool_name.text = "Tool: [3] Thermal Salt Spreader"
				shovel_bar.visible = false

	_update_face_overlay()
	_update_hint()

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
	if float(player_ref.get("face_snow_timer")) > 0.0:
		text = "Snow on your face - hold [E] to wipe it off"
	elif player_ref.get("is_stuck") == true:
		text = "SHOVEL JAMMED! Look ahead to shave thin, or press [Q] to tamp"
	elif player_ref.get("is_ground_pushing") == true:
		text = "Pushing the ball along the ground - release [E] to leave it"
	elif player_ref.has_method("is_carrying") and player_ref.is_carrying():
		var mass: float = float(player_ref.get("carried_mass"))
		if player_ref.get("carry_two_hands") == true:
			var grip: float = float(player_ref.get("grip_left"))
			if grip < 0.3:
				text = "ABOUT TO SLIP! %.0f kg - press [E] to drop it" % mass
			else:
				text = "BALL OF %.0f KG overhead - grip %d%% - [E] drop, right click throw" % [
					mass, int(grip * 100.0)]
		else:
			text = "Carrying %.1f kg - [E] drop, right click throw" % mass
	elif String(player_ref.get("status_message")) != "" and _hint_timer <= 0.0:
		text = String(player_ref.get("status_message"))
		_hint_timer = 3.0
	elif "shovel_current_load" in player_ref and player_ref.shovel_current_load > 5.0:
		text = "Load: %.1f kg - hold right click to dump, tap to throw" % player_ref.shovel_current_load
	label_toss_hint.visible = text != ""
	label_toss_hint.text = text

func _on_progress_updated(pct: float, kg_cleared: float, _kg_total: float) -> void:
	progress_bar.value = pct
	label_pct.text = "Cleared: %d%%" % int(pct)
	label_kg.text = "Snow removed: %.1f kg" % kg_cleared

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
