class_name EntityVisualRegistry
extends RefCounted
## Static Cached Texture Registry for M6-2 Caves/Nests/POIs and M6-3 Monster Sheets.
## Loads each PNG asset once into a shared static cache with graceful fallback
## if a resource path is missing. Zero disk I/O or texture recreation per frame.

static var _texture_cache: Dictionary = {} # path (String) -> Texture2D
static var _fallback_cache: Dictionary = {} # key (String) -> ImageTexture
static var _portrait_cache: Dictionary = {} # key (String) -> Texture2D

const WILDLIFE_SHEET_LAYOUTS: Dictionary = {
	"bird": {
		"path": "res://assets/entities/wildlife/wildlife_bird_sheet.png",
		"hframes": 6,
		"vframes": 2,
		"frame_size": Vector2i(20, 20),
		"idle_frames": 4,
		"move_frames": 6,
		"flee_frames": 6,
		"defensive_frames": 0,
		"idle_fps": 3.5,
		"move_fps": 10.0,
		"flee_fps": 12.0,
		"defensive_fps": 0.0,
		"badge_y": -16.0,
	},
	"frog": {
		"path": "res://assets/entities/wildlife/wildlife_frog_sheet.png",
		"hframes": 6,
		"vframes": 2,
		"frame_size": Vector2i(20, 20),
		"idle_frames": 4,
		"move_frames": 6,
		"flee_frames": 6,
		"defensive_frames": 0,
		"idle_fps": 2.4,
		"move_fps": 9.0,
		"flee_fps": 11.0,
		"defensive_fps": 0.0,
		"badge_y": -15.0,
	},
	"rabbit": {
		"path": "res://assets/entities/wildlife/wildlife_rabbit_sheet.png",
		"hframes": 6,
		"vframes": 3,
		"frame_size": Vector2i(20, 22),
		"idle_frames": 4,
		"move_frames": 6,
		"flee_frames": 6,
		"defensive_frames": 0,
		"idle_fps": 3.2,
		"move_fps": 9.5,
		"flee_fps": 13.5,
		"defensive_fps": 0.0,
		"badge_y": -17.0,
	},
	"deer": {
		"path": "res://assets/entities/wildlife/wildlife_deer_sheet.png",
		"hframes": 6,
		"vframes": 3,
		"frame_size": Vector2i(28, 28),
		"idle_frames": 4,
		"move_frames": 6,
		"flee_frames": 6,
		"defensive_frames": 0,
		"idle_fps": 2.2,
		"move_fps": 7.5,
		"flee_fps": 12.0,
		"defensive_fps": 0.0,
		"badge_y": -23.0,
	},
	"wild_boar": {
		"path": "res://assets/entities/wildlife/wildlife_wild_boar_sheet.png",
		"hframes": 6,
		"vframes": 4,
		"frame_size": Vector2i(26, 24),
		"idle_frames": 4,
		"move_frames": 6,
		"flee_frames": 6,
		"defensive_frames": 4,
		"idle_fps": 2.6,
		"move_fps": 8.5,
		"flee_fps": 12.5,
		"defensive_fps": 7.0,
		"badge_y": -19.0,
	},
	"mountain_goat": {
		"path": "res://assets/entities/wildlife/wildlife_mountain_goat_sheet.png",
		"hframes": 6,
		"vframes": 4,
		"frame_size": Vector2i(26, 26),
		"idle_frames": 4,
		"move_frames": 6,
		"flee_frames": 6,
		"defensive_frames": 4,
		"idle_fps": 2.2,
		"move_fps": 7.5,
		"flee_fps": 11.5,
		"defensive_fps": 6.5,
		"badge_y": -21.0,
	},
}

static func get_wildlife_sheet_layout(species_id: String) -> Dictionary:
	return WILDLIFE_SHEET_LAYOUTS.get(species_id, WILDLIFE_SHEET_LAYOUTS["rabbit"])

static func get_wildlife_sheet_path(species_id: String) -> String:
	var lay := get_wildlife_sheet_layout(species_id)
	return str(lay.get("path", WILDLIFE_SHEET_LAYOUTS["rabbit"]["path"]))

static func get_wildlife_sheet_texture(species_id: String) -> Texture2D:
	var path := get_wildlife_sheet_path(species_id)
	var fb_key := "wildlife_sheet:%s" % species_id
	return load_texture_cached(path, fb_key)

static func get_wildlife_portrait_texture(species_id: String) -> Texture2D:
	var cache_key := "wildlife_portrait:%s" % species_id
	if _portrait_cache.has(cache_key):
		var cached = _portrait_cache[cache_key]
		if cached is Texture2D:
			return cached
	var sheet := get_wildlife_sheet_texture(species_id)
	var lay := get_wildlife_sheet_layout(species_id)
	var fsz: Vector2i = lay.get("frame_size", Vector2i(20, 20))
	if sheet != null and sheet.get_width() >= fsz.x and sheet.get_height() >= fsz.y:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0.0, 0.0, float(fsz.x), float(fsz.y))
		_portrait_cache[cache_key] = atlas
		return atlas
	return _get_or_create_fallback("wildlife:%s" % species_id)

const MONSTER_SHEET_LAYOUTS: Dictionary = {
	"forest_stalker": {
		"path": "res://assets/entities/monsters/monster_forest_stalker_sheet.png",
		"hframes": 6,
		"vframes": 4,
		"frame_size": Vector2i(32, 32),
		"anchor_offset": Vector2(-16.0, -28.0),
		"hp_bar_y": -25.0,
		"alert_y": -28.0,
		"idle_frames": 4,
		"roam_frames": 6,
		"chase_frames": 6,
		"attack_frames": 5,
		"idle_fps": 3.0,
		"roam_fps": 8.0,
		"chase_fps": 11.0,
	},
	"marsh_crawler": {
		"path": "res://assets/entities/monsters/monster_marsh_crawler_sheet.png",
		"hframes": 6,
		"vframes": 4,
		"frame_size": Vector2i(32, 28),
		"anchor_offset": Vector2(-16.0, -25.0),
		"hp_bar_y": -20.0,
		"alert_y": -23.0,
		"idle_frames": 4,
		"roam_frames": 6,
		"chase_frames": 6,
		"attack_frames": 5,
		"idle_fps": 2.4,
		"roam_fps": 6.5,
		"chase_fps": 9.0,
	},
	"stone_brute": {
		"path": "res://assets/entities/monsters/monster_stone_brute_sheet.png",
		"hframes": 6,
		"vframes": 4,
		"frame_size": Vector2i(36, 40),
		"anchor_offset": Vector2(-18.0, -36.0),
		"hp_bar_y": -36.0,
		"alert_y": -39.0,
		"idle_frames": 4,
		"roam_frames": 6,
		"chase_frames": 6,
		"attack_frames": 5,
		"idle_fps": 2.0,
		"roam_fps": 5.5,
		"chase_fps": 7.5,
	},
}

static func get_monster_sheet_layout(species_id: String) -> Dictionary:
	return MONSTER_SHEET_LAYOUTS.get(species_id, MONSTER_SHEET_LAYOUTS["forest_stalker"])

static func get_monster_sheet_path(species_id: String) -> String:
	var lay := get_monster_sheet_layout(species_id)
	return str(lay.get("path", MONSTER_SHEET_LAYOUTS["forest_stalker"]["path"]))

static func get_monster_sheet_texture(species_id: String) -> Texture2D:
	var path := get_monster_sheet_path(species_id)
	var fb_key := "monster_sheet:%s" % species_id
	return load_texture_cached(path, fb_key)

static func get_monster_portrait_texture(species_id: String) -> Texture2D:
	var cache_key := "monster_portrait:%s" % species_id
	if _portrait_cache.has(cache_key):
		var cached = _portrait_cache[cache_key]
		if cached is Texture2D:
			return cached
	var sheet := get_monster_sheet_texture(species_id)
	var lay := get_monster_sheet_layout(species_id)
	var fsz: Vector2i = lay.get("frame_size", Vector2i(32, 32))
	if sheet != null and sheet.get_width() >= fsz.x and sheet.get_height() >= fsz.y:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0.0, 0.0, float(fsz.x), float(fsz.y))
		_portrait_cache[cache_key] = atlas
		return atlas
	return _get_or_create_fallback("monster:%s" % species_id)

static func get_nest_texture_path(species_id: String, is_destroyed: bool) -> String:
	var base := "nest_forest_stalker_bramble"
	match species_id:
		"stone_brute":
			base = "nest_stone_brute_cave"
		"marsh_crawler":
			base = "nest_marsh_crawler_mire"
		"forest_stalker":
			base = "nest_forest_stalker_bramble"
	var suffix := "_destroyed" if is_destroyed else ""
	return "res://assets/entities/nests/%s%s.png" % [base, suffix]

static func get_poi_texture_path(poi_type: String, is_claimed: bool) -> String:
	match poi_type:
		"abandoned_camp":
			return "res://assets/entities/poi/poi_abandoned_camp%s.png" % ("_claimed" if is_claimed else "")
		"forgotten_cache":
			return "res://assets/entities/poi/poi_forgotten_cache%s.png" % ("_claimed" if is_claimed else "")
		"ancient_ruins":
			return "res://assets/entities/poi/poi_ancient_ruins%s.png" % ("_claimed" if is_claimed else "")
		_:
			return "res://assets/props/prop_poi_ruins.png"

static func get_nest_texture(species_id: String, is_destroyed: bool) -> Texture2D:
	var path := get_nest_texture_path(species_id, is_destroyed)
	var fb_key := "nest:%s:%s" % [species_id, str(is_destroyed)]
	return load_texture_cached(path, fb_key)

static func get_poi_texture(poi_type: String, is_claimed: bool) -> Texture2D:
	var path := get_poi_texture_path(poi_type, is_claimed)
	var fb_key := "poi:%s:%s" % [poi_type, str(is_claimed)]
	return load_texture_cached(path, fb_key)

static func get_nest_sprite_offset(tex: Texture2D) -> Vector2:
	if tex != null:
		return Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()) + 9.0)
	return Vector2(-24.0, -31.0)

static func get_poi_sprite_offset(tex: Texture2D) -> Vector2:
	if tex != null:
		return Vector2(-float(tex.get_width()) * 0.5, -float(tex.get_height()) + 8.0)
	return Vector2(-20.0, -28.0)

const VILLAGER_FRAME_SIZE := Vector2i(32, 36)
const VILLAGER_SPRITE_OFFSET := Vector2(-16.0, -33.0)
const FACTION_MARKER_OFFSET := Vector2(0.0, -30.0)
const FACTION_MARKER_OUTLINE := Color(18.0 / 255.0, 22.0 / 255.0, 30.0 / 255.0, 1.0)
const FACTION_MARKER_COLORS: Dictionary = {
	"rival_military": Color(224.0 / 255.0, 56.0 / 255.0, 56.0 / 255.0, 1.0),
	"rival_merchant": Color(242.0 / 255.0, 194.0 / 255.0, 46.0 / 255.0, 1.0),
	"neutral_tribe": Color(62.0 / 255.0, 198.0 / 255.0, 96.0 / 255.0, 1.0),
	"emerging_power": Color(162.0 / 255.0, 92.0 / 255.0, 232.0 / 255.0, 1.0),
}

const VILLAGER_ROLE_ALIASES: Dictionary = {
	"idle": "idle",
	"farmer": "farmer",
	"woodcutter": "woodcutter",
	"woodcut": "woodcutter",
	"hunter": "hunter",
	"hauler": "hauler",
	"guard": "guard",
	"soldier": "soldier",
	"builder": "builder",
	"miner": "miner",
	"quarryman": "quarryman",
	"quarry": "quarryman",
	"smith": "smith",
}

const VILLAGER_SHEET_LAYOUTS: Dictionary = {
	"idle": {
		"path": "res://assets/entities/villagers/villager_idle_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 2.5,
	},
	"farmer": {
		"path": "res://assets/entities/villagers/villager_farmer_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 5.5,
	},
	"woodcutter": {
		"path": "res://assets/entities/villagers/villager_woodcutter_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 6.0,
	},
	"hunter": {
		"path": "res://assets/entities/villagers/villager_hunter_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.5, "work_fps": 4.0,
	},
	"hauler": {
		"path": "res://assets/entities/villagers/villager_hauler_sheet.png",
		"hframes": 6, "vframes": 8, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 8.5,
	},
	"guard": {
		"path": "res://assets/entities/villagers/villager_guard_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 4,
		"idle_fps": 2.0, "walk_fps": 8.5, "work_fps": 2.0,
	},
	"soldier": {
		"path": "res://assets/entities/villagers/villager_soldier_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.0, "walk_fps": 9.5, "work_fps": 7.5,
	},
	"builder": {
		"path": "res://assets/entities/villagers/villager_builder_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 6.0,
	},
	"miner": {
		"path": "res://assets/entities/villagers/villager_miner_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 6.0,
	},
	"quarryman": {
		"path": "res://assets/entities/villagers/villager_quarryman_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 5.5,
	},
	"smith": {
		"path": "res://assets/entities/villagers/villager_smith_sheet.png",
		"hframes": 6, "vframes": 6, "idle_frames": 4, "walk_frames": 6, "work_frames": 6,
		"idle_fps": 2.2, "walk_fps": 9.0, "work_fps": 6.5,
	},
}

static func normalize_villager_role(role_id: String) -> String:
	var key := role_id.strip_edges().to_lower()
	return str(VILLAGER_ROLE_ALIASES.get(key, "idle"))

static func get_villager_sheet_layout(role_id: String) -> Dictionary:
	var norm := normalize_villager_role(role_id)
	return VILLAGER_SHEET_LAYOUTS.get(norm, VILLAGER_SHEET_LAYOUTS["idle"])

static func get_villager_sheet_path(role_id: String) -> String:
	var lay := get_villager_sheet_layout(role_id)
	return str(lay.get("path", VILLAGER_SHEET_LAYOUTS["idle"]["path"]))

static func get_villager_sheet_texture(role_id: String) -> Texture2D:
	var norm := normalize_villager_role(role_id)
	var path := get_villager_sheet_path(norm)
	var fb_key := "villager_sheet:%s" % norm
	return load_texture_cached(path, fb_key)

static func get_villager_portrait_texture(role_id: String) -> Texture2D:
	var norm := normalize_villager_role(role_id)
	var cache_key := "villager_portrait:%s" % norm
	if _portrait_cache.has(cache_key):
		var cached = _portrait_cache[cache_key]
		if cached is Texture2D:
			return cached
	var sheet := get_villager_sheet_texture(norm)
	if sheet != null and sheet.get_width() >= VILLAGER_FRAME_SIZE.x and sheet.get_height() >= VILLAGER_FRAME_SIZE.y:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = Rect2(0.0, 0.0, float(VILLAGER_FRAME_SIZE.x), float(VILLAGER_FRAME_SIZE.y))
		_portrait_cache[cache_key] = atlas
		return atlas
	return _get_or_create_fallback("villager:%s" % norm)

static func get_faction_marker_color(faction_id: String) -> Color:
	if faction_id.is_empty() or faction_id == "player":
		return Color(0.0, 0.0, 0.0, 0.0)
	return FACTION_MARKER_COLORS.get(faction_id, Color(162.0 / 255.0, 92.0 / 255.0, 232.0 / 255.0, 1.0))

static func draw_faction_marker_7x7(canvas: CanvasItem, faction_id: String, center_pos: Vector2 = FACTION_MARKER_OFFSET) -> void:
	if canvas == null:
		return
	var col := get_faction_marker_color(faction_id)
	if col.a <= 0.0:
		return
	var cx := roundf(center_pos.x)
	var cy := roundf(center_pos.y)
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var d2 := dx * dx + dy * dy
			if d2 <= 4:
				canvas.draw_rect(Rect2(cx + float(dx), cy + float(dy), 1.0, 1.0), col, true)
			elif d2 <= 9:
				canvas.draw_rect(Rect2(cx + float(dx), cy + float(dy), 1.0, 1.0), FACTION_MARKER_OUTLINE, true)

static func load_texture_cached(path: String, fallback_key: String = "") -> Texture2D:
	if not path.is_empty() and _texture_cache.has(path):
		var cached = _texture_cache[path]
		if cached is Texture2D:
			return cached
	if not path.is_empty() and ResourceLoader.exists(path):
		var res = load(path)
		if res is Texture2D:
			_texture_cache[path] = res
			return res
	var key := fallback_key if not fallback_key.is_empty() else path
	return _get_or_create_fallback(key)

static func _get_or_create_fallback(key: String) -> ImageTexture:
	if _fallback_cache.has(key):
		return _fallback_cache[key]
	var w := 192 if (key.begins_with("monster_sheet:") or key.begins_with("villager_sheet:")) else (120 if key.begins_with("wildlife_sheet:") else 32)
	var h := 128 if key.begins_with("monster_sheet:") else (216 if key.begins_with("villager_sheet:") else (80 if key.begins_with("wildlife_sheet:") else 32))
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.0, 0.0, 0.0, 0.0))
	var col := Color(0.55, 0.45, 0.35, 1.0)
	if key.contains("stone_brute"):
		col = Color(0.48, 0.46, 0.52, 1.0)
	elif key.contains("marsh_crawler"):
		col = Color(0.32, 0.52, 0.34, 1.0)
	elif key.contains("forest_stalker"):
		col = Color(0.72, 0.24, 0.22, 1.0)
	elif key.contains("bird"):
		col = Color(0.32, 0.62, 0.88, 1.0)
	elif key.contains("frog"):
		col = Color(0.28, 0.78, 0.34, 1.0)
	elif key.contains("rabbit"):
		col = Color(0.86, 0.80, 0.72, 1.0)
	elif key.contains("deer"):
		col = Color(0.74, 0.50, 0.28, 1.0)
	elif key.contains("wild_boar"):
		col = Color(0.42, 0.30, 0.24, 1.0)
	elif key.contains("mountain_goat"):
		col = Color(0.90, 0.88, 0.82, 1.0)
	elif key.contains("ancient_ruins"):
		col = Color(0.45, 0.65, 0.78, 1.0)
	elif key.contains("forgotten_cache"):
		col = Color(0.58, 0.42, 0.24, 1.0)
	if key.begins_with("monster_sheet:"):
		var fw := 32
		var fh := 32
		for r in range(4):
			for c in range(6):
				for y in range(r * fh + 10, r * fh + 26):
					for x in range(c * fw + 8, c * fw + 24):
						img.set_pixel(x, y, col)
	elif key.begins_with("wildlife_sheet:"):
		var fw_w := 20
		var fh_w := 20
		for r in range(4):
			for c in range(6):
				for y in range(r * fh_w + 6, r * fh_w + 15):
					for x in range(c * fw_w + 5, c * fw_w + 15):
						img.set_pixel(x, y, col)
	elif key.begins_with("villager_sheet:"):
		var fw_v := 32
		var fh_v := 36
		for r in range(6):
			for c in range(6):
				for y in range(r * fh_v + 15, r * fh_v + 33):
					for x in range(c * fw_v + 11, c * fw_v + 21):
						img.set_pixel(x, y, col)
	else:
		for y in range(10, 24):
			for x in range(8, 24):
				img.set_pixel(x, y, col)
	var tex := ImageTexture.create_from_image(img)
	_fallback_cache[key] = tex
	return tex
