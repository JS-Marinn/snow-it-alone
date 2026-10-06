shader_type spatial;
render_mode cull_front, unshaded;

// ============================================================================
//  Inverted Hull Outline Shader (Back-face extrusion)
//  Draws strictly BEHIND the front-facing geometry.
//  Cannot encroach into object interiors or create horizon bands on planes.
// ============================================================================

uniform float outline_width : hint_range(0.0, 0.05) = 0.006;
uniform vec4 outline_color : source_color = vec4(0.12, 0.16, 0.28, 1.0);
uniform bool outline_enabled = true;

void vertex() {
	if (outline_enabled && outline_width > 0.0) {
		VERTEX += NORMAL * outline_width;
	}
}

void fragment() {
	if (!outline_enabled || outline_width <= 0.0) {
		discard;
	}
	ALBEDO = outline_color.rgb;
	ALPHA = outline_color.a;
}
