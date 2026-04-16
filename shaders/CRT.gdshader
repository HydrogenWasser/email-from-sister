shader_type canvas_item;

uniform float scanline_intensity : hint_range(0.0, 1.0) = 0.3;
uniform float scanline_count : hint_range(0.0, 4096.0) = 720.0;
uniform float curvature : hint_range(0.0, 0.1) = 0.01;
uniform float vignette_intensity : hint_range(0.0, 1.0) = 0.18;
uniform float chromatic_aberration : hint_range(0.0, 5.0) = 0.8;
uniform float noise_intensity : hint_range(0.0, 1.0) = 0.05;
uniform float shake_intensity : hint_range(0.0, 0.1) = 0.0;
uniform float flicker_intensity : hint_range(0.0, 1.0) = 0.02;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;

float random(vec2 uv) {
	return fract(sin(dot(uv.xy, vec2(12.9898, 78.233))) * 43758.5453);
}

vec2 curve_uv(vec2 uv) {
	vec2 centered = uv - 0.5;
	float dist = dot(centered, centered);
	return centered * (1.0 + curvature * dist) + 0.5;
}

float vignette(vec2 uv) {
	vec2 centered = uv - 0.5;
	float dist = length(centered);
	float edge_falloff = smoothstep(0.52, 0.92, dist);
	return mix(1.0, 0.78, edge_falloff * vignette_intensity);
}

void fragment() {
	vec2 uv = UV;

	float shake_x = (random(vec2(TIME, 0.0)) - 0.5) * shake_intensity;
	float shake_y = (random(vec2(0.0, TIME)) - 0.5) * shake_intensity;
	uv += vec2(shake_x, shake_y);

	vec2 curved_uv = curve_uv(uv);

	if (curved_uv.x < 0.0 || curved_uv.x > 1.0 || curved_uv.y < 0.0 || curved_uv.y > 1.0) {
		COLOR = vec4(0.0, 0.0, 0.0, 1.0);
	} else {
		vec3 color;
		float aberration = chromatic_aberration / 1000.0;
		vec2 offset = curved_uv - vec2(0.5);
		vec2 direction = vec2(0.0);

		if (length(offset) > 0.0001) {
			direction = normalize(offset);
		}

		float r = texture(screen_texture, curved_uv + direction * aberration).r;
		float g = texture(screen_texture, curved_uv).g;
		float b = texture(screen_texture, curved_uv - direction * aberration).b;
		color = vec3(r, g, b);

		float scanline = sin(curved_uv.y * scanline_count * PI) * 0.5 + 0.5;
		scanline = 1.0 - (scanline * scanline_intensity);
		color *= scanline;

		float scanline_dark = step(0.98, fract(curved_uv.y * scanline_count * 0.5));
		color *= (1.0 - scanline_dark * 0.3);

		float vig = vignette(curved_uv);
		color *= vig;

		float noise = random(curved_uv * max(TIME, 0.001)) * noise_intensity;
		color += noise;

		float flicker = 1.0 + (random(vec2(TIME * 10.0, 0.0)) - 0.5) * flicker_intensity;
		color *= flicker;

		color.g *= 1.05;
		color.b *= 0.95;

		COLOR = vec4(color, 1.0);
	}
}
