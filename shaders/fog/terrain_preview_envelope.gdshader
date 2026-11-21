shader_type canvas_item;

const int MAX_SOURCE_SLOTS = 128;
const float PREVIEW_SMOOTH_K = 135.0;
const float CORE_SMOOTH_K = 95.0;

uniform sampler2D source_data_tex : repeat_disable, filter_nearest;
uniform int source_count = 0;
uniform vec2 map_size = vec2(128.0, 128.0);
uniform float phase_a = 0.4;
uniform float phase_b = -0.9;

float smin_poly(float a, float b, float k) {
	float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
	return mix(b, a, h) - k * h * (1.0 - h);
}

void fragment() {
	vec2 uv_grid = UV * map_size - 0.5;
	vec2 p_iso = vec2((uv_grid.x - uv_grid.y) * 16.0, (uv_grid.x + uv_grid.y) * 8.0);

	float p_sd = 9999.0;
	float c_sd = 9999.0;
	bool has_p = false;
	bool has_c = false;

	int count = min(source_count, MAX_SOURCE_SLOTS);
	for (int i = 0; i < MAX_SOURCE_SLOTS; i++) {
		if (i >= count) {
			break;
		}
		vec4 pr = texelFetch(source_data_tex, ivec2(i, 0), 0);
		vec4 dov = texelFetch(source_data_tex, ivec2(i, 1), 0);

		float dx = (p_iso.x - pr.x) / max(0.5, dov.z);
		float dy = p_iso.y - pr.y;
		float dist = sqrt(dx * dx + dy * dy);
		float lobe = 1.0;
		if (dist > 0.0001) {
			float ang = atan(dy, dx);
			lobe += 0.045 * sin(ang * 2.0 + phase_a) + 0.035 * cos(ang * 3.0 + phase_b);
			if (dov.w > 0.5 && dist > 1.0) {
				vec2 u = vec2(dx, dy) / dist;
				lobe += 0.11 * max(0.0, dot(u, dov.xy));
			}
		} else {
			lobe += 0.045 * sin(phase_a) + 0.035 * cos(phase_b);
		}

		if (pr.z > 0.0) {
			float dp = dist - pr.z * lobe;
			if (!has_p) {
				p_sd = dp;
				has_p = true;
			} else {
				p_sd = smin_poly(p_sd, dp, PREVIEW_SMOOTH_K);
			}
		}
		if (pr.w > 0.0) {
			float dc = dist - pr.w * lobe;
			if (!has_c) {
				c_sd = dc;
				has_c = true;
			} else {
				c_sd = smin_poly(c_sd, dc, CORE_SMOOTH_K);
			}
		}
	}

	float r = clamp(0.5 + p_sd / 600.0, 0.0, 1.0);
	float g = clamp(0.5 + c_sd / 400.0, 0.0, 1.0);
	COLOR = vec4(r, g, 0.0, 1.0);
}
