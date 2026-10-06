extends RefCounted

# CelShadingSystem: Global cel shading manager.
# Replaces materials on all MeshInstance3D nodes in the game with toon materials,
# while preserving original albedo textures (atlas colormaps) and colors.
# Also controls toon lighting mode on the heightmap snow field.

static var cel_shading_enabled: bool = true
static var _toon_shader: Shader = preload("res://materials/toon.gdshader")
static var _material_cache: Dictionary = {}
static var _original_materials: Dictionary = {}
static var _snow_material: ShaderMaterial = null
static var _world_env: WorldEnvironment = null
static var _orig_glow_intensity: float = 0.35
static var _orig_glow_bloom: float = 0.12
static var _orig_ambient_energy: float = 1.1

# Default artistic direction parameters
static var default_bands: int = 3
static var default_band_softness: float = 0.05
static var default_shadow_tint: Color = Color(0.68, 0.74, 0.88)
static var default_rim_strength: float = 0.75
static var default_rim_color: Color = Color(1.0, 0.92, 0.80)
static var default_outline_width: float = 0.006
static var default_outline_color: Color = Color(0.12, 0.16, 0.28, 1.0)

## Traverses root_node and applies cel shading across all MeshInstance3Ds.
static func apply_cel_shading(root_node: Node) -> void:
	if root_node == null:
		return
	_find_world_environment(root_node)
	_sweep_and_apply(root_node)
	_update_environment()

## Recursively finds and replaces materials on all eligible MeshInstance3Ds.
static func _sweep_and_apply(node: Node) -> void:
	# Skip particle systems (billboards / unshaded flakes)
	if node is CPUParticles3D or node is GPUParticles3D:
		return

	if node is MeshInstance3D:
		_process_mesh_instance(node as MeshInstance3D)

	for child in node.get_children():
		_sweep_and_apply(child)

## Replaces material on a single MeshInstance3D, saving original state.
static func _process_mesh_instance(mesh_inst: MeshInstance3D) -> void:
	# Skip if flake or particle billboard
	if mesh_inst.name.begins_with("Flake") or (mesh_inst.mesh and mesh_inst.mesh.resource_name.contains("flake")):
		return

	# Handle the snow field deformation mesh
	if mesh_inst.material_override is ShaderMaterial:
		var sm := mesh_inst.material_override as ShaderMaterial
		if sm.shader and sm.shader.resource_path.contains("snow_deform"):
			_snow_material = sm
			sm.set_shader_parameter("toon_enabled", cel_shading_enabled)
			sm.set_shader_parameter("bands", default_bands)
			sm.set_shader_parameter("band_softness", default_band_softness)
			sm.set_shader_parameter("shadow_tint", default_shadow_tint)
			sm.set_shader_parameter("rim_strength", default_rim_strength)
			sm.set_shader_parameter("rim_color", default_rim_color)
			sm.set_shader_parameter("outline_width", default_outline_width)
			sm.set_shader_parameter("outline_color", default_outline_color)
			return

	var inst_id := mesh_inst.get_instance_id()
	if not _original_materials.has(inst_id):
		_original_materials[inst_id] = {
			"override": mesh_inst.material_override,
			"surfaces": {}
		}

	# 1. Check material_override
	if mesh_inst.material_override != null:
		var orig = _original_materials[inst_id]["override"]
		if orig is StandardMaterial3D or orig is BaseMaterial3D:
			# Skip unshaded particles
			if orig.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
				return
			if cel_shading_enabled:
				mesh_inst.material_override = _get_or_create_toon_material(orig)
			else:
				mesh_inst.material_override = orig
		return

	# 2. Check mesh surface materials
	if mesh_inst.mesh != null:
		var sc: int = mesh_inst.mesh.get_surface_count()
		for i in range(sc):
			var orig = _original_materials[inst_id]["surfaces"].get(i, null)
			if orig == null:
				orig = mesh_inst.get_surface_override_material(i)
				if orig == null:
					orig = mesh_inst.mesh.surface_get_material(i)
				_original_materials[inst_id]["surfaces"][i] = orig

			if orig is StandardMaterial3D or orig is BaseMaterial3D:
				if orig.shading_mode == BaseMaterial3D.SHADING_MODE_UNSHADED:
					continue
				if cel_shading_enabled:
					mesh_inst.set_surface_override_material(i, _get_or_create_toon_material(orig))
				else:
					mesh_inst.set_surface_override_material(i, null)

## Helper to apply cel shading to a single node and descendants (e.g. dynamic snowballs).
static func apply_to_node(node: Node) -> void:
	if node == null:
		return
	_sweep_and_apply(node)

## Creates or retrieves a cached toon ShaderMaterial from a StandardMaterial3D source.
static func _get_or_create_toon_material(orig: Material) -> ShaderMaterial:
	var key: int = orig.get_instance_id()
	if _material_cache.has(key):
		return _material_cache[key]

	var toon_mat := ShaderMaterial.new()
	toon_mat.shader = _toon_shader

	if orig is StandardMaterial3D or orig is BaseMaterial3D:
		toon_mat.set_shader_parameter("albedo_color", orig.albedo_color)
		toon_mat.set_shader_parameter("albedo_texture", orig.albedo_texture)
		toon_mat.set_shader_parameter("roughness", orig.roughness)
		toon_mat.set_shader_parameter("metallic", orig.metallic)
		if orig.emission_enabled:
			toon_mat.set_shader_parameter("emission", orig.emission)
			toon_mat.set_shader_parameter("emission_energy", orig.emission_energy_multiplier)

	toon_mat.set_shader_parameter("toon_enabled", cel_shading_enabled)
	toon_mat.set_shader_parameter("bands", default_bands)
	toon_mat.set_shader_parameter("band_softness", default_band_softness)
	toon_mat.set_shader_parameter("shadow_tint", default_shadow_tint)
	toon_mat.set_shader_parameter("rim_strength", default_rim_strength)
	toon_mat.set_shader_parameter("rim_color", default_rim_color)
	toon_mat.set_shader_parameter("outline_width", default_outline_width)
	toon_mat.set_shader_parameter("outline_color", default_outline_color)

	_material_cache[key] = toon_mat
	return toon_mat

## Toggles cel shading state on and off, updating materials and environment.
static func set_cel_shading_enabled(is_on: bool, root_node: Node = null) -> void:
	cel_shading_enabled = is_on
	if _snow_material != null:
		_snow_material.set_shader_parameter("toon_enabled", is_on)

	for mat in _material_cache.values():
		if mat is ShaderMaterial:
			mat.set_shader_parameter("toon_enabled", is_on)

	if root_node != null:
		_sweep_and_apply(root_node)

	_update_environment()

## Configures specific parameters for bisection / diagnostics.
static func configure_bisect(snow_toon: bool, obj_toon: bool, obj_bands: int, outline_w: float, root_node: Node = null) -> void:
	cel_shading_enabled = obj_toon or snow_toon
	if _snow_material != null:
		_snow_material.set_shader_parameter("toon_enabled", snow_toon)
		_snow_material.set_shader_parameter("outline_width", outline_w)

	for mat in _material_cache.values():
		if mat is ShaderMaterial:
			mat.set_shader_parameter("toon_enabled", obj_toon)
			mat.set_shader_parameter("bands", obj_bands)
			mat.set_shader_parameter("outline_width", outline_w)

	if root_node != null:
		_sweep_and_apply(root_node)

	_update_environment()

static func _find_world_environment(root: Node) -> void:
	if _world_env != null and is_instance_valid(_world_env):
		return
	if root is WorldEnvironment:
		_world_env = root
		return
	for child in root.get_children():
		_find_world_environment(child)
		if _world_env != null:
			return

static func _update_environment() -> void:
	if _world_env == null or not is_instance_valid(_world_env) or _world_env.environment == null:
		return
	var env := _world_env.environment
	if cel_shading_enabled:
		# Reduced glow and balanced ambient energy for crisp toon bands and shadows
		env.glow_enabled = false
		env.glow_intensity = 0.0
		env.ambient_light_energy = 0.65
	else:
		env.glow_enabled = true
		env.glow_intensity = _orig_glow_intensity
		env.glow_bloom = _orig_glow_bloom
		env.ambient_light_energy = _orig_ambient_energy

## Verifies that all MeshInstance3Ds preserved their textures and equivalent colors.
static func verify_material_preservation(root_node: Node) -> Dictionary:
	var res := {
		"ok": true,
		"checked_count": 0,
		"textured_count": 0,
		"errors": []
	}
	_verify_recursive(root_node, res)
	return res

static func _verify_recursive(node: Node, res: Dictionary) -> void:
	if node is CPUParticles3D or node is GPUParticles3D:
		return

	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var inst_id := mesh_inst.get_instance_id()
		if _original_materials.has(inst_id):
			var orig_data: Dictionary = _original_materials[inst_id]
			# Check override
			var orig_over = orig_data.get("override", null)
			if orig_over is StandardMaterial3D or orig_over is BaseMaterial3D:
				_check_match(mesh_inst.name, mesh_inst.material_override, orig_over, res)

			# Check surfaces
			var surf_dict: Dictionary = orig_data.get("surfaces", {})
			for s_idx in surf_dict:
				var orig_surf = surf_dict[s_idx]
				if orig_surf is StandardMaterial3D or orig_surf is BaseMaterial3D:
					var active = mesh_inst.get_surface_override_material(s_idx)
					_check_match(mesh_inst.name + "[s%d]" % s_idx, active, orig_surf, res)

	for child in node.get_children():
		_verify_recursive(child, res)

static func _check_match(label: String, active: Material, orig: BaseMaterial3D, res: Dictionary) -> void:
	res["checked_count"] += 1
	if not (active is ShaderMaterial):
		res["ok"] = false
		res["errors"].append("%s: active material is not ShaderMaterial (%s)" % [label, str(active)])
		return

	var sm := active as ShaderMaterial
	# Check texture preservation
	if orig.albedo_texture != null:
		res["textured_count"] += 1
		var active_tex = sm.get_shader_parameter("albedo_texture")
		if active_tex != orig.albedo_texture:
			res["ok"] = false
			res["errors"].append("%s: lost albedo_texture! expected %s, got %s" % [
				label, str(orig.albedo_texture), str(active_tex)])

	# Check color preservation
	var active_col = sm.get_shader_parameter("albedo_color")
	if active_col is Color:
		var c_diff: float = absf(active_col.r - orig.albedo_color.r) + absf(active_col.g - orig.albedo_color.g) + absf(active_col.b - orig.albedo_color.b)
		if c_diff > 0.02:
			res["ok"] = false
			res["errors"].append("%s: albedo_color mismatch! expected %s, got %s (diff=%.4f)" % [
				label, str(orig.albedo_color), str(active_col), c_diff])
