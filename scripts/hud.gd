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
- 1, 2, 3: Shovel / Blower / Salt
- ESC: release mouse - R: restart level - H: hide help"""

func _ready() -> void:
	if victory_panel:
		victory_panel.visible = false
	# The help panel starts hidden so it never covers the scene.
	if panel_controls:
		panel_controls.visible = false
	if label_controls:
		label_controls.text = CONTROLS_TEXT

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

	_update_hint()

## Contextual physics readouts: jammed blade, what is in your hands, how much
## snow the blade is holding.
func _update_hint() -> void:
	if label_toss_hint == null:
		return
	var text := ""
	if player_ref.get("is_stuck") == true:
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
