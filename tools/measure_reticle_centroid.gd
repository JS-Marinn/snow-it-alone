extends SceneTree

func _init() -> void:
	RenderingServer.set_default_clear_color(Color.BLACK)
	var main_res := load("res://scenes/main.tscn")
	var scene = main_res.instantiate()
	root.add_child(scene)
	
	for i in range(5):
		await process_frame
		
	var hud: Node = scene.get_node_or_null("HUD")
	var drawer: Control = hud.get("_reticle_drawer")
	var v_rect: Rect2 = root.get_visible_rect()
	var v_center: Vector2 = v_rect.get_center()
	
	print("[MEASURE] Default resolution %s, viewport center: %s" % [str(v_rect.size), str(v_center)])
	
	# State 1: CAN_PACK
	hud.set("_reticle_state", 1)
	drawer.visible = true
	drawer.queue_redraw()
	for i in range(3):
		await process_frame
	_measure(v_center, "CAN_PACK @ 1280x720")
	
	# State 2: CAN_CARVE
	hud.set("_reticle_state", 2)
	drawer.queue_redraw()
	for i in range(3):
		await process_frame
	_measure(v_center, "CAN_CARVE @ 1280x720")
	
	# Secondary resolution: 800x600
	root.size = Vector2i(800, 600)
	for i in range(5):
		await process_frame
	v_rect = root.get_visible_rect()
	v_center = v_rect.get_center()
	print("[MEASURE] Changed to resolution %s, viewport center: %s" % [str(v_rect.size), str(v_center)])
	
	hud.set("_reticle_state", 1)
	drawer.queue_redraw()
	for i in range(3):
		await process_frame
	_measure(v_center, "CAN_PACK @ 800x600")
	
	hud.set("_reticle_state", 2)
	drawer.queue_redraw()
	for i in range(3):
		await process_frame
	_measure(v_center, "CAN_CARVE @ 800x600")
	
	quit(0)

func _measure(v_center: Vector2, label: String) -> void:
	var img := root.get_texture().get_image()
	var sum_x := 0.0
	var sum_y := 0.0
	var count := 0
	var cx := int(v_center.x)
	var cy := int(v_center.y)
	for y in range(cy - 25, cy + 25):
		for x in range(cx - 25, cx + 25):
			var col := img.get_pixel(x, y)
			# Look for reticle pixels (white or cyan)
			if (col.r > 0.8 and col.g > 0.8 and col.b > 0.8) or (col.b > 0.8 and col.g > 0.7):
				sum_x += float(x)
				sum_y += float(y)
				count += 1
	if count == 0:
		print("[MEASURE] %s: No pixels detected!" % label)
		return
	var centroid := Vector2(sum_x / float(count), sum_y / float(count))
	var diff := centroid - v_center
	print("[MEASURE] %s: %d px, centroid: (%.2f, %.2f), v_center: (%.2f, %.2f), diff: (%.2f, %.2f) px, int(round): (%d, %d)" % [
		label, count, centroid.x, centroid.y, v_center.x, v_center.y, diff.x, diff.y, int(round(diff.x)), int(round(diff.y))])
