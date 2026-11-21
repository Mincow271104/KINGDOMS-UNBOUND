shader_type canvas_item;

uniform sampler2D sea_tex : repeat_enable, filter_linear;
uniform sampler2D bank_tex : repeat_enable, filter_linear;
uniform sampler2D envelope_tex : repeat_disable, filter_linear;
uniform sampler2D fog_state_tex : repeat_disable, filter_nearest;
uniform sampler2D transition_tex : repeat_disable, filter_linear;
uniform vec2 map_size = vec2(128.0, 128.0);
uniform float world_seed_f = 12345.0;
// 0 = Final Composite, 1 = Raw Preview Mask, 2 = Rounded Envelope, 3 = Cloud Density
uniform int debug_mode = 0;

varying vec2 v_world_pos;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

vec2 rotate_uv(vec2 p, float a) {
	float c = cos(a);
	float s = sin(a);
	return vec2(c * p.x - s * p.y, s * p.x + c * p.y);
}

void fragment() {
	float u_grid = (v_world_pos.x / 32.0) + (v_world_pos.y / 16.0);
	float v_grid = (v_world_pos.y / 16.0) - (v_world_pos.x / 32.0);
	vec2 mask_uv = (vec2(u_grid, v_grid) + 0.5) / map_size;

	float preview_sd = 300.0; // > 0 means outside preview
	float core_sd = 200.0;    // > 0 means outside clear core
	float fog_state = 0.0;    // 0.0 = UNEXPLORED, ~0.5 = EXPLORED_NOT_VISIBLE, 1.0 = VISIBLE
	float exp_cov = 0.0;      // visual-only smooth explored/visible coverage
	float vis_cov = 0.0;      // visual-only smooth visible coverage
	if (mask_uv.x >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y >= 0.0 && mask_uv.y <= 1.0) {
		vec3 m = texture(envelope_tex, mask_uv).rgb;
		preview_sd = (m.r - 0.5) * 600.0;
		core_sd    = (m.g - 0.5) * 400.0;
		fog_state  = texture(fog_state_tex, mask_uv).r;
		vec2 tr    = texture(transition_tex, mask_uv).rg;
		exp_cov    = tr.r;
		vis_cov    = tr.g;
	}

	float is_unexplored = step(fog_state, 0.25);

	vec2 seed_off = vec2(fract(world_seed_f * 0.00173) * 700.0, fract(world_seed_f * 0.00319) * 700.0);
	vec4 s1 = texture(sea_tex, (v_world_pos + seed_off) / 1180.0);
	vec4 b1 = texture(bank_tex, rotate_uv(v_world_pos - seed_off * 0.4, 0.45) / 680.0 + vec2(0.37, 0.21));
	vec4 b2 = texture(bank_tex, rotate_uv(v_world_pos + seed_off * 0.25, -0.35) / 310.0 + vec2(0.11, 0.63));

	float bank = clamp(s1.r * 0.50 + b1.r * 0.32 + b2.r * 0.24, 0.0, 1.0);
	float veil = clamp(s1.b * 0.55 + b1.b * 0.30 + b2.b * 0.20, 0.0, 1.0);
	float lit  = clamp(s1.g * 0.55 + b1.g * 0.28 + b2.g * 0.22, 0.0, 1.0);

	// 1. Outside rounded preview envelope: 100% opaque luminous cloud sea
	float opaque_sea = smoothstep(-24.0, 64.0, preview_sd + (bank - 0.42) * 56.0);
	opaque_sea = max(opaque_sea, smoothstep(48.0, 105.0, preview_sd));

	// 2. Inside preview envelope, outside clear core: soft atmospheric cloud veil
	float outer_mist_mask = smoothstep(-32.0, 96.0, core_sd + (bank - 0.40) * 42.0);
	float preview_cloud = clamp(outer_mist_mask * (1.0 - opaque_sea), 0.0, 1.0) * (0.24 + 0.42 * bank + 0.16 * veil);
	float preview_alpha = clamp(max(opaque_sea, preview_cloud), 0.0, 1.0);

	// 3. Visual-only smooth transition across EXPLORED <-> UNEXPLORED (Zero Overlay on EXPLORED_NOT_VISIBLE)
	float unexp_factor = 1.0 - smoothstep(0.10, 0.86, exp_cov + (bank - 0.46) * 0.36);

	float cloud_alpha = preview_alpha * unexp_factor;
	float total_alpha = clamp(cloud_alpha, 0.0, 1.0);

	if (debug_mode == 1) {
		float in_prev = 1.0 - smoothstep(-2.0, 2.0, preview_sd);
		float fow_exp = 1.0 - is_unexplored;
		COLOR = vec4(0.15, 0.55 * in_prev + 0.25 * fow_exp, 0.85 * fow_exp + 0.25 * in_prev, 0.88);
	} else if (debug_mode == 2) {
		float env_val = 1.0 - smoothstep(-40.0, 40.0, preview_sd);
		float core_val = 1.0 - smoothstep(-30.0, 30.0, core_sd);
		COLOR = vec4(env_val * 0.8, core_val * 0.9, 0.3 + 0.7 * env_val, 0.88);
	} else if (debug_mode == 3) {
		COLOR = vec4(vec3(total_alpha), 1.0);
	} else {
		if (total_alpha < 0.005) {
			discard;
		}
		vec3 col_shadow = vec3(0.68, 0.76, 0.86);
		vec3 col_mist   = vec3(0.80, 0.86, 0.93);
		vec3 col_body   = vec3(0.92, 0.95, 0.98);
		vec3 col_top    = vec3(0.99, 0.995, 1.00);

		float h = clamp(lit * 0.62 + bank * 0.38, 0.0, 1.0);
		vec3 cloud_col = mix(col_shadow, col_mist, smoothstep(0.10, 0.36, h));
		cloud_col = mix(cloud_col, col_body, smoothstep(0.36, 0.66, h));
		cloud_col = mix(cloud_col, col_top, smoothstep(0.64, 0.92, h));

		COLOR = vec4(cloud_col, total_alpha);
	}
}
