shader_type spatial;
render_mode cull_back;

// Modern slate playing surface - deep blue-grey stone with faint teal
// veins and a scatter of pale "star" specks (Star Cluster branding).
// Satin roughness: lights pool softly instead of blowing out to white.
uniform vec3 body_col : source_color = vec3(0.15, 0.19, 0.24);
uniform vec3 vein_col : source_color = vec3(0.22, 0.52, 0.54);
uniform float vein_scale = 4.0;
uniform float rough_min : hint_range(0.0, 1.0) = 0.30;
uniform float rough_max : hint_range(0.0, 1.0) = 0.55;

float hash21(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453123);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
		mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int i = 0; i < 5; i++) {
		v += a * vnoise(p);
		p = p * 2.17 + vec2(11.3, 7.9);
		a *= 0.5;
	}
	return v;
}

void fragment() {
	vec2 uv = UV * vein_scale;
	float warp = fbm(uv * 1.6);
	float w = fbm(uv + warp * 1.5);
	float band = abs(fract(w * 3.0) - 0.5) * 2.0;
	float veins = smoothstep(0.0, 0.35, band);
	float speck = step(0.982, hash21(floor(uv * 22.0)));
	vec3 col = mix(vein_col, body_col, veins);
	// Pale star specks, dimmed so they twinkle rather than glare.
	col = mix(col, vec3(0.80, 0.85, 0.92), speck * 0.55);
	ALBEDO = col;
	ROUGHNESS = mix(rough_min, rough_max, veins);
	METALLIC = 0.0;
	SPECULAR = 0.55;
}
