#[compute]
#version 450

// ============================================================================
//  Simulación de nieve en GPU (compute) — FÍSICAS EMERGENTES
//
//  Canales de la textura RGBA32F:
//    R = altura total H            (1.0 = capa virgen = snow_depth metros)
//    G = nieve SUELTA / movilizable (solo esta fracción puede fluir)
//    B = COHESIÓN / humedad [0..1]  (modula el ángulo de fricción interna)
//    A = scratch de relajación:  +escala  -> celda en REPOSO
//                                -escala  -> celda EN FLUJO (histéresis bi-fásica)
//
//  Ángulo de reposo bi-fásico (Ley de Coulomb granular con histéresis):
//    - Una celda en reposo necesita superar el ángulo ESTÁTICO para arrancar.
//    - Una celda ya en flujo se asienta en el ángulo DINÁMICO.
//    - La cohesión (B) eleva ambos ángulos: nieve húmeda sostiene paredes más
//      verticales que la nieve seca.
//
//  Modos (push constant):
//    0 = Pala: recoge la nieve bajo la plancha (con corte máximo opcional = esculpido)
//    1 = Pala: deposita la nieve recogida frente a la hoja (montón)
//    2 = Sellos: huella de bota / limpieza radial
//    3 = DUMP: inyecta volumen libre en (x,z) con perfil de montículo cónico
//    4 = Relajación (1/2): escala de salida + estado de flujo (histéresis)
//    5 = Relajación (2/2): transfiere nieve suelta según el ángulo de reposo
//    6 = Estadísticas, sondas y volumen retirado por operación
//    7 = TAMP: aplana (difusión conservativa) y compacta la nieve
//    8 = HARVEST: siega un cilindro a lo largo de un segmento (acreción de bolas)
//    9 = COARSE: espejo reducido 64x64 para consultas de gameplay en CPU
// ============================================================================

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f, set = 0, binding = 0) uniform restrict readonly image2D src_img;
layout(rgba32f, set = 0, binding = 1) uniform restrict writeonly image2D dst_img;
// El espejo CPU es RGBA32F: declararlo r32f descartaría los canales de nieve
// suelta, cohesión y altura máxima al escribir.
layout(rgba32f, set = 0, binding = 5) uniform restrict writeonly image2D coarse_img;

struct Op {
	vec4 a; // xy = posición/segmento inicio (x,z), zw = dirección / segmento fin
	vec4 b; // x = tipo, y = radio/medio ancho, z = largo/profundidad/volumen, w = libre
	vec4 c; // x = fraction retained by shovel blade; remaining collected mass is redeposited
};

layout(set = 0, binding = 2, std140) uniform Params {
	vec4 field;   // xy = tamaño (m), z = snow_depth (m), w = tamaño textura
	vec4 sim;     // x = áng. dinámico seco (rad), y = áng. dinámico húmedo (rad),
	              // z = histéresis (rad), w = tasa de relajación
	vec4 sim2;    // x = lambda de depósito, y = largo de depósito, z = humedad al verter, w = densidad kg/m3
	vec4 sim3;    // x = asiento del palmeo (m), y = fracción de compactación, z = cohesión añadida, w = tan(áng. reposo ref.)
	vec4 blade0;  // x = activa, yz = posición, w = altura de la pared de la hoja (m)
	vec4 blade1;  // xy = dirección, z = medio ancho, w = medio largo
	vec4 probes[4];
	Op ops[12];
} P;

layout(set = 0, binding = 3, std430) buffer Stats { uint v[]; } stats;
layout(set = 0, binding = 4, std430) buffer Buckets { uint v[]; } buckets;

// Operation-mass reductions are rounded once per workgroup rather than once per texel.
// Per-texel fixed-point rounding was visibly inflating small deposit contributions.
shared float wg_mass[64];

layout(push_constant, std430) uniform Push {
	int mode;
	int op_index;
	int pad0;
	int pad1;
	ivec4 rect;
} pc;

const int TEX = 512;
const int COARSE = 64;
const int COARSE_BLOCK = TEX / COARSE;
const int MAX_OPS = 12;
const int BUCKETS = 192;
const float BUCKET_W = 0.01;
const float BUCKET_HALF = 0.96;
const float FIXED_SCALE = 4096.0;
// GLSL no define PI (es un builtin del lenguaje de shaders de Godot, no de GLSL)
const float PI = 3.14159265358979323846;

const ivec2 NB[8] = ivec2[8](
	ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1),
	ivec2(1, 1), ivec2(1, -1), ivec2(-1, 1), ivec2(-1, -1)
);
const ivec2 NB4[4] = ivec2[4](
	ivec2(1, 0), ivec2(-1, 0), ivec2(0, 1), ivec2(0, -1)
);

vec2 texel_size_m() {
	return P.field.xy / float(TEX);
}

float cell_area() {
	vec2 ts = texel_size_m();
	return ts.x * ts.y;
}

vec2 to_local(ivec2 id) {
	return (vec2(id) + 0.5) * texel_size_m() - 0.5 * P.field.xy;
}

bool in_rect(ivec2 c) {
	return c.x >= pc.rect.x && c.y >= pc.rect.y && c.x <= pc.rect.z && c.y <= pc.rect.w;
}

ivec2 clamp_cell(ivec2 c) {
	return clamp(c, ivec2(0), ivec2(TEX - 1));
}

float height_at(ivec2 c) {
	return imageLoad(src_img, clamp_cell(c)).r;
}

// Ángulo de fricción efectivo de la celda (radianes), modulado por su cohesión.
float friction_angle(float cohesion) {
	return mix(P.sim.x, P.sim.y, clamp(cohesion, 0.0, 1.0));
}

// Región sólida ocupada por la plancha de la pala (la nieve no puede atravesarla)
bool blocked(vec2 p) {
	if (P.blade0.x < 0.5) {
		return false;
	}
	vec2 f = P.blade1.xy;
	vec2 r = vec2(f.y, -f.x);
	vec2 d = p - P.blade0.yz;
	return abs(dot(d, r)) < P.blade1.z + 0.03 && abs(dot(d, f)) < P.blade1.w + 0.02;
}

// Flujo de nieve de la celda a hacia la celda b (en altura normalizada).
// mob_a = 1.0 si la celda a ya está en movimiento -> usa el ángulo dinámico;
//        0.0 si está en reposo -> exige superar el ángulo estático (histéresis).
float raw_flow(ivec2 a, ivec2 b, float ha, float hb, float cohesion_a, float mob_a) {
	if (ha <= hb) {
		return 0.0;
	}
	if (blocked(to_local(a))) {
		return 0.0;
	}
	if (blocked(to_local(b))) {
		// La hoja actúa como muro: solo la nieve que sobrepasa su altura cae por encima
		hb = max(hb, P.blade0.w / P.field.z);
	}
	float dist = length(vec2(b - a) * texel_size_m());
	float ang = friction_angle(cohesion_a) + (mob_a > 0.5 ? 0.0 : P.sim.z);
	float excess = (ha - hb) * P.field.z - tan(ang) * dist;
	return max(excess, 0.0) / P.field.z * P.sim.w;
}

// ---------------------------------------------------------------- Modo 0
// Recoge la nieve bajo la plancha. op.b.w = corte máximo en metros (0 = sin límite):
// con un corte pequeño la hoja actúa como formón y arranca láminas finas (esculpido).
void mode_collect(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	Op op = P.ops[pc.op_index];
	vec2 p = to_local(id);
	vec2 f = normalize(op.a.zw);
	vec2 r = vec2(f.y, -f.x);
	float hw = op.b.y * 0.5;
	float hl = op.b.z * 0.5;
	vec2 d = p - op.a.xy;
	float lat = dot(d, r);
	float fw = dot(d, f);

	float m = (1.0 - smoothstep(hw - 0.05, hw + 0.05, abs(lat)))
		* smoothstep(-hl - 0.02, -hl + 0.02, fw)
		* (1.0 - smoothstep(hl - 0.02, hl + 0.02, fw));

	float cut_limit = op.b.w > 0.0 ? op.b.w / P.field.z : s.r;
	float removed = min(s.r, cut_limit) * m;
	if (removed > 0.0) {
		int k = clamp(int(floor((lat + BUCKET_HALF) / BUCKET_W)), 0, BUCKETS - 1);
		atomicAdd(buckets.v[pc.op_index * BUCKETS + k], uint(removed * FIXED_SCALE + 0.5));
	}
	float h = s.r - removed;
	float lo = s.g * (1.0 - m);
	if (h < 0.002) {
		h = 0.0;
		lo = 0.0;
	}
	imageStore(dst_img, id, vec4(h, min(lo, h), s.b, s.a));
	wg_mass[gl_LocalInvocationIndex] = removed;
	barrier();
	for (int stride = 32; stride > 0; stride >>= 1) {
		if (int(gl_LocalInvocationIndex) < stride) {
			wg_mass[gl_LocalInvocationIndex] += wg_mass[gl_LocalInvocationIndex + uint(stride)];
		}
		barrier();
	}
	if (gl_LocalInvocationIndex == 0u) {
		atomicAdd(stats.v[16 + pc.op_index], uint(wg_mass[0] * FIXED_SCALE + 0.5));
	}
}

// ---------------------------------------------------------------- Modo 1
float shovel_deposit_weight(ivec2 id, Op op, vec4 s) {
	vec2 p = to_local(id);
	vec2 f = normalize(op.a.zw);
	vec2 r = vec2(f.y, -f.x);
	float hl = op.b.z * 0.5;
	vec2 d = p - op.a.xy;
	float lat = dot(d, r);
	float x = dot(d, f) - hl;
	ivec2 c_face = clamp(ivec2(floor((op.a.xy + f * (hl + 0.04) + 0.5 * P.field.xy) / P.field.xy * float(TEX))), ivec2(0), ivec2(TEX - 1));
	ivec2 c_far = clamp(ivec2(floor((op.a.xy + f * (hl + 0.9) + 0.5 * P.field.xy) / P.field.xy * float(TEX))), ivec2(0), ivec2(TEX - 1));
	float pile_h = max(height_at(c_face) - height_at(c_far), 0.0) * P.field.z;
	float slope_ref = max(P.sim3.w, 0.2);
	float lambda = clamp(max(P.sim2.x, pile_h / slope_ref), P.sim2.x, 0.5);
	float depth_len = max(P.sim2.y, 4.6 * lambda);
	float sigma = clamp(0.4 * lambda, 0.07, 0.2);
	float leak = clamp((pile_h - 0.10) / 0.25, 0.0, 0.92);
	int kc = int(floor((lat + BUCKET_HALF) / BUCKET_W));
	float cell = cell_area();
	float weight = 0.0;

	if (x >= 0.0 && x < depth_len && abs(lat) < BUCKET_HALF - 0.2) {
		float norm = 1.0 - exp(-depth_len / lambda);
		float g = exp(-x / lambda) / lambda / norm;
		int win = int(ceil(3.2 * sigma / BUCKET_W));
		float dens = 0.0;
		for (int k = kc - win; k <= kc + win; k++) {
			if (k < 0 || k >= BUCKETS) {
				continue;
			}
			uint raw = buckets.v[pc.op_index * BUCKETS + k];
			if (raw == 0u) {
				continue;
			}
			float lat_b = (float(k) + 0.5) * BUCKET_W - BUCKET_HALF;
			float dl = (lat - lat_b) / sigma;
			float kl = exp(-0.5 * dl * dl) / (sigma * 2.5066283);
			dens += (float(raw) / FIXED_SCALE) * kl;
		}
		weight += dens * g * cell * (1.0 - leak);
	}

	float hw = op.b.y * 0.5;
	if (leak > 0.0 && x > -0.34 && x < 0.30) {
		float wc = hw + 0.22;
		float sw = 0.12;
		float dl1 = (lat - wc) / sw;
		float dl2 = (lat + wc) / sw;
		float kw = 0.5 * (exp(-0.5 * dl1 * dl1) + exp(-0.5 * dl2 * dl2)) / (sw * 2.5066283);
		if (kw > 1e-4) {
			float m_total = 0.0;
			for (int k = 0; k < BUCKETS; k++) {
				m_total += float(buckets.v[pc.op_index * BUCKETS + k]) / FIXED_SCALE;
			}
			float gw = smoothstep(-0.34, -0.30, x) * (1.0 - smoothstep(0.26, 0.30, x)) / 0.60;
			weight += m_total * kw * gw * cell * leak;
		}
	}
	return weight * (1.0 - clamp(op.c.x, 0.0, 1.0));
}


// Pre-pass: measure the discrete deposit footprint so the next pass can normalize it to
// exactly the source mass minus the fraction retained in the blade.
void mode_deposit_measure(ivec2 id) {
	Op op = P.ops[pc.op_index];
	vec4 s = imageLoad(src_img, id);
	float weight = in_rect(id) ? shovel_deposit_weight(id, op, s) : 0.0;
	wg_mass[gl_LocalInvocationIndex] = weight;
	barrier();
	for (int stride = 32; stride > 0; stride >>= 1) {
		if (int(gl_LocalInvocationIndex) < stride) {
			wg_mass[gl_LocalInvocationIndex] += wg_mass[gl_LocalInvocationIndex + uint(stride)];
		}
		barrier();
	}
	if (gl_LocalInvocationIndex == 0u) {
		atomicAdd(stats.v[16 + MAX_OPS + pc.op_index], uint(wg_mass[0] * FIXED_SCALE + 0.5));
	}
}


void mode_deposit(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	Op op = P.ops[pc.op_index];
	float retained = clamp(op.c.x, 0.0, 1.0);
	float source_norm = float(stats.v[16 + pc.op_index]) / FIXED_SCALE;
	float deposit_norm = source_norm * (1.0 - retained);
	float measured_weight = float(stats.v[16 + MAX_OPS + pc.op_index]) / FIXED_SCALE;
	float scale = deposit_norm / max(measured_weight, 1e-9);
	float added = 0.0;
	if (in_rect(id)) {
		added = shovel_deposit_weight(id, op, s) * scale;
	}
	if (added > 1e-6 && s.r > 1e-6) {
		s.r += added;
		s.g = min(s.g + added, s.r);
		s.b = clamp((s.r - added) * s.b / s.r + added * clamp(P.sim2.z, 0.0, 1.0) / s.r, 0.0, 1.0);
	}
	imageStore(dst_img, id, vec4(s.r, min(s.g, s.r), s.b, s.a));
	wg_mass[gl_LocalInvocationIndex] = added;
	barrier();
	for (int stride = 32; stride > 0; stride >>= 1) {
		if (int(gl_LocalInvocationIndex) < stride) {
			wg_mass[gl_LocalInvocationIndex] += wg_mass[gl_LocalInvocationIndex + uint(stride)];
		}
		barrier();
	}
	if (gl_LocalInvocationIndex == 0u) {
		atomicAdd(stats.v[16 + MAX_OPS * 2 + pc.op_index], uint(wg_mass[0] * FIXED_SCALE + 0.5));
	}
}

// ---------------------------------------------------------------- Modo 2
void mode_stamp(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	Op op = P.ops[pc.op_index];
	int type = int(op.b.x + 0.5);
	vec2 p = to_local(id);

	if (type == 2) {
		// A footprint changes material state, not mass. The former height dent discarded
		// snow without a destination; visible impressions belong in a decal layer.
		vec2 q = (p - op.a.xy) / op.b.y;
		float d2 = dot(q, q);
		if (d2 < 1.0 && s.r > 0.08) {
			float w = 1.0 - d2;
			s.g = min(s.g, s.r) * (1.0 - 0.65 * w);
			s.b = min(1.0, s.b + 0.22 * w);
		}
	} else if (type == 3) {
		// Salt changes cohesion only. It is not a snow-removal operation.
		if (op.b.w > 0.5) {
			float salt_distance = length(p - op.a.xy) / op.b.y;
			if (salt_distance < 1.0) {
				float influence = 1.0 - smoothstep(0.55, 1.0, salt_distance);
				s.b = mix(s.b, 0.0, influence);
			}
		}
	}
	imageStore(dst_img, id, vec4(s.r, min(s.g, s.r), s.b, s.a));
}

// ---------------------------------------------------------------- Modo 11
// Destructive fixture reset. Kept separate from gameplay operations so an ordinary radial
// carve can no longer bypass snow ownership and remove mass without producing a payload.
void mode_clear_diagnostic(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	Op op = P.ops[pc.op_index];
	vec2 p = to_local(id);
	float removed = 0.0;
	float dist = length(p - op.a.xy) / max(op.b.y, 0.001);
	if (dist <= 0.55) {
		removed = s.r;
		s.r = 0.0;
		s.g = 0.0;
	} else if (dist < 1.0) {
		float t = (dist - 0.55) / 0.45;
		float sm = t * t * (3.0 - 2.0 * t);
		float nh = min(s.r, sm);
		removed = max(s.r - nh, 0.0);
		s.r = nh;
		s.g = min(s.g, s.r);
	}
	imageStore(dst_img, id, vec4(s.r, min(s.g, s.r), s.b, s.a));
	wg_mass[gl_LocalInvocationIndex] = removed;
	barrier();
	for (int stride = 32; stride > 0; stride >>= 1) {
		if (int(gl_LocalInvocationIndex) < stride) {
			wg_mass[gl_LocalInvocationIndex] += wg_mass[gl_LocalInvocationIndex + uint(stride)];
		}
		barrier();
	}
	if (gl_LocalInvocationIndex == 0u) {
		atomicAdd(stats.v[16 + pc.op_index], uint(wg_mass[0] * FIXED_SCALE + 0.5));
	}
}

// ---------------------------------------------------------------- Modo 3
// Inject a uniformly distributed loose-snow footprint. This is only the contact area of the
// deposit; granular relaxation, not a baked cone profile, determines the resulting pile.
//   op.a.xy = local centre, op.b.y = footprint radius (m), op.b.z = requested mass (kg)
void mode_dump(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	Op op = P.ops[pc.op_index];
	vec2 p = to_local(id);
	float radius = max(op.b.y, 0.02);
	float d = length(p - op.a.xy) / radius;
	float added_height = 0.0;
	if (d < 1.0) {
		float volume_m3 = op.b.z / max(P.sim2.w, 1.0);
		float height_m = op.c.x > 0.0 ? op.c.x : volume_m3 / (PI * radius * radius);
		float dh = height_m / P.field.z;
		float before = s.r;
		s.r += dh;
		s.g = min(s.g + dh, s.r);
		added_height = dh;
		// Weighted by the material mass added by this operation.
		float wet = op.b.w > 0.0 ? clamp(op.b.w, 0.0, 1.0) : clamp(P.sim2.z, 0.0, 1.0);
		if (s.r > 1e-6) {
			s.b = clamp((before * s.b + dh * wet) / s.r, 0.0, 1.0);
		}
	}
	imageStore(dst_img, id, vec4(s.r, s.g, s.b, s.a));
	wg_mass[gl_LocalInvocationIndex] = added_height;
	barrier();
	for (int stride = 32; stride > 0; stride >>= 1) {
		if (int(gl_LocalInvocationIndex) < stride) {
			wg_mass[gl_LocalInvocationIndex] += wg_mass[gl_LocalInvocationIndex + uint(stride)];
		}
		barrier();
	}
	if (gl_LocalInvocationIndex == 0u) {
		atomicAdd(stats.v[16 + MAX_OPS * 2 + pc.op_index], uint(wg_mass[0] * FIXED_SCALE + 0.5));
	}
}

// ---------------------------------------------------------------- Modo 4
void mode_relax_scale(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	float mob = s.a < 0.0 ? 1.0 : 0.0;
	float scale = 0.0;
	float total = 0.0;
	if (in_rect(id)) {
		for (int i = 0; i < 8; i++) {
			ivec2 nb = id + NB[i];
			if (!in_rect(nb)) {
				continue;
			}
			total += raw_flow(id, nb, s.r, imageLoad(src_img, nb).r, s.b, mob);
		}
		scale = total > 1e-9 ? min(1.0, s.g / total) : 1.0;
	}
	// Histéresis: el signo de A recuerda si la celda está en movimiento
	float flowing = total > 1e-7 ? 1.0 : 0.0;
	float mag = flowing > 0.5 ? max(scale, 1e-6) : max(scale, 0.0);
	float sign_a = flowing > 0.5 ? -1.0 : 1.0;
	imageStore(dst_img, id, vec4(s.r, s.g, s.b, mag * sign_a));
}

// ---------------------------------------------------------------- Modo 5
void mode_relax_flow(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	float mob = s.a < 0.0 ? 1.0 : 0.0;
	float scale = abs(s.a);
	if (in_rect(id)) {
		float out_f = 0.0;
		float in_f = 0.0;
		for (int i = 0; i < 8; i++) {
			ivec2 nb = id + NB[i];
			if (!in_rect(nb)) {
				continue;
			}
			vec4 n = imageLoad(src_img, nb);
			float n_mob = n.a < 0.0 ? 1.0 : 0.0;
			float n_scale = abs(n.a);
			out_f += raw_flow(id, nb, s.r, n.r, s.b, mob) * scale;
			in_f += raw_flow(nb, id, n.r, s.r, n.b, n_mob) * n_scale;
		}
		s.r = max(s.r - out_f + in_f, 0.0);
		s.g = clamp(s.g - out_f + in_f, 0.0, s.r);
	}
	imageStore(dst_img, id, vec4(s.r, s.g, s.b, s.a));
}

// ---------------------------------------------------------------- Modo 7
// Palmeo: aplana por difusión conservativa y asienta plásticamente la zona,
// empujando la masa sobrante hacia FUERA (no a los cuatro vecinos, donde se
// cancelaría). Todas las funciones de reparto dependen sólo del estado de la
// celda que dona, así que emisor y receptores calculan exactamente lo mismo y
// la masa total se conserva.
float tamp_w(ivec2 c, vec2 center, float radius, float strength) {
	float d = length(to_local(c) - center) / max(radius, 0.02);
	return strength * (1.0 - smoothstep(0.55, 1.0, d));
}

// Dirección de salida determinista: el eje dominante respecto al centro.
ivec2 tamp_out_dir(ivec2 c, vec2 center) {
	vec2 d = to_local(c) - center;
	if (abs(d.x) >= abs(d.y)) {
		return ivec2(d.x >= 0.0 ? 1 : -1, 0);
	}
	return ivec2(0, d.y >= 0.0 ? 1 : -1);
}

// Difusión: el pico cede su exceso sobre la media de sus vecinos (repartido a partes iguales).
float tamp_give_flat(ivec2 c, float w) {
	vec4 s = imageLoad(src_img, c);
	float avg = 0.0;
	for (int i = 0; i < 4; i++) {
		avg += height_at(c + NB4[i]);
	}
	avg *= 0.25;
	return max(s.r - avg, 0.0) * w;
}

// Asiento plástico: la zona baja `settle` y esa masa se empuja en la dirección de salida.
float tamp_give_settle(ivec2 c, float w) {
	vec4 s = imageLoad(src_img, c);
	float settle_norm = P.sim3.x / P.field.z;
	if (s.r <= settle_norm) {
		return 0.0;
	}
	float flat_e = tamp_give_flat(c, w);
	return min(settle_norm * w, max(s.r - flat_e, 0.0));
}

void mode_tamp(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	Op op = P.ops[pc.op_index];
	vec2 center = op.a.xy;
	float radius = max(op.b.y, 0.02);
	float dist = length(to_local(id) - center) / radius;
	if (dist >= 1.45) {
		imageStore(dst_img, id, s);
		return;
	}
	float strength = clamp(op.b.z, 0.0, 1.0);
	float w = tamp_w(id, center, radius, strength);

	float out_e = tamp_give_flat(id, w) + tamp_give_settle(id, w);
	float in_e = 0.0;
	for (int i = 0; i < 4; i++) {
		ivec2 nb = id + NB4[i];
		if (nb.x < 0 || nb.y < 0 || nb.x >= TEX || nb.y >= TEX) {
			continue;
		}
		float nw = tamp_w(nb, center, radius, strength);
		in_e += tamp_give_flat(nb, nw) * 0.25;
		if (tamp_out_dir(nb, center) == -NB4[i]) {
			in_e += tamp_give_settle(nb, nw);
		}
	}
	float h = max(s.r - out_e, 0.0) + in_e;
	float compact = clamp(P.sim3.y, 0.0, 1.0);
	float g = min(s.g * (1.0 - compact * w), h);
	float b = clamp(s.b + P.sim3.z * w, 0.0, 1.0);
	imageStore(dst_img, id, vec4(h, g, b, s.a));
}

// ---------------------------------------------------------------- Modo 8
// Siega un cilindro a lo largo de un segmento (acreción de bolas rodantes,
// formón de la pala).  op.a.xy = inicio, op.a.zw = fin, op.b.y = radio,
// op.b.z = profundidad máxima (m) y op.b.w = 1 -> marca de flujo (no usado aquí).
void mode_harvest(ivec2 id) {
	vec4 s = imageLoad(src_img, id);
	Op op = P.ops[pc.op_index];
	vec2 a = op.a.xy;
	vec2 b = op.a.zw;
	vec2 p = to_local(id);
	float radius = max(op.b.y, 0.02);
	float cut = 0.0;
	float d;
	float seg_len2 = dot(b - a, b - a);
	if (seg_len2 < 1e-8) {
		d = length(p - a) / radius;
	} else {
		float t = clamp(dot(p - a, b - a) / seg_len2, 0.0, 1.0);
		d = length(p - (a + (b - a) * t)) / radius;
	}
	if (d < 1.0) {
		float w = 1.0 - smoothstep(0.35, 1.0, d);
		float max_cut = op.b.z / P.field.z;
		cut = min(s.r, max_cut) * w;
		float h = max(s.r - cut, 0.0);
		float g = min(s.g, h);
		s.r = h;
		s.g = g;
	}
	imageStore(dst_img, id, s);
	wg_mass[gl_LocalInvocationIndex] = cut;
	barrier();
	for (int stride = 32; stride > 0; stride >>= 1) {
		if (int(gl_LocalInvocationIndex) < stride) {
			wg_mass[gl_LocalInvocationIndex] += wg_mass[gl_LocalInvocationIndex + uint(stride)];
		}
		barrier();
	}
	if (gl_LocalInvocationIndex == 0u) {
		atomicAdd(stats.v[16 + pc.op_index], uint(wg_mass[0] * FIXED_SCALE + 0.5));
	}
}

// ---------------------------------------------------------------- Modo 9
// Espejo reducido: media de altura, media de nieve suelta, media de cohesión y
// máximo de altura por bloque. Lo lee la CPU para sustentación, resistencia,
// rodadura de bolas y clavado de objetos.
void mode_coarse(ivec2 id) {
	if (id.x >= COARSE || id.y >= COARSE) {
		return;
	}
	ivec2 base = id * COARSE_BLOCK;
	vec4 acc = vec4(0.0);
	for (int j = 0; j < COARSE_BLOCK; j++) {
		for (int i = 0; i < COARSE_BLOCK; i++) {
			vec4 s = imageLoad(src_img, base + ivec2(i, j));
			acc.x += s.r;
			acc.y += s.g;
			acc.z += s.b;
			acc.w = max(acc.w, s.r);
		}
	}
	float n = float(COARSE_BLOCK * COARSE_BLOCK);
	imageStore(coarse_img, id, vec4(acc.x / n, acc.y / n, acc.z / n, acc.w));
}

// ---------------------------------------------------------------- Modo 6
shared uint wg_clear;
shared uint wg_volume;

void stats_pass() {
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (gl_LocalInvocationIndex == 0u) {
		wg_clear = 0u;
		wg_volume = 0u;
	}
	barrier();
	vec4 s = imageLoad(src_img, id);
	if (s.r < 0.05) {
		atomicAdd(wg_clear, 1u);
	}
	atomicAdd(wg_volume, uint(s.r * 1024.0 + 0.5));
	barrier();
	if (gl_LocalInvocationIndex == 0u) {
		atomicAdd(stats.v[0], wg_clear);
		atomicAdd(stats.v[1], wg_volume);
	}
	if (id == ivec2(0, 0)) {
		for (int i = 0; i < 4; i++) {
			vec2 q = P.probes[i].xy;
			ivec2 c = clamp(ivec2(floor((q + 0.5 * P.field.xy) / P.field.xy * float(TEX))), ivec2(0), ivec2(TEX - 1));
			vec4 v = imageLoad(src_img, c);
			stats.v[8 + i] = floatBitsToUint(v.r);
			stats.v[12 + i] = floatBitsToUint(v.g);
		}
	}
}

void main() {
	if (pc.mode == 6) {
		stats_pass();
		return;
	}
	if (pc.mode == 9) {
		mode_coarse(ivec2(gl_GlobalInvocationID.xy));
		return;
	}
	if (pc.mode == 10) {
		mode_deposit_measure(ivec2(gl_GlobalInvocationID.xy));
		return;
	}
	ivec2 id = ivec2(gl_GlobalInvocationID.xy);
	if (id.x >= TEX || id.y >= TEX) {
		return;
	}
	switch (pc.mode) {
		case 0: mode_collect(id); break;
		case 1: mode_deposit(id); break;
		case 2: mode_stamp(id); break;
		case 3: mode_dump(id); break;
		case 4: mode_relax_scale(id); break;
		case 5: mode_relax_flow(id); break;
		case 7: mode_tamp(id); break;
		case 8: mode_harvest(id); break;
		case 11: mode_clear_diagnostic(id); break;
	}
}
