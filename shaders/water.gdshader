shader_type spatial;
render_mode specular_schlick_ggx, depth_draw_opaque;

uniform vec4 shallow_color : source_color = vec4(0.05, 0.2, 0.3, 0.82);
uniform vec4 deep_color : source_color = vec4(0.0, 0.05, 0.12, 0.92);
uniform sampler2D normal_tex : repeat_enable, filter_linear_mipmap;
uniform float wave_speed = 0.35;
uniform float normal_strength = 0.55;

varying vec2 world_xz;

void vertex() {
	world_xz = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}

void fragment() {
	vec2 uv1 = world_xz * 0.035 + vec2(TIME * wave_speed * 0.05, TIME * wave_speed * 0.031);
	vec2 uv2 = world_xz * 0.08 - vec2(TIME * wave_speed * 0.043, TIME * wave_speed * 0.06);
	vec3 n1 = texture(normal_tex, uv1).rgb;
	vec3 n2 = texture(normal_tex, uv2).rgb;
	vec3 nmap = normalize(n1 + n2 - vec3(1.0));
	NORMAL_MAP = nmap * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = normal_strength;
	float fres = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 2.0);
	vec4 col = mix(deep_color, shallow_color, fres * 0.7);
	ALBEDO = col.rgb;
	ALPHA = col.a;
	ROUGHNESS = 0.08;
	SPECULAR = 0.9;
	METALLIC = 0.0;
}
