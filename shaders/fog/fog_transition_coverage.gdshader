shader_type canvas_item;

uniform sampler2D fog_state_tex : repeat_disable, filter_nearest;
uniform vec2 map_size = vec2(128.0, 128.0);

void fragment() {
	vec2 cell_f = UV * map_size - 0.5;
	ivec2 c = ivec2(floor(cell_f + 0.5));
	int mw = int(map_size.x);
	int mh = int(map_size.y);

	float w_sum = 0.0;
	float exp_sum = 0.0;
	float vis_sum = 0.0;
	for (int dy = -2; dy <= 2; dy++) {
		for (int dx = -2; dx <= 2; dx++) {
			ivec2 p = clamp(c + ivec2(dx, dy), ivec2(0), ivec2(mw - 1, mh - 1));
			vec2 d_cell = vec2(float(p.x), float(p.y)) - cell_f;
			// Isotropic world-space distance (32x16 iso -> equal screen-space radius)
			vec2 d_iso = vec2(d_cell.x - d_cell.y, (d_cell.x + d_cell.y) * 0.5);
			float r2 = dot(d_iso, d_iso);
			float w = exp(-r2 * 0.55);
			float s = texelFetch(fog_state_tex, p, 0).r;
			exp_sum += w * step(0.25, s);
			vis_sum += w * step(0.75, s);
			w_sum += w;
		}
	}
	float inv_w = 1.0 / max(0.0001, w_sum);
	COLOR = vec4(exp_sum * inv_w, vis_sum * inv_w, 0.0, 1.0);
}
