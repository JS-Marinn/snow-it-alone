extends Node

# Save slots for New Game / Continue.
#
# One JSON file per slot under user://saves. The schema is versioned so a later
# build can migrate old files instead of discarding them.

const SLOT_COUNT: int = 3
const SAVE_DIR: String = "user://saves"
const SAVE_VERSION: int = 1

## Placeholder prices for owning each tool (in coins):
const TOOL_PRICES: Dictionary = {
	"hands": 0,
	"shovel": 50, # placeholder
	"blower": 200, # placeholder
	"salt": 500, # placeholder
}

signal slot_changed(slot: int)

## Slot currently in play, or -1 when we are not in a session (demos, tests).
var current_slot: int = -1
var data: Dictionary = {}

func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SAVE_DIR))

static func normalize_tool_name(tool) -> String:
	if tool is int:
		match tool:
			0: return "shovel"
			1: return "blower"
			2: return "salt"
			3: return "hands"
			_: return "hands"
	return str(tool).to_lower().strip_edges()

func price(tool) -> int:
	var tname := normalize_tool_name(tool)
	return int(TOOL_PRICES.get(tname, 0))

func is_tool_owned(tool) -> bool:
	var tname := normalize_tool_name(tool)
	if tname == "hands":
		return true
	var owned: Array = data.get("owned_tools", ["hands"])
	return owned.has(tname)

func can_afford(tool) -> bool:
	var p := price(tool)
	var current_coins: int = int(data.get("coins", 0))
	return current_coins >= p

func grant_tool(tool) -> void:
	var tname := normalize_tool_name(tool)
	var owned: Array = data.get("owned_tools", ["hands"]).duplicate()
	if not owned.has(tname):
		owned.append(tname)
		data["owned_tools"] = owned
		save_current()

func purchase(tool) -> bool:
	var tname := normalize_tool_name(tool)
	if is_tool_owned(tname):
		return true
	var p := price(tool)
	var current_coins: int = int(data.get("coins", 0))
	if current_coins < p:
		return false
	data["coins"] = current_coins - p
	var owned: Array = data.get("owned_tools", ["hands"]).duplicate()
	if not owned.has(tname):
		owned.append(tname)
		data["owned_tools"] = owned
	save_current()
	return true

func slot_path(slot: int) -> String:
	return "%s/slot_%d.json" % [SAVE_DIR, slot]

func slot_exists(slot: int) -> bool:
	return FileAccess.file_exists(slot_path(slot))

## Header for the menu. Never fails: an unreadable file reports as empty.
func slot_info(slot: int) -> Dictionary:
	var info := {
		"slot": slot,
		"exists": false,
		"level_index": 0,
		"cleared_pct": 0.0,
		"coins": 0,
		"playtime": 0.0,
		"updated": 0,
		"owned_tools": ["hands"],
	}
	if not slot_exists(slot):
		return info
	var raw := _read_json(slot)
	if raw.is_empty():
		return info
	info["exists"] = true
	for key in ["level_index", "cleared_pct", "coins", "playtime", "updated", "owned_tools"]:
		if raw.has(key):
			info[key] = raw[key]
	return info

## Starts a fresh run in a slot, overwriting whatever was there.
func new_game(slot: int) -> void:
	data = {
		"version": SAVE_VERSION,
		"slot": slot,
		"created": Time.get_unix_time_from_system(),
		"updated": Time.get_unix_time_from_system(),
		"level_index": 0,
		"cleared_pct": 0.0,
		"best_pct": {},
		"coins": 0,
		"playtime": 0.0,
		"levels_done": 0,
		"owned_tools": ["hands"],
	}
	current_slot = slot
	save_current()
	slot_changed.emit(slot)

## Loads a slot into memory. Returns false if there is nothing usable to load.
func load_slot(slot: int) -> bool:
	if not slot_exists(slot):
		return false
	var raw := _read_json(slot)
	if raw.is_empty():
		return false
	data = raw
	if int(data.get("version", 1)) != SAVE_VERSION:
		data = _migrate(raw)
	if not data.has("owned_tools") or not (data["owned_tools"] is Array):
		data["owned_tools"] = ["hands"]
	current_slot = slot
	slot_changed.emit(slot)
	return true

func save_current() -> void:
	if current_slot < 0:
		return
	data["version"] = SAVE_VERSION
	data["slot"] = current_slot
	data["updated"] = Time.get_unix_time_from_system()
	var file := FileAccess.open(slot_path(current_slot), FileAccess.WRITE)
	if file == null:
		push_error("SaveSystem: cannot write slot %d" % current_slot)
		return
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	slot_changed.emit(current_slot)

func delete_slot(slot: int) -> void:
	if slot_exists(slot):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(slot_path(slot)))
	if slot == current_slot:
		current_slot = -1
		data = {}
	slot_changed.emit(slot)

func has_any_slot() -> bool:
	for slot in range(SLOT_COUNT):
		if slot_exists(slot):
			return true
	return false

## Most recently written slot, so Continue resumes where the player left off.
func latest_slot() -> int:
	var best := -1
	var best_time := -1
	for slot in range(SLOT_COUNT):
		var info := slot_info(slot)
		if info["exists"] and int(info["updated"]) > best_time:
			best_time = int(info["updated"])
			best = slot
	return best

## Records the outcome of a finished level and persists it right away.
func record_result(cleared_pct: float, coins: int, level_index: int = 0) -> void:
	if current_slot < 0:
		return
	var best: Dictionary = data.get("best_pct", {})
	var key := str(level_index)
	if cleared_pct > float(best.get(key, 0.0)):
		best[key] = cleared_pct
	data["best_pct"] = best
	data["level_index"] = maxi(int(data.get("level_index", 0)), level_index)
	data["cleared_pct"] = maxf(float(data.get("cleared_pct", 0.0)), cleared_pct)
	data["coins"] = int(data.get("coins", 0)) + coins
	if cleared_pct >= 90.0:
		data["levels_done"] = int(data.get("levels_done", 0)) + 1
	save_current()

func add_playtime(seconds: float) -> void:
	if current_slot < 0 or seconds <= 0.0:
		return
	data["playtime"] = float(data.get("playtime", 0.0)) + seconds

func _read_json(slot: int) -> Dictionary:
	var file := FileAccess.open(slot_path(slot), FileAccess.READ)
	if file == null:
		return {}
	var text := file.get_as_text()
	file.close()
	var parsed = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_warning("SaveSystem: slot %d is not valid JSON, ignoring it" % slot)
		return {}
	return parsed

## Placeholder for older schemas. For now a missing version just means "oldest".
func _migrate(raw: Dictionary) -> Dictionary:
	var migrated := raw
	migrated["version"] = SAVE_VERSION
	if not migrated.has("best_pct"):
		migrated["best_pct"] = {}
	if not migrated.has("playtime"):
		migrated["playtime"] = 0.0
	if not migrated.has("owned_tools"):
		migrated["owned_tools"] = ["hands"]
	return migrated

## Formats a slot header for the menu.
func slot_label(slot: int, level_names: Array = []) -> String:
	var info := slot_info(slot)
	if not info["exists"]:
		return tr("MENU_SLOT_EMPTY") % (slot + 1)
	var level_index := int(info["level_index"])
	var level_name := tr("MENU_LEVEL_N") % (level_index + 1)
	if level_index < level_names.size():
		level_name = String(level_names[level_index])
	var minutes := int(float(info["playtime"]) / 60.0)
	return tr("MENU_SLOT_DETAILS") % [
		slot + 1, level_name, int(float(info["cleared_pct"])), int(info["coins"]), minutes]
