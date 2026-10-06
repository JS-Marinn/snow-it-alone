shader_type spatial;
render_mode cull_back, diffuse_lambert, specular_schlick_ggx;

// ============================================================================
//  Universal Toon / Cel Shader
//  Preserves albedo textures (e.g. colormap atlas) and original material colors.
//  Applies multi-band quantization, cool pastel shadow tint, warm rim lighting,
//  and fine dark-blue contours.
// ============================================================================

group_uniforms Surface;
uniform vec4 albedo_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform sampler2D albedo_texture : source_color, filter_nearest_mipmap, hint_default_white, repeat_enable;
uniform float roughness : hint_range(0.0, 1.0) = 0.6;
uniform float metallic : hint_range(0.0, 1.0) = 0.0;
uniform vec3 emission : source_color = vec3(0.0);
uniform float emission_energy : hint_range(0.0, 16.0) = 0.0;

group_uniforms CelShading;
uniform bool toon_enabled = true;
uniform int bands : hint_range(1, 5) = 2;
uniform float band_softness : hint_range(0.001, 0.4) = 0.18;
uniform vec3 shadow_tint : source_color = vec3(0.68, 0.74, 0.88);
uniform float rim_strength : hint_range(0.0, 2.0) = 0.65;
uniform vec3 rim_color : source_color = vec3(1.0, 0.92, 0.80);

void fragment() {
	vec4 tex = texture(albedo_texture, UV);
	vec4 base = albedo_color * tex;

	ALBEDO = base.rgb;
	ALPHA = base.a;
	ROUGHNESS = roughness;
	METALLIC = metallic;
	if (emission_energy > 0.0) {
		EMISSION = emission * emission_energy;
	}
}

const float INV_PI = 0.318309886;

void light() {
	if (!toon_enabled) {
		float NdotL = clamp(dot(NORMAL, LIGHT), 0.0, 1.0);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * (NdotL * INV_PI * ATTENUATION);
	} else {
		// 1. Irradiancia incidente: monótona y continua sobre caras planas
		float NdotL = dot(NORMAL, LIGHT);
		float half_lambert = clamp(NdotL * 0.5 + 0.5, 0.0, 1.0);
		float lit = clamp(half_lambert * ATTENUATION, 0.0, 1.0);

		// 2. Cuantización suave (1-2 bandas con terminador suave) para evitar mosaicos en planos
		float band_factor = 0.0;
		if (bands <= 1) {
			band_factor = smoothstep(0.40 - band_softness, 0.40 + band_softness, lit);
		} else if (bands == 2) {
			band_factor = smoothstep(0.45 - band_softness, 0.45 + band_softness, lit);
		} else {
			float step1 = smoothstep(0.38 - band_softness, 0.38 + band_softness, lit);
			float step2 = smoothstep(0.68 - band_softness, 0.68 + band_softness, lit);
			band_factor = step1 * 0.5 + step2 * 0.5;
		}

		// 3. Tinte frío de sombra vs luz directa cálida
		vec3 light_ramp = mix(shadow_tint, vec3(1.0), band_factor);
		float diffuse_scale = mix(0.25, 1.0, band_factor) * INV_PI * 1.25;
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * light_ramp * diffuse_scale;

		// 4. Rim light contenido en ángulos estrictamente rasantes para silueta
		float NdotV = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
		float rim = 1.0 - NdotV;
		float rim_mask = smoothstep(0.72, 0.95, rim);
		float rim_lit = clamp(NdotL * 0.5 + 0.5, 0.0, 1.0);
		vec3 rim_contrib = rim_color * (rim_mask * rim_strength * rim_lit * INV_PI * 0.9);
		DIFFUSE_LIGHT += ALBEDO * LIGHT_COLOR * rim_contrib;

		// 5. Destello especular estilizado
		float spec_size = (1.0 - ROUGHNESS) * 0.45;
		if (spec_size > 0.05) {
			vec3 H = normalize(LIGHT + VIEW);
			float NdotH = clamp(dot(NORMAL, H), 0.0, 1.0);
			float spec = smoothstep(1.0 - spec_size - 0.03, 1.0 - spec_size + 0.03, pow(NdotH, 24.0 / max(ROUGHNESS * ROUGHNESS, 0.01)));
			SPECULAR_LIGHT += LIGHT_COLOR * spec * ATTENUATION * (1.0 - ROUGHNESS) * 0.7 * INV_PI;
		}
	}
}
