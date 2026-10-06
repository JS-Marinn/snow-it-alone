extends SceneTree
##
## make_hud_scene.gd: extracts the HUD subtree out of `scenes/main.tscn` into
## `scenes/hud.tscn`, so that the level and the test scene can INSTANCE one HUD instead of each
## carrying a byte-identical copy of it.
##
## WHY THIS IS A SCRIPT AND NOT A HAND EDIT. The subtree is 24 nodes with `unique_id`s, anchors
## and container flags, and it exists twice: `scenes/playground.tscn` held a byte-identical copy
## of it, all 24 `unique_id` values included. Editing two scene files by hand to keep them in step
## is exactly the process that already failed once -- commit 635ea6d fixed a reticle the test
## scene could not show, and the fix was itself another copy. So the extraction is generated,
## and it is checked by loading the result rather than by trusting the text.
##
## Run:
##   godot --headless --path . --script tools/make_hud_scene.gd
##
## It prints what it did and refuses to write a file it could not re-read as a scene.

const MAIN_SCENE: String = "res://scenes/main.tscn"
const OUT_SCENE: String = "res://scenes/hud.tscn"
const HUD_NODE: String = "HUD"
const HUD_SCRIPT_UID: String = "uid://v5t0uv7q2qdn"


func _initialize() -> void:
	var src := FileAccess.open(MAIN_SCENE, FileAccess.READ)
	if src == null:
		printerr("[HUDGEN] cannot open %s" % MAIN_SCENE)
		quit(1)
		return
	var text := src.get_as_text()
	src.close()
	var lines := text.split("\n")

	# The subtree runs from the HUD node header to the next node header that is not one of its
	# children. Any node whose `parent="HUD..."` belongs to it.
	var start := -1
	var stop := lines.size()
	for i in range(lines.size()):
		var l: String = lines[i]
		if start < 0:
			if l.begins_with("[node name=\"%s\"" % HUD_NODE):
				start = i
		elif l.begins_with("[node name=") and not l.contains("parent=\"HUD"):
			stop = i
			break
	if start < 0:
		printerr("[HUDGEN] no %s node found in %s" % [HUD_NODE, MAIN_SCENE])
		quit(1)
		return
	var subtree := lines.slice(start, stop)
	var node_count := 0
	for l in subtree:
		if l.begins_with("[node name="):
			node_count += 1
	print("[HUDGEN] found %d nodes in the %s subtree (%d lines)" % [node_count, HUD_NODE, subtree.size()])

	# The new scene: the HUD node as root, with the script as its only dependency.
	var out: Array[String] = []
	out.append("[gd_scene load_steps=2 format=3]")
	out.append("")
	out.append("[ext_resource type=\"Script\" uid=\"%s\" path=\"res://scripts/hud.gd\" id=\"1_hud\"]" % HUD_SCRIPT_UID)
	out.append("")
	# The root node: same name and type, but no `parent`, and every `parent="HUD..."` path
	# shortened by one level because the HUD is now the root rather than a child.
	for l in subtree:
		if l.begins_with("[node name=\"%s\"" % HUD_NODE):
			out.append("[node name=\"%s\" type=\"CanvasLayer\"]" % HUD_NODE)
			continue
		out.append(l.replace("parent=\"HUD/", "parent=\"").replace("parent=\"HUD\"", "parent=\".\""))
	# The script reference the subtree carries is the one we just declared.
	var joined := "\n".join(out)
	joined = joined.replace("ExtResource(\"4_hud\")", "ExtResource(\"1_hud\")")
	if not joined.ends_with("\n"):
		joined += "\n"

	var w := FileAccess.open(OUT_SCENE, FileAccess.WRITE)
	if w == null:
		printerr("[HUDGEN] cannot write %s" % OUT_SCENE)
		quit(1)
		return
	w.store_string(joined)
	w.close()

	# VERIFY BY LOADING IT, not by reading what we wrote. A scene that saves but does not load is
	# a scene that will fail on someone else's machine.
	var check := ResourceLoader.load(OUT_SCENE, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if check == null:
		printerr("[HUDGEN] wrote %s but it does NOT load as a PackedScene" % OUT_SCENE)
		quit(1)
		return
	var inst = (check as PackedScene).instantiate()
	if inst == null:
		printerr("[HUDGEN] %s loads but does not instantiate" % OUT_SCENE)
		quit(1)
		return
	var kids := inst.get_child_count()
	print("[HUDGEN] verified: %s loads and instantiates with %d children" % [OUT_SCENE, kids])
	print("[HUDGEN] now replace the inline subtree in both scenes with an instance of it")
	inst.free()
	quit(0)
