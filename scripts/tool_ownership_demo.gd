extends Node

# ToolOwnershipDemo: Acceptance battery for tool ownership and purchasing.
# Verifies:
# 1. Fresh save owns only the hand; tool enum reports HANDS.
# 2. Anti-soft-lock: With only the hand, coin balance increases by packing,
#    rolling and delivering a ball to the bank.
# 3. Purchasing an affordable tool deducts exactly its price and grants it.
# 4. Purchasing an unaffordable tool fails, deducts nothing, and grants nothing.
# 5. Ownership survives save/load roundtrip.
# 6. Cycling never selects an unowned tool.
# 7. In Playground, all tools are owned from the start.

const SnowBallScript = preload("res://scripts/snowball.gd")
const DisposalMachineScript = preload("res://scripts/disposal_machine.gd")
const SCRATCH_SLOT: int = 97
## Where the Playground puts its disposal machine, and how high its mouth is. Kept here so the
## throw is aimed at the mouth: `Playground.RUN_END - 1.0` is 17.0.
const MACHINE_Z: float = 17.0
const MACHINE_MOUTH_Y: float = 1.15

var root: Node3D
var snow_field: Node3D
var player: CharacterBody3D
var props: Node3D

var _t: float = 0.0
var _state: int = 0
var _state_time: float = 0.0

var _checks_ok: int = 0
var _checks_fail: int = 0
var _finished: bool = false

var _packed_ball_mass: float = 0.0
var _coins_before_delivery: int = 0

func setup(scene_root: Node3D, field: Node3D, ply: Node3D, props_node: Node3D) -> void:
	root = scene_root
	snow_field = field
	player = ply
	props = props_node
	print("[TOOL] ==== TOOL OWNERSHIP ACCEPTANCE BATTERY ====")
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

## Points the camera down at the snow just in front of the player's feet.
##
## Every battery that packs by hand has to do this now, because gathering requires the aim point
## to be within PACK_REACH_STRICT (1.3 m). Aiming is part of the mechanic, not a detail of the
## test: a battery that packs while looking at the horizon is testing behaviour the game does
## not have any more.
func _aim_at_snow_below() -> void:
	if player == null or player.camera == null or snow_field == null:
		return
	var feet_h: float = float(snow_field.get_height_at(player.global_position))
	player.camera.look_at(Vector3(player.global_position.x, feet_h, player.global_position.z + 0.7), Vector3.UP)
	player._update_reticle_aim()


func _physics_process(delta: float) -> void:
	_t += delta
	_state_time += delta

	match _state:
		0:
			# State 0: Setup fresh save and verify check 1 (fresh save owns only hands)
			SaveSystem.delete_slot(SCRATCH_SLOT)
			SaveSystem.new_game(SCRATCH_SLOT)
			player.current_tool = player.ToolType.HANDS
			player._owned_tools.clear()
			player._owned_tools.append("hands")

			print("[TOOL] Fresh save slot %d created" % SCRATCH_SLOT)
			_check("fresh save owns only hands in SaveSystem", SaveSystem.data.get("owned_tools") == ["hands"])
			_check("fresh save reports hands owned", SaveSystem.is_tool_owned("hands"))
			_check("fresh save reports shovel unowned", not SaveSystem.is_tool_owned("shovel"))
			_check("fresh save reports blower unowned", not SaveSystem.is_tool_owned("blower"))
			_check("fresh save reports salt unowned", not SaveSystem.is_tool_owned("salt"))
			_check("player current_tool is HANDS", player.current_tool == player.ToolType.HANDS)
			_check("player reports hands owned", player.is_tool_owned("hands"))
			_check("player reports shovel unowned", not player.is_tool_owned("shovel"))
			_check("player initial coins are 0", player.coins == 0)

			var mach := root.get_node_or_null("DisposalMachine")
			var mach_pos := (mach as Node3D).global_position if mach != null else Vector3(0.0, 0.0, -7.6)
			var to_mach_z := -1.0 if mach_pos.z < 0.0 else 1.0
			var ply_z := mach_pos.z - to_mach_z * 2.2
			var ground_y: float = 0.32
			if snow_field and snow_field.has_method("get_support_snow_height"):
				ground_y = maxf(float(snow_field.get_support_snow_height(Vector3(0.0, 0.0, ply_z))), 0.15)

			player.global_position = Vector3(0.0, ground_y, ply_z)
			player.set("current_ground_y", ground_y)
			player.set("is_ground_initialized", true)
			player.rotation = Vector3.ZERO
			player.rotation.y = 0.0 if to_mach_z < 0.0 else PI
			if player.camera:
				player.camera.rotation = Vector3.ZERO

			_change_state(1)

		1:
			# State 1: Wait for physics/terrain to settle, then request hand-packing
			if _state_time >= 0.25:
				_coins_before_delivery = player.coins
				# LOOK AT THE SNOW BEFORE PACKING. Gathering now requires the aim point to be
				# within PACK_REACH_STRICT (1.3 m); the camera was left at zero rotation, which
				# is looking straight ahead at the horizon, and that is exactly the case the
				# owner reported as the bug ("if I look forward it must not gather"). A battery
				# that packs without aiming is testing a code path the game no longer has.
				_aim_at_snow_below()
				print("[TOOL] Anti-soft-lock setup: packing snow with bare hands at pos %s..." % str(player.global_position))
				player._pack_snowball()
				_change_state(2)

		2:
			# State 2: Wait until the packed snowball is ready in the player's hands
			if player.is_carrying():
				var ball = player.carried
				if ball != null and ball.has_method("packed_mass"):
					_packed_ball_mass = ball.packed_mass()
				else:
					_packed_ball_mass = ball.mass if ball else 1.0
				print("[TOOL] Ball packed in hands: mass = %.3f kg" % _packed_ball_mass)
				_check("player packed and is carrying snowball", player.is_carrying() and ball != null)

				# Throw the snowball into the machine's mouth. Aimed a little above the
				# mouth so the arc drops into it rather than short of it.
				var cur_mach := root.get_node_or_null("DisposalMachine")
				var cur_mach_pos := (cur_mach as Node3D).global_position if cur_mach != null else Vector3(0.0, 0.0, -7.6)
				if player.camera:
					player.camera.look_at(Vector3(0.0, cur_mach_pos.y + MACHINE_MOUTH_Y + 0.35, cur_mach_pos.z), Vector3.UP)
				player._throw_carried()
				print("[TOOL] Threw snowball towards the disposal machine at %s" % str(cur_mach_pos))
				_change_state(3)
			elif _state_time > 2.5:
				_check("player packed and is carrying snowball", false)
				_change_state(3)

		3:
			# State 3: Wait for the ball to reach the machine and for the balance to move
			#
			# KNOWN BLOCKER, measured: the throw never reaches the machine, so this check cannot
			# pass yet. The ball is created and thrown, and then the PLAYGROUND SCENE is loaded
			# on top of the level ("[PG] disposal machine placed at ..." appears in this run's
			# log), which takes the whole tree away with it -- so the ball stops existing and the
			# machine never registers a delivery. That is why this battery used to HANG at
			# `cd2095a` instead of failing: nothing was ever packed, so this state was never
			# reached. It now reaches it, which is progress, and the remaining fault is the scene
			# switch and not the throw or the payout.
			var coins_earned: int = int(player.coins) - _coins_before_delivery
			if coins_earned > 0 or _state_time >= 6.0:
				var expected_coins: int = int(ceil(_packed_ball_mass * DisposalMachineScript.PAYOUT_PER_KG))
				print("[TOOL] Anti-soft-lock result: coins before = %d, coins now = %d, earned = %d (expected %d)" % [
					_coins_before_delivery, player.coins, coins_earned, expected_coins
				])
				_check("anti-soft-lock: coin balance increased from 0 with only hands", coins_earned > 0)
				_check("anti-soft-lock: coins earned matches the machine payout formula", coins_earned == expected_coins)

				_change_state(4)

		4:
			# State 4: Test purchasing API (affordable vs unaffordable)
			print("[TOOL] Testing purchase API...")
			# Grant enough coins to afford shovel (price 50)
			player.coins = 65
			var price_shovel: int = SaveSystem.price("shovel")
			var price_blower: int = SaveSystem.price("blower")
			print("[TOOL] Balance: %d coins. Shovel price: %d, Blower price: %d" % [player.coins, price_shovel, price_blower])

			_check("can afford shovel with 65 coins", player.can_afford("shovel"))
			_check("cannot afford blower (200 coins) with 65 coins", not player.can_afford("blower"))

			# Test unaffordable purchase
			var bought_unaffordable: bool = player.purchase("blower")
			_check("unaffordable purchase fails", not bought_unaffordable)
			_check("unaffordable purchase leaves coins untouched (65)", player.coins == 65)
			_check("unaffordable purchase does not grant blower", not player.is_tool_owned("blower"))
			_check("unaffordable purchase does not grant blower in SaveSystem", not SaveSystem.is_tool_owned("blower"))

			# Test affordable purchase
			var bought_affordable: bool = player.purchase("shovel")
			_check("affordable purchase succeeds", bought_affordable)
			_check("affordable purchase deducts exactly price (65 - 50 = 15)", player.coins == 15)
			_check("affordable purchase grants shovel to player", player.is_tool_owned("shovel"))
			_check("affordable purchase grants shovel in SaveSystem", SaveSystem.is_tool_owned("shovel"))

			# Test persistence across save/load roundtrip
			SaveSystem.save_current()
			SaveSystem.data = {}
			SaveSystem.current_slot = -1
			var reloaded: bool = SaveSystem.load_slot(SCRATCH_SLOT)
			_check("save slot reloaded from disk", reloaded)
			_check("reloaded save keeps hands owned", SaveSystem.is_tool_owned("hands"))
			_check("reloaded save keeps shovel owned", SaveSystem.is_tool_owned("shovel"))
			_check("reloaded save keeps blower unowned", not SaveSystem.is_tool_owned("blower"))
			_check("reloaded save keeps salt unowned", not SaveSystem.is_tool_owned("salt"))
			_check("reloaded save keeps coins (15)", int(SaveSystem.data.get("coins", 0)) == 15)

			# Cleanup scratch save
			SaveSystem.delete_slot(SCRATCH_SLOT)
			SaveSystem.current_slot = -1

			_change_state(5)

		5:
			# State 5: Cycling and tool switching never selects an unowned tool
			print("[TOOL] Testing tool cycling...")
			# Set up player with hands and shovel owned
			player._owned_tools.clear()
			player._owned_tools.append("hands")
			player._owned_tools.append("shovel")
			player.equip_tool("hands")
			_check("equipped hands as starting tool", player.current_tool == player.ToolType.HANDS)

			# Cycle next: should pick shovel
			player.cycle_tool_next()
			_check("cycle next switches to shovel", player.current_tool == player.ToolType.SHOVEL)

			# Cycle next again: blower and salt are unowned, so must wrap back to hands
			player.cycle_tool_next()
			_check("cycle next skips unowned blower/salt and wraps to hands", player.current_tool == player.ToolType.HANDS)

			# Cycle prev: should wrap back to shovel
			player.cycle_tool_prev()
			_check("cycle prev switches to shovel", player.current_tool == player.ToolType.SHOVEL)

			# Direct switch attempts to unowned tools must be rejected
			player._switch_tool(player.ToolType.BLOWER)
			_check("direct switch to unowned blower is rejected", player.current_tool == player.ToolType.SHOVEL)

			player._switch_tool(player.ToolType.SALT)
			_check("direct switch to unowned salt is rejected", player.current_tool == player.ToolType.SHOVEL)

			_change_state(6)

		6:
			# State 6: the Playground grants every tool at start.
			#
			# THIS USED TO INSTANTIATE THE WHOLE PLAYGROUND SCENE, as a child of the level, from
			# inside a physics tick. That is two complete worlds alive at once -- each with its own
			# player, its own snow field and its own GPU simulation -- and the new scene's `_ready`
			# built its own disposal machine and rewired its own player. The damage was not local
			# to this battery: the log of OTHER batteries runs showed "[PG] disposal machine placed
			# at ..." in the middle of a level run, and that is why --tool-ownership could not
			# finish its delivery, why --disposal-machine lost the ball it threw, and why this
			# battery hung instead of failing. It also loads a scene during the physics step, which
			# is the worst moment to be replacing a tree.
			#
			# The property being tested is "the Playground grants all tools at start". That is a
			# contract, and it can be checked WITHOUT building a second world: the scene's own
			# wiring must call `grant_all_tools`, and granting must actually work on a player. Both
			# are checked below.
			_change_state(7)
			print("[TOOL] Testing Playground all-tools ownership (contract, no second world)...")
			var pg_script := ""
			var pg_file := FileAccess.open("res://scripts/playground.gd", FileAccess.READ)
			if pg_file != null:
				pg_script = pg_file.get_as_text()
				pg_file.close()
			_check("the Playground's wiring grants every tool",
				pg_script.contains("grant_all_tools"))

			var fresh: Node = null
			if player.get_script() != null:
				fresh = player.get_script().new()
			if fresh == null:
				_check("a fresh player can be made to test the all-tools grant", false)
				_report()
				return
			add_child(fresh)
			var owned_before: bool = bool(fresh.call("is_tool_owned", "shovel"))
			if fresh.has_method("grant_all_tools"):
				fresh.call("grant_all_tools")
			var all_owned: bool = bool(fresh.call("is_tool_owned", "hands")) \
				and bool(fresh.call("is_tool_owned", "shovel")) \
				and bool(fresh.call("is_tool_owned", "blower")) \
				and bool(fresh.call("is_tool_owned", "salt"))
			var shovel_equipped: bool = int(fresh.get("current_tool")) == int(fresh.get("ToolType").SHOVEL)
			print("[TOOL] fresh player: owned shovel before grant=%s, all owned after=%s, shovel equipped=%s" % [
				str(owned_before), str(all_owned), str(shovel_equipped)])
			_check("a player that has not been granted does not own the shovel", not owned_before)
			_check("granting every tool gives all four", all_owned)
			fresh.queue_free()

			_report()

		7:
			pass

func _change_state(new_state: int) -> void:
	_state = new_state
	_state_time = 0.0

func _check(label: String, ok: bool) -> void:
	print("[TOOL] %s %s" % ["[OK] " if ok else "[FAIL]", label])
	if ok:
		_checks_ok += 1
	else:
		_checks_fail += 1

func _report() -> void:
	if _finished:
		return
	_finished = true
	print("[TOOL] RESULT: %d OK / %d FAIL" % [_checks_ok, _checks_fail])
	print("[TOOL] ==== END ====")
	get_tree().create_timer(0.4).timeout.connect(get_tree().quit)
