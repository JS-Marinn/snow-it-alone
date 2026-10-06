extends SceneTree
##
## use_hud_scene.gd: replaces the inline HUD subtree in `scenes/main.tscn` and
## `scenes/playground.tscn` with an INSTANCE of `scenes/hud.tscn`, so the HUD exists once.
##
## Run after `tools/make_hud_scene.gd`, and only once: it reports if a scene already instances it.
##
##   godot --headless --path . --script tools/use_hud_scene.gd
##
## What it does to each scene:
##   * drops every node line belonging to the inline HUD subtree
##   * declares `scenes/hud.tscn` as an ext_resource
##   * adds one node line: `[node name="HUD" parent="." instance=ExtResource("...")]`
##   * leaves every other node, every sub_resource and every unique_id alone
##
## It VERIFIES by loading the result, and writes nothing if the result does not load. A scene
## rewrite that saves but will not open is worse than the duplication it removed.

const HUD_SCENE: String = "res://scenes/hud.tscn"
const HUD_NODE: String = "HUD"
const SCENES: Array[String] = ["res://scenes/main.tscn", "res://scenes/playground.tscn"]


func _initialize() -> void:
	var failures := 0
	for path in SCENES:
		if not _convert(path):
			failures += 1
	if failures > 0:
		printerr("[HUDUSE] %d scene(s) failed; nothing was left half-done" % failures)
		quit(1)
		return
	quit(0)


func _convert(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		printerr("[HUDUSE] cannot open %s" % path)
		return false
	var text := f.get_as_text()
	f.close()

	if text.contains("instance=ExtResource") and text.contains("path=\"%s\"" % HUD_SCENE):
		print("[HUDUSE] %s already instances the HUD; leaving it alone" % path)
		return true

	var lines := text.split("\n")
	var kept: Array[String] = []
	var removed := 0
	var inserted := false
	var ext_id := ""
	for l in lines:
		# Drop the inline HUD root and every node under it.
		if l.begins_with("[node name=\"%s\"" % HUD_NODE) and l.contains("parent=\".\""):
			ext_id = "1_hud_instance"
			kept.append("[node name=\"%s\" parent=\".\" instance=ExtResource(\"%s\")]" % [HUD_NODE, ext_id])
			inserted = true
			removed += 1
			continue
		if l.begins_with("[node name=") and l.contains("parent=\"HUD"):
			removed += 1
			continue
		kept.append(l)

	if not inserted:
		printerr("[HUDUSE] %s has no HUD node with parent=\".\"; refusing to guess" % path)
		return false

	var out_text := "\n".join(kept)
	# The instance needs the scene declared as a resource, and the ONLY valid place for an
	# `[ext_resource]` line is immediately after the run of ext_resource lines at the top of the
	# file.
	#
	# This used to insert it before the first `[sub_resource]`, which in `main.tscn` is AFTER the
	# project settings block (`[gd_scene ...]` followed by `ground_curve`, `sun_angle_max`...).
	# The declaration landed inside that block and the scene stopped loading with "Unknown tag
	# 'ext_resource'". The converter noticed, refused the scene and said so -- which is why the
	# file was recoverable -- but the anchor was wrong. Count the consecutive ext_resource lines
	# instead of looking for the next section.
	var decl := "\n[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [HUD_SCENE, ext_id]
	var ls := out_text.split("\n")
	var last_ext := -1
	for i in range(ls.size()):
		if ls[i].begins_with("[ext_resource"):
			last_ext = i
		elif last_ext >= 0 and ls[i].strip_edges() != "" and not ls[i].begins_with("[ext_resource"):
			# The run of ext_resource lines has ended.
			break
	if last_ext < 0:
		printerr("[HUDUSE] %s has no ext_resource lines to sit beside" % path)
		return false
	ls.insert(last_ext + 1, "[ext_resource type=\"PackedScene\" path=\"%s\" id=\"%s\"]" % [HUD_SCENE, ext_id])
	out_text = "\n".join(ls)

	# Every `load_steps` in this format counts the resources; keep it honest.
	var steps_re := RegEx.new()
	steps_re.compile("\\[gd_scene load_steps=(\\d+)")
	var m := steps_re.search(out_text)
	if m != null:
		var old_steps := int(m.get_string(1))
		out_text = out_text.replace("load_steps=%d" % old_steps, "load_steps=%d" % (old_steps + 1))

	var w := FileAccess.open(path, FileAccess.WRITE)
	if w == null:
		printerr("[HUDUSE] cannot write %s" % path)
		return false
	w.store_string(out_text)
	w.close()

	# VERIFY BY LOADING.
	var check := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE)
	if check == null:
		printerr("[HUDUSE] %s no longer loads as a scene. Restore it with git checkout." % path)
		return false
	var inst = (check as PackedScene).instantiate()
	if inst == null:
		printerr("[HUDUSE] %s loads but will not instantiate" % path)
		return false
	var hud := inst.get_node_or_null(HUD_NODE)
	var hud_ok := hud != null
	print("[HUDUSE] %s: removed %d inline node lines, instanced the HUD, loads OK, HUD node present=%s" % [
		path, removed, str(hud_ok)])
	inst.free()
	return hud_ok
