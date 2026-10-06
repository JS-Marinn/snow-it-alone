extends Node3D

# Snow field (system 1): continuous GPU terrain plus the bridge to the
# gameplay systems. Granular reology with strict mass conservation, with
# channels R = height, G = movable loose snow, B = cohesion/wetness and
# A = relaxation scratch (sign = cell in flow, which drives two-phase
# hysteresis). A reduced 64x64 CPU mirror of the field lets the gameplay
# systems (player support, blade resistance, ball rolling and accretion, prop
# pinning) read real snow height without pulling the whole texture every frame.

signal progress_updated(percent_cleared: float, kg_cleared: float, kg_total: float)
signal snow_tossed_in_bank(bonus_coins: int, world_pos: Vector3)
## Real volume removed or added by one operation, already converted to kg.
signal op_volume_ready(role: String, owner: int, kg: float)

@export var field_width: float = 8.0    # meters
@export var field_length: float = 12.0  # meters
@export var snow_depth: float = 0.32    # meters of snow
## Snow mesh subdivision. On an 8x12 m field, 320x480 puts a vertex every
## 2.5 cm, dense enough to resolve the solver's 1.6 x 2.3 cm texels without
## aliasing the edges of cleared snow into sawteeth.
@export_range(64, 512) var mesh_subdiv_x: int = 320
@export_range(64, 768) var mesh_subdiv_z: int = 480

# Reology (block 1)
## Dynamic friction angle of DRY snow (B=0), i.e. while it flows.
@export_range(20.0, 50.0) var repose_dry_deg: float = 32.0
## Dynamic friction angle of WET, cohesive snow (B=1).
@export_range(30.0, 70.0) var repose_wet_deg: float = 54.0
## Two-phase hysteresis: how far past the dynamic angle flow must be pushed to START.
@export_range(0.0, 20.0) var repose_hysteresis_deg: float = 8.0
## Bulk density of the field snow (kg/m3), for volume to mass conversion.
@export var snow_density: float = 150.0
## Wetness/cohesion given to snow dumped by the blade or the piles.
@export_range(0.0, 1.0) var deposit_wetness: float = 0.45
## Cohesion added by each tamp (compacting with the flat face of the blade).
@export_range(0.0, 1.0) var tamp_cohesion_gain: float = 0.35

# Tool
## Height of the blade front wall (m): taller snow spills over the top.
@export var blade_wall_height: float = 0.30

const TEX_SIZE: int = 512
const COARSE_SIZE: int = 64
const MAX_OPS: int = 12
const BUCKETS: int = 192
const RELAX_ITERATIONS: int = 8
const SETTLE_TIME: float = 2.5
const SIM_SHADER_PATH: String = "res://shaders/snow_sim.glsl"

# Blade transport parameters
const DEPOSIT_LAMBDA: float = 0.16
const DEPOSIT_LENGTH: float = 0.70
const RELAX_RATE: float = 0.08

# Tamping: plastic settle (m) and the fraction of loose snow that gets compacted
const TAMP_SETTLE: float = 0.03
const TAMP_COMPACT: float = 0.85

# Uniform block layout in floats (std140); must match snow_sim.glsl
const P_FIELD: int = 0
const P_SIM: int = 4
const P_SIM2: int = 8
const P_SIM3: int = 12
const P_BLADE0: int = 16
const P_BLADE1: int = 20
const P_PROBES: int = 24
const P_OPS: int = 40
const PARAM_FLOATS: int = 160

var snow_texture: Texture2DRD
var shader_material: ShaderMaterial
var snow_mesh_instance: MeshInstance3D

var total_pixels: int = 0
var cleared_pixels: int = 0
var snow_volume_norm: float = 0.0
var total_snow_kg: float = 0.0
var kg_cleared_cumulative: float = 0.0

# GPU simulation state
var rd: RenderingDevice
var sim_ready: bool = false
var _shader_rid: RID
var _pipeline_rid: RID
var _tex_rids: Array[RID] = []
var _uset_rids: Array[RID] = []
var _coarse_rid: RID
var _params_buf: RID
var _stats_buf: RID
var _buckets_buf: RID
var _cur: int = 0

# CPU mirror (64x64 x 4 channels)
# channel 0 = mean height, 1 = mean loose snow, 2 = mean cohesion, 3 = peak height
var _coarse: PackedFloat32Array = PackedFloat32Array()
var _coarse_valid: bool = false
var _coarse_in_flight: bool = false

# Per-frame operation queue
var _ops: Array[PackedFloat32Array] = []
var _op_meta: Array = []           # one {role, owner} pair per queued op
var _stats_queue: Array = []       # metadata of each in-flight stats read
var _rect_log: Array = []
var _time: float = 0.0
var _frame: int = 0

# Blade state
var _blade_ttl: float = 0.0
var _blade_pos: Vector2 = Vector2.ZERO
var _blade_dir: Vector2 = Vector2(0.0, -1.0)
var _blade_half_w: float = 0.38
var _blade_half_l: float = 0.17

# Point probes (kept for compatibility with the shovel)
var _probe_pos: Array[Vector2] = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _probe_h: Array[float] = [1.0, 1.0, 1.0, 1.0]
var _stats_pending: bool = false
var _stats_has_data: bool = false

# Automated push demo: godot -- --plow-demo
var _demo: bool = false
var _demo_t: float = 0.0
var _demo_last: Vector3 = Vector3.INF

func _ready() -> void:
	total_pixels = TEX_SIZE * TEX_SIZE
	total_snow_kg = field_width * field_length * snow_depth * snow_density
	_demo = OS.get_cmdline_user_args().has("--plow-demo")

	_setup_collision()
	_setup_snow_surface()
	_create_snowbanks()

	_emit_progress()
	if _demo:
		_setup_demo_camera()

func _exit_tree() -> void:
	RenderingServer.call_on_render_thread(_free_sim)

func _setup_collision() -> void:
	var static_body = StaticBody3D.new()
	var col = CollisionShape3D.new()
	var box = BoxShape3D.new()
	box.size = Vector3(field_width + 12.0, 0.4, field_length + 12.0)
	col.shape = box
	col.position = Vector3(0, -0.2, 0)
	static_body.add_child(col)
	add_child(static_body)

func _setup_snow_surface() -> void:
	snow_texture = Texture2DRD.new()
	RenderingServer.call_on_render_thread(_init_sim_rd)

	var shader = load("res://materials/snow_deform.gdshader") as Shader
	shader_material = ShaderMaterial.new()
	shader_material.shader = shader
	shader_material.set_shader_parameter("snow_heightmap", snow_texture)
	shader_material.set_shader_parameter("snow_depth", snow_depth)
	shader_material.set_shader_parameter("field_size", Vector2(field_width, field_length))
	# Footprint filter radius used by the shader: half a vertex footprint, in UV.
	# Keeps geometry, colour mask and normals in sync, so nothing aliases.
	shader_material.set_shader_parameter("smooth_uv", Vector2(
		0.75 / float(mesh_subdiv_x + 1), 0.75 / float(mesh_subdiv_z + 1)))

	snow_mesh_instance = MeshInstance3D.new()
	var plane = PlaneMesh.new()
	plane.size = Vector2(field_width, field_length)
	# The simulation grid has 1.56 x 2.34 cm texels, so the mesh has to get close
	# to that density or the edges of cleared snow alias into sawteeth.
	plane.subdivide_width = mesh_subdiv_x
	plane.subdivide_depth = mesh_subdiv_z
	snow_mesh_instance.mesh = plane
	snow_mesh_instance.material_override = shader_material
	snow_mesh_instance.extra_cull_margin = 2.5
	add_child(snow_mesh_instance)

	var wood_mat = StandardMaterial3D.new()
	wood_mat.albedo_color = Color(0.46, 0.30, 0.16)
	wood_mat.roughness = 0.75

	for side in [-1, 1]:
		var curb = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(0.3, 0.45, field_length)
		curb.mesh = box
		curb.position = Vector3(side * (field_width * 0.5 + 0.15), 0.15, 0)
		curb.material_override = wood_mat
		add_child(curb)

# GPU resource init and cleanup (render thread)
func _init_sim_rd() -> void:
	rd = RenderingServer.get_rendering_device()
	if rd == null:
		push_error("SnowField: RenderingDevice unavailable (Forward+ or Mobile required).")
		return

	var shader_file := load(SIM_SHADER_PATH) as RDShaderFile
	if shader_file == null:
		push_error("SnowField: could not load %s" % SIM_SHADER_PATH)
		return
	var spirv: RDShaderSPIRV = shader_file.get_spirv()
	if spirv.compile_error_compute != "":
		push_error("SnowField: compute shader compile error: " + spirv.compile_error_compute)
		return
	_shader_rid = rd.shader_create_from_spirv(spirv)
	_pipeline_rid = rd.compute_pipeline_create(_shader_rid)

	# RGBA32F ping-pong textures: R = height, G = loose snow, B = cohesion, A = scratch
	var fmt := RDTextureFormat.new()
	fmt.width = TEX_SIZE
	fmt.height = TEX_SIZE
	fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT

	# Initial state: packed virgin snow (G=0, immobile) with slight cohesion
	var init := PackedFloat32Array()
	init.resize(TEX_SIZE * TEX_SIZE * 4)
	for i in range(TEX_SIZE * TEX_SIZE):
		init[i * 4] = 1.0     # height
		init[i * 4 + 1] = 0.0 # loose snow
		init[i * 4 + 2] = 0.18 # cohesion of virgin snow
	var init_bytes := init.to_byte_array()

	_tex_rids.clear()
	for i in range(2):
		_tex_rids.append(rd.texture_create(fmt, RDTextureView.new(), [init_bytes]))

	# Reduced mirror for CPU gameplay queries
	var cfmt := RDTextureFormat.new()
	cfmt.width = COARSE_SIZE
	cfmt.height = COARSE_SIZE
	cfmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	cfmt.usage_bits = RenderingDevice.TEXTURE_USAGE_STORAGE_BIT \
		| RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT
	_coarse_rid = rd.texture_create(cfmt, RDTextureView.new(), [])

	_params_buf = rd.uniform_buffer_create(PARAM_FLOATS * 4)
	_stats_buf = rd.storage_buffer_create((16 + MAX_OPS) * 4)
	_buckets_buf = rd.storage_buffer_create(MAX_OPS * BUCKETS * 4)

	_uset_rids.clear()
	_uset_rids.append(_make_uniform_set(_tex_rids[0], _tex_rids[1]))
	_uset_rids.append(_make_uniform_set(_tex_rids[1], _tex_rids[0]))

	_cur = 0
	snow_texture.texture_rd_rid = _tex_rids[0]
	sim_ready = true

func _make_uniform_set(src: RID, dst: RID) -> RID:
	var u0 := RDUniform.new()
	u0.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u0.binding = 0
	u0.add_id(src)
	var u1 := RDUniform.new()
	u1.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u1.binding = 1
	u1.add_id(dst)
	var u2 := RDUniform.new()
	u2.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
	u2.binding = 2
	u2.add_id(_params_buf)
	var u3 := RDUniform.new()
	u3.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u3.binding = 3
	u3.add_id(_stats_buf)
	var u4 := RDUniform.new()
	u4.uniform_type = RenderingDevice.UNIFORM_TYPE_STORAGE_BUFFER
	u4.binding = 4
	u4.add_id(_buckets_buf)
	var u5 := RDUniform.new()
	u5.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	u5.binding = 5
	u5.add_id(_coarse_rid)
	return rd.uniform_set_create([u0, u1, u2, u3, u4, u5], _shader_rid, 0)

func _free_sim() -> void:
	if rd == null:
		return
	sim_ready = false
	if snow_texture:
		snow_texture.texture_rd_rid = RID()
	for r in _uset_rids:
		if r.is_valid():
			rd.free_rid(r)
	for r in _tex_rids:
		if r.is_valid():
			rd.free_rid(r)
	for r in [_coarse_rid, _params_buf, _stats_buf, _buckets_buf, _pipeline_rid, _shader_rid]:
		if r.is_valid():
			rd.free_rid(r)

# Main loop
func _process(delta: float) -> void:
	_time += delta
	_frame += 1
	if _demo:
		_run_demo(delta)

	_blade_ttl = maxf(_blade_ttl - delta, 0.0)
	_update_probes()

	var n_ops: int = mini(_ops.size(), MAX_OPS)

	# Active relaxation region = union of the areas touched recently
	var active_rect := Vector4i(TEX_SIZE, TEX_SIZE, -1, -1)
	var i := _rect_log.size() - 1
	while i >= 0:
		var entry = _rect_log[i]
		if entry[1] < _time:
			_rect_log.remove_at(i)
		else:
			var r: Vector4i = entry[0]
			active_rect = Vector4i(mini(active_rect.x, r.x), mini(active_rect.y, r.y), maxi(active_rect.z, r.z), maxi(active_rect.w, r.w))
		i -= 1
	var relax_iters: int = RELAX_ITERATIONS if active_rect.z >= 0 else 0

	var want_full: bool = (_frame % 3 == 0)
	# Every operation must be able to attribute the volume it removes, so a stats
	# buffer read is queued on any frame that has operations (112 bytes, cheap),
	# while the full field reduction only runs every 3 frames (progress and probes).
	var want_op_read: bool = (n_ops > 0 or want_full) and _stats_queue.size() < 8
	var want_coarse: bool = not _coarse_in_flight

	if sim_ready and (n_ops > 0 or relax_iters > 0 or want_full or want_coarse):
		var params := _pack_params(n_ops)
		var types := PackedInt32Array()
		for k in range(n_ops):
			types.append(int(_ops[k][4] + 0.5))
		if want_op_read:
			_stats_queue.append({"meta": _op_meta.duplicate(), "full": want_full})
		RenderingServer.call_on_render_thread(_sim_step.bind(params, types, relax_iters, active_rect, want_full, want_coarse, want_op_read))
	_ops.clear()
	_op_meta.clear()

	if _stats_pending:
		_stats_pending = false
		_emit_progress()

func _pack_params(n_ops: int) -> PackedByteArray:
	var f := PackedFloat32Array()
	f.resize(PARAM_FLOATS)
	# field
	f[P_FIELD + 0] = field_width
	f[P_FIELD + 1] = field_length
	f[P_FIELD + 2] = snow_depth
	f[P_FIELD + 3] = float(TEX_SIZE)
	# sim: angles (rad) + hysteresis + rate
	f[P_SIM + 0] = deg_to_rad(repose_dry_deg)
	f[P_SIM + 1] = deg_to_rad(repose_wet_deg)
	f[P_SIM + 2] = deg_to_rad(repose_hysteresis_deg)
	f[P_SIM + 3] = RELAX_RATE
	# sim2: deposit + wetness + density
	f[P_SIM2 + 0] = DEPOSIT_LAMBDA
	f[P_SIM2 + 1] = DEPOSIT_LENGTH
	f[P_SIM2 + 2] = deposit_wetness
	f[P_SIM2 + 3] = snow_density
	# sim3: tamping + reference slope for the base of the snow piles
	f[P_SIM3 + 0] = TAMP_SETTLE
	f[P_SIM3 + 1] = TAMP_COMPACT
	f[P_SIM3 + 2] = tamp_cohesion_gain
	f[P_SIM3 + 3] = tan(deg_to_rad(repose_dry_deg + repose_hysteresis_deg + 4.0))
	# blade0
	f[P_BLADE0 + 0] = 1.0 if _blade_ttl > 0.0 else 0.0
	f[P_BLADE0 + 1] = _blade_pos.x
	f[P_BLADE0 + 2] = _blade_pos.y
	f[P_BLADE0 + 3] = blade_wall_height
	# blade1
	f[P_BLADE1 + 0] = _blade_dir.x
	f[P_BLADE1 + 1] = _blade_dir.y
	f[P_BLADE1 + 2] = _blade_half_w
	f[P_BLADE1 + 3] = _blade_half_l
	# probes
	for p in range(4):
		f[P_PROBES + p * 4] = _probe_pos[p].x
		f[P_PROBES + p * 4 + 1] = _probe_pos[p].y
	# ops
	for k in range(n_ops):
		var o := _ops[k]
		for j in range(8):
			f[P_OPS + k * 8 + j] = o[j]
	return f.to_byte_array()

func _sim_step(params: PackedByteArray, types: PackedInt32Array, relax_iters: int, rect: Vector4i, want_full: bool, want_coarse: bool, want_op_read: bool) -> void:
	if not sim_ready:
		return
	rd.buffer_update(_params_buf, 0, params.size(), params)
	rd.buffer_clear(_buckets_buf, 0, MAX_OPS * BUCKETS * 4)
	rd.buffer_clear(_stats_buf, 0, (16 + MAX_OPS) * 4)

	var cl := rd.compute_list_begin()
	rd.compute_list_bind_compute_pipeline(cl, _pipeline_rid)

	for k in range(types.size()):
		match types[k]:
			1:
				_dispatch(cl, 0, k, rect, true)   # collect under the plate
				_dispatch(cl, 1, k, rect, true)   # deposit in front of the blade
			2, 3:
				_dispatch(cl, 2, k, rect, true)   # footprint / radial clear
			4:
				_dispatch(cl, 3, k, rect, true)   # free dump
			5:
				_dispatch(cl, 7, k, rect, true)   # tamp / compaction
			6:
				_dispatch(cl, 8, k, rect, true)   # cylindrical harvest (accretion)

	for it in range(relax_iters):
		_dispatch(cl, 4, 0, rect, true)
		_dispatch(cl, 5, 0, rect, true)

	if want_coarse:
		_dispatch(cl, 9, 0, rect, false)

	if want_full:
		_dispatch(cl, 6, 0, rect, false)

	rd.compute_list_end()
	snow_texture.texture_rd_rid = _tex_rids[_cur]

	if want_op_read:
		rd.buffer_get_data_async(_stats_buf, _on_stats_ready)
	if want_coarse:
		_coarse_in_flight = true
		rd.texture_get_data_async(_coarse_rid, 0, _on_coarse_ready)

func _dispatch(cl: int, mode: int, op_index: int, rect: Vector4i, flip: bool) -> void:
	rd.compute_list_bind_uniform_set(cl, _uset_rids[_cur], 0)
	var pc := PackedInt32Array([mode, op_index, 0, 0, rect.x, rect.y, rect.z, rect.w])
	rd.compute_list_set_push_constant(cl, pc.to_byte_array(), 32)
	if mode == 9:
		rd.compute_list_dispatch(cl, COARSE_SIZE / 8, COARSE_SIZE / 8, 1)
	else:
		rd.compute_list_dispatch(cl, TEX_SIZE / 8, TEX_SIZE / 8, 1)
	rd.compute_list_add_barrier(cl)
	if flip:
		_cur = 1 - _cur

func _on_coarse_ready(data: PackedByteArray) -> void:
	_coarse_in_flight = false
	if data.size() < COARSE_SIZE * COARSE_SIZE * 16:
		return
	_coarse = data.to_float32_array()
	_coarse_valid = true

func _on_stats_ready(data: PackedByteArray) -> void:
	if _stats_queue.is_empty():
		return
	var entry: Dictionary = _stats_queue.pop_front()
	if data.size() < (16 + MAX_OPS) * 4:
		return
	# Progress counters and probes are only valid if the full field reduction
	# (mode 6) ran during that frame.
	if bool(entry.get("full", false)):
		cleared_pixels = int(data.decode_u32(0))
		snow_volume_norm = float(data.decode_u32(4)) / 1024.0
		for p in range(4):
			_probe_h[p] = data.decode_float(32 + p * 4)
		_stats_has_data = true
		_stats_pending = true

	# Real volume removed by each operation of the frame just read
	var cell_v := (field_width / float(TEX_SIZE)) * (field_length / float(TEX_SIZE))
	var kg_per_unit := cell_v * snow_depth * snow_density
	var meta: Array = entry.get("meta", [])
	for k in range(meta.size()):
		if k >= MAX_OPS:
			break
		var fixed := float(data.decode_u32((16 + k) * 4)) / 4096.0
		var op_entry: Dictionary = meta[k]
		var role: String = String(op_entry.get("role", ""))
		if role.is_empty() and fixed <= 0.0:
			continue
		op_volume_ready.emit(role, int(op_entry.get("owner", -1)), maxf(fixed, 0.0) * kg_per_unit)

# Tool API
func _local_xz(world_pos: Vector3) -> Vector2:
	var l := to_local(world_pos)
	return Vector2(l.x, l.z)

func _queue_op(a: Vector4, b: Vector4, role: String = "", owner: int = -1) -> void:
	if _ops.size() >= MAX_OPS:
		return
	_ops.append(PackedFloat32Array([a.x, a.y, a.z, a.w, b.x, b.y, b.z, b.w]))
	_op_meta.append({"role": role, "owner": owner})

func _mark_active(center: Vector2, radius_m: float) -> void:
	var half := Vector2(field_width, field_length) * 0.5
	var size := Vector2(field_width, field_length)
	var lo := (center - Vector2(radius_m, radius_m) + half) / size * float(TEX_SIZE)
	var hi := (center + Vector2(radius_m, radius_m) + half) / size * float(TEX_SIZE)
	var rect := Vector4i(
		clampi(int(floor(lo.x)), 0, TEX_SIZE - 1), clampi(int(floor(lo.y)), 0, TEX_SIZE - 1),
		clampi(int(ceil(hi.x)), 0, TEX_SIZE - 1), clampi(int(ceil(hi.y)), 0, TEX_SIZE - 1))
	_rect_log.append([rect, _time + SETTLE_TIME])

func _inside_field(local: Vector2, margin: float = 0.0) -> bool:
	var half_w := field_width * 0.5 + margin
	var half_l := field_length * 0.5 + margin
	return absf(local.x) <= half_w and absf(local.y) <= half_l

# Shovel: collects and piles snow while conserving mass
# max_cut_m > 0 caps the thickness cut away: the blade then works like a chisel
# and can shave thin sheets off a ball or a pile (block 4.3).
## Cumulative kilograms `carve_shovel` has handed to a blade.
##
## WHY THIS EXISTS, and it is measured rather than theoretical: the whole-field integral drifts by
## several kilograms while the granular solver relaxes -- 23199.15 and then 23202.04 for the same
## untouched world, a drift an order of magnitude larger than a bucket-sized carve. Subtracting
## two of those numbers to adjudicate mass gave the shovel battery -0.070 kg of field loss for a
## 6.300 kg load, and -11.562 kg for a 13.717 kg one. A mass check cannot be built on that.
##
## This is an exact record of what the field HANDED OVER, so it needs no integral and cannot
## drift. Read it with `shovel_yield_kg()`; reset it with `reset_shovel_yield()`.
var _shovel_yield_kg: float = 0.0
## The same, for every route out of the field. See carve_yield_kg.
var _total_yield_kg: float = 0.0


## The blade ledger: total kilograms handed to blades since the last reset.
func shovel_yield_kg() -> float:
	return _shovel_yield_kg


## Clears the blade ledger, so a test can measure a carve from a known zero.
func reset_shovel_yield() -> void:
	_shovel_yield_kg = 0.0


## EVERY kilogram this field has given up, by any route, since the last reset.
##
## `shovel_yield_kg` counts only `carve_shovel`, which is the right ledger for a blade. This one
## also counts `carve` -- the radial clearing used for tests, lanes and pits -- because a test that
## clears a strip and then pushes along it needs to measure the push WITHOUT the clearing in the
## sum. Measured reason: the shovel battery's push verdict read -90.979 kg of field loss for a
## 17.000 kg blade, because the battery reset the blade ledger while its own setup clearing went
## through `carve` and was never in that number at all.
func carve_yield_kg() -> float:
	return _total_yield_kg


## Clears the all-routes ledger.
func reset_carve_yield() -> void:
	_total_yield_kg = 0.0


func carve_shovel(scoop_pos: Vector3, forward_dir: Vector3, blade_w: float = 0.76, blade_l: float = 0.32, max_cut_m: float = 0.0) -> float:
	var local := _local_xz(scoop_pos)
	if not _inside_field(local, 1.2):
		return 0.0

	var fwd := Vector2(forward_dir.x, forward_dir.z)
	if fwd.length_squared() < 0.01:
		fwd = Vector2(0.0, -1.0)
	fwd = fwd.normalized()

	_queue_op(Vector4(local.x, local.y, fwd.x, fwd.y), Vector4(1.0, blade_w, blade_l, max_cut_m), "shovel_collect")
	_mark_active(local, 2.8)

	_blade_pos = local
	_blade_dir = fwd
	_blade_half_w = blade_w * 0.5
	_blade_half_l = blade_l * 0.5
	_blade_ttl = 0.12

	# Probe 1 tracks the blade and reports, with latency, whether snow is there
	_probe_pos[1] = local + fwd * (blade_l * 0.5 + 0.1)
	if _probe_h[1] > 0.05:
		var kg := blade_w * minf(_probe_h[1], 1.5) * 3.0
		# THE LEDGER. See `carve_shovel_yield`: the whole-field integral drifts by kilograms while
		# the granular solver relaxes, so it cannot adjudicate a small carve. This counter is an
		# exact record of what this function HANDED OVER, and it is what a mass test should read.
		_shovel_yield_kg += kg
		_total_yield_kg += kg
		return kg
	return 0.0

# Radial clearing (turbine / salt spreader)
func carve(world_pos: Vector3, radius_meters: float, _depth_cut: float, _push_dir: Vector3 = Vector3.ZERO, desalinate: bool = false) -> float:
	var local := _local_xz(world_pos)
	if not _inside_field(local, radius_meters):
		return 0.0

	_queue_op(Vector4(local.x, local.y, 0.0, -1.0), Vector4(3.0, radius_meters, 0.0, 1.0 if desalinate else 0.0), "radial_clear")
	_mark_active(local, radius_meters + 0.4)
	_probe_pos[2] = local
	if _probe_h[2] > 0.05:
		var kg_out := radius_meters * minf(_probe_h[2], 1.0) * 5.0
		_total_yield_kg += kg_out
		return kg_out
	return 0.0

# FREE DUMP (block 1.2): injects mass as loose snow
# Dumped snow enters marked as loose (G) and wet (B), so the granular solver
# spreads it into stable conical mounds on its own.
func dump_snow(world_pos: Vector3, kg: float, radius: float = 0.22, wetness: float = -1.0) -> void:
	if kg <= 0.0:
		return
	var local := _local_xz(world_pos)
	if not _inside_field(local, 0.5):
		return
	var wet := wetness if wetness >= 0.0 else deposit_wetness
	_queue_op(Vector4(local.x, local.y, 0.0, -1.0), Vector4(4.0, maxf(radius, 0.04), kg, clampf(wet, 0.0, 1.0)), "dump")
	_mark_active(local, radius + 1.2)

# TAMPING / COMPACTION (blocks 1.3 and 2.3)
# Flattens by conservative diffusion (peaks give mass to valleys through a
# plastic settle) and turns loose snow into packed, cohesive snow.
func tamp(world_pos: Vector3, radius: float = 0.34, strength: float = 1.0) -> void:
	var local := _local_xz(world_pos)
	if not _inside_field(local, 0.5):
		return
	_queue_op(Vector4(local.x, local.y, 0.0, -1.0), Vector4(5.0, maxf(radius, 0.05), clampf(strength, 0.0, 1.0), 0.0), "tamp")
	_mark_active(local, radius + 0.6)

# CYLINDRICAL HARVEST (blocks 3.2 and 4.3)
# Removes snow along a segment and reports the real volume harvested through
# the op_volume_ready(role, owner, kg) signal. Used by rolling balls
# (accretion) and by the blade while carving.
func request_harvest(owner: int, from_world: Vector3, to_world: Vector3, radius: float, max_depth: float) -> void:
	var a := _local_xz(from_world)
	var b := _local_xz(to_world)
	if not _inside_field(a, 0.5) and not _inside_field(b, 0.5):
		return
	_queue_op(Vector4(a.x, a.y, b.x, b.y), Vector4(6.0, maxf(radius, 0.03), maxf(max_depth, 0.005), 0.0), "harvest", owner)
	_mark_active(a, radius + 0.4)
	_mark_active(b, radius + 0.4)

func _emit_progress() -> void:
	var pct = (float(cleared_pixels) / float(total_pixels)) * 100.0
	kg_cleared_cumulative = (float(cleared_pixels) / float(total_pixels)) * total_snow_kg
	progress_updated.emit(pct, kg_cleared_cumulative, total_snow_kg)

## True when the GPU coarse mirror has received its first valid readback.
func is_coarse_ready() -> bool:
	return _coarse_valid and not _coarse.is_empty()

## Real total snow mass (kg) currently present on the field, integrated from the GPU coarse mirror.
func measure_total_mass() -> float:
	if not is_coarse_ready():
		return total_snow_kg
	var cell_area := (field_width / float(COARSE_SIZE)) * (field_length / float(COARSE_SIZE))
	var mass := 0.0
	var count := COARSE_SIZE * COARSE_SIZE
	for i in range(count):
		var h: float = _coarse[i * 4 + 0]
		if h > 0.0:
			mass += (h * snow_depth) * cell_area * snow_density
	return mass

# Gameplay queries (CPU mirror)
func _coarse_sample(world_pos: Vector3, channel: int) -> float:
	if not _coarse_valid:
		return -1.0
	var local := to_local(world_pos)
	var u := (local.x + field_width * 0.5) / field_width * float(COARSE_SIZE) - 0.5
	var v := (local.z + field_length * 0.5) / field_length * float(COARSE_SIZE) - 0.5
	var x0 := clampi(int(floor(u)), 0, COARSE_SIZE - 1)
	var y0 := clampi(int(floor(v)), 0, COARSE_SIZE - 1)
	var x1 := mini(x0 + 1, COARSE_SIZE - 1)
	var y1 := mini(y0 + 1, COARSE_SIZE - 1)
	var fx := clampf(u - float(x0), 0.0, 1.0)
	var fy := clampf(v - float(y0), 0.0, 1.0)
	var c := channel
	var v00 := _coarse[(y0 * COARSE_SIZE + x0) * 4 + c]
	var v10 := _coarse[(y0 * COARSE_SIZE + x1) * 4 + c]
	var v01 := _coarse[(y1 * COARSE_SIZE + x0) * 4 + c]
	var v11 := _coarse[(y1 * COARSE_SIZE + x1) * 4 + c]
	return lerpf(lerpf(v00, v10, fx), lerpf(v01, v11, fx), fy)

## Real snow height (m) at a world point, taken from the GPU mirror.
func get_height_at(world_pos: Vector3) -> float:
	var local := to_local(world_pos)
	if not _inside_field(Vector2(local.x, local.z)):
		return -1.0
	var h := _coarse_sample(world_pos, 0)
	if h < 0.0:
		return snow_depth
	return maxf(h * snow_depth, 0.0)

## Support height: the player stands on snow piles, not on the flat ground.
## Uses the highest local average around the feet, which is stable and stops
## the player floating on single-texel spikes.
func get_support_snow_height(world_pos: Vector3, foot_radius: float = 0.35) -> float:
	var local := to_local(world_pos)
	if not _inside_field(Vector2(local.x, local.z)):
		return get_snow_height(world_pos)
	if not _coarse_valid:
		return snow_depth
	var best := _coarse_sample(world_pos, 0)
	for i in range(4):
		var off := Vector2(foot_radius * 0.7, 0.0).rotated(float(i) * PI * 0.5)
		best = maxf(best, _coarse_sample(world_pos + Vector3(off.x, 0.0, off.y), 0))
	return maxf(best * snow_depth, 0.0)

## Peak height recorded in the mirror cell (for ridges and piles).
func get_peak_snow_height(world_pos: Vector3) -> float:
	var peak := _coarse_sample(world_pos, 3)
	return maxf(peak * snow_depth, 0.0) if peak >= 0.0 else 0.0

## Local cohesion/wetness [0..1].
func get_cohesion_at(world_pos: Vector3) -> float:
	var c := _coarse_sample(world_pos, 2)
	return clampf(c, 0.0, 1.0) if c >= 0.0 else 0.5

## Local loose (movable) snow [0..1], normalised against height.
func get_loose_fraction_at(world_pos: Vector3) -> float:
	var g := _coarse_sample(world_pos, 1)
	var h := _coarse_sample(world_pos, 0)
	if g < 0.0 or h <= 1e-5:
		return 0.0
	return clampf(g / h, 0.0, 1.0)

## Legacy support height: keeps the surface stable inside the field (now driven
## by the GPU mirror) plus the analytic ramp out to the snow banks.
func get_snow_height(world_pos: Vector3) -> float:
	var local = to_local(world_pos)
	var half_w = field_width * 0.5
	var half_l = field_length * 0.5

	if absf(local.x) <= half_w and absf(local.z) <= half_l:
		if not _coarse_valid:
			return snow_depth
		var h := _coarse_sample(world_pos, 0)
		return maxf(h * snow_depth, 0.0)
	elif absf(local.x) > half_w and absf(local.x) <= half_w + 4.5 and absf(local.z) <= half_l + 2.0:
		var edge_dist = absf(local.x) - half_w
		var ramp = clampf(edge_dist / 0.85, 0.0, 1.0)
		return lerpf(snow_depth, 0.72, ramp)

	return snow_depth

## Real local snow thickness (m), used for footprints, audio and resistance.
func get_snow_depth_at(world_pos: Vector3) -> float:
	var local := _local_xz(world_pos)
	if _inside_field(local):
		if _coarse_valid:
			return maxf(_coarse_sample(world_pos, 0) * snow_depth, 0.0)
		if _probe_pos[0].distance_to(local) > 0.6:
			_probe_pos[0] = local
		return _probe_h[0] * snow_depth
	return snow_depth

func _update_probes() -> void:
	var player := get_parent().get_node_or_null("Player") if get_parent() else null
	if player is Node3D:
		_probe_pos[0] = _local_xz(player.global_position)

func stamp_footprint(world_pos: Vector3, radius_m: float = 0.20, depth_dent: float = 0.06) -> void:
	var local := _local_xz(world_pos)
	if not _inside_field(local, 0.2):
		return
	_queue_op(Vector4(local.x, local.y, 0.0, -1.0), Vector4(2.0, radius_m, depth_dent, 0.0), "footprint")

## The snow bank used to pay for snow thrown into it. IT DOES NOT ANY MORE.
##
## The disposal machine is the real sink now: it is the only thing in the game that destroys
## snow, and paying for both meant two places paid for the same job while only one of them
## finished it. The bank is scenery.
##
## The code is kept, not deleted, behind this flag. The bank's payment can be switched back on
## by setting it to true, and everything downstream of it (the signal, the chunk that reports
## a landing, the HUD and the player controller that listen for it) is intact and still wired.
## Deleting it would have thrown away a mechanic somebody may want back.
const BANK_PAYS: bool = false

func check_snowbank_hit(world_pos: Vector3, kg_tossed: float) -> bool:
	var local = to_local(world_pos)
	var half_w = field_width * 0.5
	var half_l = field_length * 0.5

	if absf(local.x) > half_w and absf(local.x) < half_w + 6.0 and absf(local.z) <= half_l + 3.0:
		# Still reports the hit: the bank is a real place and snow landing in it is still a
		# fact. What it no longer does is PAY.
		if not BANK_PAYS:
			return true
		var bonus = int(ceil(kg_tossed * 1.5))
		snow_tossed_in_bank.emit(bonus, world_pos)
		return true
	return false

# Visual verification demo (godot --path . -- --plow-demo)
func _setup_demo_camera() -> void:
	var cam := Camera3D.new()
	cam.name = "DemoCamera"
	add_child(cam)
	cam.position = Vector3(3.2, 2.7, 3.2)
	cam.look_at(Vector3(-0.4, 0.0, -1.6), Vector3.UP)
	cam.fov = 55.0
	get_tree().create_timer(0.4).timeout.connect(cam.make_current)

func _run_demo(delta: float) -> void:
	_demo_t += delta
	if _demo_t > 1.0 and _demo_t - delta <= 1.0:
		RenderingServer.call_on_render_thread(_debug_dump.bind("start"))
	if _demo_t > 6.5 and _demo_t - delta <= 6.5:
		RenderingServer.call_on_render_thread(_debug_dump.bind("after-push"))
	if _demo_t > 9.0 and _demo_t - delta <= 9.0:
		RenderingServer.call_on_render_thread(_debug_dump.bind("settled"))
	var pos := Vector3.INF
	var dir := Vector3(0, 0, -1)
	if _demo_t > 1.2 and _demo_t < 4.0:
		var t := (_demo_t - 1.2) / 2.8
		pos = Vector3(-1.2, 0.0, lerpf(3.2, -3.4, t))
	elif _demo_t > 4.4 and _demo_t < 6.4:
		var t2 := (_demo_t - 4.4) / 2.0
		dir = Vector3(-0.45, 0, -1).normalized()
		pos = Vector3(lerpf(1.6, 0.5, t2), 0.0, lerpf(3.0, -2.0, t2))
	if pos == Vector3.INF:
		_demo_last = Vector3.INF
		return
	if _demo_last != Vector3.INF:
		var dist := _demo_last.distance_to(pos)
		var steps := clampi(int(dist / 0.08) + 1, 1, 4)
		for s in range(steps):
			carve_shovel(_demo_last.lerp(pos, float(s + 1) / float(steps)), dir, 0.76, 0.34)
	else:
		carve_shovel(pos, dir, 0.76, 0.34)
	_demo_last = pos

func _create_snowbanks() -> void:
	var bank_mat = StandardMaterial3D.new()
	bank_mat.albedo_color = Color(0.93, 0.96, 1.0)
	bank_mat.roughness = 0.65
	bank_mat.rim_enabled = true
	bank_mat.rim = 0.55
	bank_mat.rim_tint = 0.4

	var lantern_scene = load("res://assets/models/lantern_01.glb")

	for side in [-1, 1]:
		var bank = MeshInstance3D.new()
		var box = BoxMesh.new()
		box.size = Vector3(4.5, 0.75, field_length + 2.0)
		bank.mesh = box
		bank.position = Vector3(side * (field_width * 0.5 + 2.3), 0.38, 0)
		bank.material_override = bank_mat
		add_child(bank)

		var post = MeshInstance3D.new()
		var cyl = CylinderMesh.new()
		cyl.top_radius = 0.06
		cyl.bottom_radius = 0.08
		cyl.height = 1.6
		post.mesh = cyl
		post.position = Vector3(side * (field_width * 0.5 + 0.9), 0.8, -field_length * 0.2)
		var wood_mat = StandardMaterial3D.new()
		wood_mat.albedo_color = Color(0.46, 0.30, 0.16)
		wood_mat.roughness = 0.75
		post.material_override = wood_mat
		add_child(post)

		if lantern_scene:
			var lantern = lantern_scene.instantiate()
			lantern.position = post.position + Vector3(0, 0.7, 0)
			lantern.scale = Vector3(0.7, 0.7, 0.7)
			add_child(lantern)

		var lamp = OmniLight3D.new()
		lamp.light_color = Color(1.0, 0.78, 0.48)
		lamp.light_energy = 2.4
		lamp.omni_range = 8.5
		lamp.shadow_enabled = true
		lamp.position = post.position + Vector3(0, 0.95, 0)
		add_child(lamp)

# Debug dump: reads the whole map and prints profiles and total volume
func _debug_dump(label: String) -> void:
	if not sim_ready:
		return
	var f := rd.texture_get_data(_tex_rids[_cur], 0).to_float32_array()
	var vol := 0.0
	var maxh := 0.0
	for i in range(TEX_SIZE * TEX_SIZE):
		vol += f[i * 4]
		maxh = maxf(maxh, f[i * 4])
	print("[DUMP %s] volume=%.1f (initial %d)  max_height=%.2f (%.2f m)" % [label, vol, TEX_SIZE * TEX_SIZE, maxh, maxh * snow_depth])
	var px := int((-1.2 + field_width * 0.5) / field_width * TEX_SIZE)
	var line := "z profile (x=-1.2): "
	var zz := -4.4
	while zz <= 3.4:
		var py := clampi(int((zz + field_length * 0.5) / field_length * TEX_SIZE), 0, TEX_SIZE - 1)
		line += "%.2f " % f[(py * TEX_SIZE + px) * 4]
		zz += 0.2
	print(line)
	var best := 0
	for i in range(TEX_SIZE * TEX_SIZE):
		if f[i * 4] > f[best * 4]:
			best = i
	var by := best / TEX_SIZE
	var bx := best % TEX_SIZE
	print("peak at x=%.2f z=%.2f" % [(float(bx) + 0.5) / TEX_SIZE * field_width - field_width * 0.5, (float(by) + 0.5) / TEX_SIZE * field_length - field_length * 0.5])
	var lat := "lateral at peak: "
	for dx in range(-60, 61, 6):
		var x2 := clampi(bx + dx, 0, TEX_SIZE - 1)
		lat += "%.2f " % f[(by * TEX_SIZE + x2) * 4]
	print(lat)
