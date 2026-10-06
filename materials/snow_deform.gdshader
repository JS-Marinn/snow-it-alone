shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ============================================================================
//  Superficie de nieve: desplazamiento por mapa de alturas.
//
//  El campo de simulación es una rejilla de 512x512 sobre 8x12 m (texeles de
//  1,56 x 2,34 cm) mientras que la malla tiene un vértice cada ~2,5 cm. Muestrear
//  el mapa a pelo con esa diferencia de rejillas produce aliasing: los bordes de
//  la nieve recogida salían en "dientes" y con normales invertidas (manchas
//  oscuras).
//
//  Solución: TODA lectura del mapa (desplazamiento, máscara de color y normales)
//  pasa por el mismo filtro de huella `sample_height()`, cuyo radio se fija por
//  uniforme al tamaño real de un vértice. Así geometría, color e iluminación
//  cuentan exactamente la misma historia.
// ============================================================================

// Textura de profundidad dinámica (1.0 = nieve virgen, 0.0 = suelo despejado)
uniform sampler2D snow_heightmap : hint_default_white, filter_linear, repeat_disable;
uniform float snow_depth : hint_range(0.05, 0.8) = 0.35;
uniform vec2 field_size = vec2(8.0, 12.0);

// Radio del filtro de huella en unidades UV (lo fija SnowField a partir de la
// subdivisión real de la malla).
uniform vec2 smooth_uv = vec2(0.0023, 0.0016);

// Colores estilizados estilo Donkey Kong Bananza / Nintendo
uniform vec3 powder_color : source_color = vec3(0.93, 0.96, 1.0);      // Nieve fresca esponjosa
uniform vec3 hollow_tint : source_color = vec3(0.66, 0.76, 0.92);      // Sombras azuladas suaves de volumen
uniform vec3 packed_color : source_color = vec3(0.84, 0.88, 0.95);     // Borde compactado de la zanja
uniform vec3 ground_color : source_color = vec3(0.40, 0.42, 0.47);     // Suelo limpio despejado (pizarra húmeda estilizada)
uniform vec3 stone_pattern_color : source_color = vec3(0.33, 0.35, 0.40);

uniform float sparkle_strength : hint_range(0.0, 2.0) = 0.75;

// ============================================================================
//  Cel Shading / Toon Lighting Parameters
// ============================================================================
group_uniforms CelShading;
uniform bool toon_enabled = true;
uniform int bands : hint_range(1, 5) = 3;
uniform float band_softness : hint_range(0.001, 0.3) = 0.05;
uniform vec3 shadow_tint : source_color = vec3(0.68, 0.74, 0.88);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.75;
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.80);

group_uniforms Outline;
uniform float outline_width : hint_range(0.0, 0.05) = 0.006;
uniform vec4 outline_color : source_color = vec4(0.12, 0.16, 0.28, 1.0);

varying vec3 v_world_pos;
varying float v_slope;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Filtro de huella: media de 5 tomas en cruz al radio del vértice. Estabiliza la
// lectura frente al desajuste de rejillas sin perder el detalle del montón.
float sample_height(vec2 uv, vec2 radius) {
	float h = textureLod(snow_heightmap, uv, 0.0).r;
	h += textureLod(snow_heightmap, uv + vec2(radius.x, 0.0), 0.0).r;
	h += textureLod(snow_heightmap, uv - vec2(radius.x, 0.0), 0.0).r;
	h += textureLod(snow_heightmap, uv + vec2(0.0, radius.y), 0.0).r;
	h += textureLod(snow_heightmap, uv - vec2(0.0, radius.y), 0.0).r;
	return h * 0.2;
}

float sample_height(vec2 uv) {
	return sample_height(uv, smooth_uv);
}

void vertex() {
	vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_pos = wp;

	float h = sample_height(UV);
	VERTEX.y += h * snow_depth;
}

void fragment() {
	float h = sample_height(UV);
	// Transición nieve -> pavimento: borde limpio y estrecho (0,3 a 1,9 cm de
	// nieve). Al estar h filtrada a la escala del vértice no genera ruido.
	float mask = smoothstep(0.010, 0.060, h);

	// Patrón sutil estilizado de adoquines / losas para el suelo limpio
	vec2 stone_grid = fract(v_world_pos.xz * 1.5);
	float edge = step(0.06, stone_grid.x) * step(0.06, stone_grid.y);
	vec3 clean_path = mix(stone_pattern_color, ground_color, edge);

	// Normal suave a partir del MISMO dato filtrado, con un paso de una huella de
	// vértice: así no aparecen normales invertidas en los cortes.
	float hr = sample_height(UV + vec2(smooth_uv.x, 0.0));
	float hl = sample_height(UV - vec2(smooth_uv.x, 0.0));
	float hd = sample_height(UV + vec2(0.0, smooth_uv.y));
	float hu = sample_height(UV - vec2(0.0, smooth_uv.y));

	float dX = (hr - hl) * snow_depth;
	float dZ = (hd - hu) * snow_depth;
	float stepX = 2.0 * smooth_uv.x * field_size.x;
	float stepZ = 2.0 * smooth_uv.y * field_size.y;
	vec3 world_n = normalize(vec3(-dX / stepX, 1.0, -dZ / stepZ));

	// Convertir la normal calculada al espacio de vista (View Space) que requiere Godot
	NORMAL = (VIEW_MATRIX * vec4(world_n, 0.0)).xyz;

	// La nieve virgen es blanca; sólo la película muy fina se ve compactada, así
	// que el borde de lo recogido no se emborrona en una banda gris.
	vec3 snow = mix(packed_color, powder_color, smoothstep(0.55, 0.95, h));
	// Nieve suelta apilada (canal G): esponjosa y luminosa, sin el tono compactado
	float loose = texture(snow_heightmap, UV).g;
	snow = mix(snow, powder_color, smoothstep(0.03, 0.30, loose));
	float slope = 1.0 - clamp(world_n.y, 0.0, 1.0);
	v_slope = slope;
	snow = mix(snow, hollow_tint, slope * 0.30);

	// Destellos sutiles de escarcha
	float sp = step(0.995, hash(floor(v_world_pos.xz * 160.0))) * mask;

	vec3 final_color = mix(clean_path, snow, mask);
	final_color += vec3(sp * sparkle_strength * 0.7);

	// Contorno fino azul oscuro en pendientes pronunciadas / zanjas
	if (toon_enabled && outline_width > 0.0) {
		float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float edge = smoothstep(outline_width * 45.0, 0.0, NdotV) * smoothstep(0.08, 0.35, slope) * mask;
		final_color = mix(final_color, outline_color.rgb, edge * outline_color.a * 0.85);
	}

	ALBEDO = final_color;
	ROUGHNESS = mix(0.42, 0.70, mask);
	SPECULAR = mix(0.35, 0.15, mask);

	// Rim lighting modulado para volumen aterciopelado (se atenúa en cortes
	// verticales para evitar aristas blancas)
	RIM = mask * smoothstep(0.4, 0.9, world_n.y) * 0.40;
	RIM_TINT = 0.35;
}

const float INV_PI = 0.318309886;

void light() {
	if (!toon_enabled) {
		float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (NdotL * INV_PI * ATTENUATION);
	} else {
		// 1. Half-Lambert para envolvencia suave sin negros crudos
		float NdotL = dot(NORMAL, LIGHT);
		float half_lambert = clamp(NdotL * 0.5 + 0.5, 0.0, 1.0);
		float lit = clamp(half_lambert * ATTENUATION, 0.0, 1.0);

		// 2. Cuantización multi-banda (2 o 3 bandas) con terminador suave
		float band_factor = 0.0;
		if (bands <= 1) {
			band_factor = smoothstep(0.5 - band_softness, 0.5 + band_softness, lit);
		} else if (bands == 2) {
			band_factor = smoothstep(0.50 - band_softness, 0.50 + band_softness, lit);
		} else {
			float step1 = smoothstep(0.50 - band_softness, 0.50 + band_softness, lit);
			float step2 = smoothstep(0.72 - band_softness, 0.72 + band_softness, lit);
			band_factor = step1 * 0.5 + step2 * 0.5;
		}

		// 3. Sombras frías (shadow_tint azul hielo) y luz directa cálida normalizada
		vec3 light_ramp = mix(shadow_tint, vec3(1.0), band_factor);
		float diffuse_scale = mix(0.18, 1.0, band_factor) * INV_PI * 1.35;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * light_ramp * diffuse_scale;

		// 4. Luz de contorno cálida (rim light) en crestas esculpidas
		float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float rim = 1.0 - NdotV;
		float rim_mask = smoothstep(0.60, 0.90, rim) * smoothstep(0.06, 0.28, v_slope);
		float rim_lit = clamp(NdotL * 0.5 + 0.5, 0.0, 1.0);
		vec3 rim_contrib = rim_color * (rim_mask * rim_strength * rim_lit * INV_PI * 1.1);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * rim_contrib;
	}
}

