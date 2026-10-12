extends SceneTree
## Procedural pixel-art asset generator for KINGDOMS UNBOUND.
## Conforms strictly to docs/ASSET_STYLE_GUIDE.md:
## - 27-Color Authoritative Fantasy Palette
## - 2:1 Dimetric Isometric Diamond Projections (32x16, 64x32, 96x48)
## - Ground-contact pivots and visible rooftops + front facades (SW & SE)
## - Nearest-neighbor, lossless pixel precision

# 27-Color Palette Swatches
const COL_FOLIAGE_DARKEST := Color("#1c3829")
const COL_FOLIAGE_DEEP := Color("#2d5a3f")
const COL_FOLIAGE_MID := Color("#417d52")
const COL_FOLIAGE_LIGHT := Color("#68a666")
const COL_FOLIAGE_HIGHLIGHT := Color("#9ec77f")
const COL_FOLIAGE_DRY := Color("#b0ab54")

const COL_EARTH_DARKEST := Color("#2e1b12")
const COL_EARTH_DEEP := Color("#4a2e1b")
const COL_EARTH_MID := Color("#734b2c")
const COL_EARTH_LIGHT := Color("#a37244")
const COL_EARTH_HIGHLIGHT := Color("#c99d69")
const COL_EARTH_PALE := Color("#dbbe91")

const COL_STONE_DARKEST := Color("#1e2124")
const COL_STONE_DEEP := Color("#32383e")
const COL_STONE_MID := Color("#4f5761")
const COL_STONE_LIGHT := Color("#757f8c")
const COL_STONE_HIGHLIGHT := Color("#a3acb8")
const COL_STONE_SPECULAR := Color("#cfd5de")

const COL_WATER_ABYSS := Color("#0e1f38")
const COL_WATER_DEEP := Color("#183b5e")
const COL_WATER_MID := Color("#26608c")
const COL_WATER_SHALLOW := Color("#408ebf")
const COL_WATER_FOAM := Color("#8cd1e6")

const COL_GOLD := Color("#e5b83b")
const COL_GOLD_DARK := Color("#99751e")
const COL_CRIMSON := Color("#9e2835")
const COL_CREAM := Color("#f4eedb")
const COL_TRANSPARENT := Color(0, 0, 0, 0)

func _init() -> void:
	print("--- Generating Pixel Art Assets according to ASSET_STYLE_GUIDE.md ---")
	_ensure_directories()
	
	_generate_terrain_tile("res://assets/terrain/tile_grass.png", COL_FOLIAGE_MID, COL_FOLIAGE_LIGHT, COL_FOLIAGE_DEEP)
	_generate_terrain_tile("res://assets/terrain/tile_dirt.png", COL_EARTH_MID, COL_EARTH_LIGHT, COL_EARTH_DEEP)
	_generate_terrain_tile("res://assets/terrain/tile_water.png", COL_WATER_DEEP, COL_WATER_MID, COL_WATER_SHALLOW)
	_generate_terrain_tile("res://assets/terrain/tile_sand.png", COL_EARTH_HIGHLIGHT, COL_EARTH_PALE, COL_EARTH_LIGHT)
	
	_generate_cursor_diamond("res://assets/ui/cursor_diamond.png")
	_generate_tree_prop("res://assets/props/prop_tree.png")
	_generate_rock_prop("res://assets/props/prop_rock.png")
	_generate_citizen_sprite("res://assets/entities/citizen.png")
	
	_generate_house_building("res://assets/buildings/bld_house.png")
	_generate_townhall_building("res://assets/buildings/bld_townhall.png")
	_generate_farm_building("res://assets/buildings/bld_farm.png")
	_generate_storehouse_building("res://assets/buildings/bld_storehouse.png")
	_generate_woodcutter_building("res://assets/buildings/bld_woodcutter.png")
	
	print("=== All pixel assets generated successfully ===")
	quit(0)

func _ensure_directories() -> void:
	var dirs := ["res://assets/terrain", "res://assets/props", "res://assets/buildings", "res://assets/entities", "res://assets/ui"]
	for d in dirs:
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(d))

## Helper: Checks if pixel (x, y) falls inside diamond of dimensions (w, h)
func _is_inside_diamond(x: int, y: int, w: int, h: int) -> bool:
	var cx := (float(w) - 1.0) * 0.5
	var cy := (float(h) - 1.0) * 0.5
	var half_w := float(w) * 0.5
	var half_h := float(h) * 0.5
	var dist := (absf(float(x) - cx) / half_w) + (absf(float(y) - cy) / half_h)
	return dist <= 1.0

## 1. 32x16 Diamond Terrain Tile
func _generate_terrain_tile(path: String, base_col: Color, high_col: Color, dark_col: Color) -> void:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	for y in range(16):
		for x in range(32):
			if _is_inside_diamond(x, y, 32, 16):
				var col := base_col
				# Subtle isometric dithering / directional NW lighting
				if y < 8 and x < 16:
					# North-West quadrant gets subtle highlight
					if (x + y) % 3 == 0:
						col = high_col
				elif y >= 8 and x >= 16:
					# South-East quadrant gets subtle shade
					if (x + y) % 2 == 0:
						col = dark_col
				elif (x * 3 + y * 7) % 11 == 0:
					col = high_col
				img.set_pixel(x, y, col)
	
	img.save_png(path)
	print("Generated: %s" % path)

## 2. 32x16 Diamond Cursor Outline
func _generate_cursor_diamond(path: String) -> void:
	var img := Image.create(32, 16, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	for y in range(16):
		for x in range(32):
			var cx := 15.5
			var cy := 7.5
			var d := (absf(float(x) - cx) / 16.0) + (absf(float(y) - cy) / 8.0)
			# Outline thickness band
			if d >= 0.85 and d <= 1.05:
				img.set_pixel(x, y, COL_GOLD)
			elif d < 0.85 and d >= 0.70:
				img.set_pixel(x, y, Color(COL_GOLD.r, COL_GOLD.g, COL_GOLD.b, 0.25))
				
	img.save_png(path)
	print("Generated: %s" % path)

## 3. Tree Prop (32x48 px, Base footprint 1x1, Trunk contact at (16, 40))
func _generate_tree_prop(path: String) -> void:
	var img := Image.create(32, 48, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	# Draw Trunk
	for y in range(30, 42):
		for x in range(14, 18):
			var col := COL_EARTH_DEEP
			if x == 14:
				col = COL_EARTH_MID # NW highlight
			elif x == 17:
				col = COL_EARTH_DARKEST # SE shadow
			img.set_pixel(x, y, col)
			
	# Draw Foliage Canopy (Layers of stylized isometric foliage)
	var canopy_layers: Array[Dictionary] = [
		{"cx": 16, "cy": 16, "rx": 13, "ry": 11, "base": COL_FOLIAGE_MID, "high": COL_FOLIAGE_LIGHT, "dark": COL_FOLIAGE_DEEP},
		{"cx": 16, "cy": 24, "rx": 14, "ry": 12, "base": COL_FOLIAGE_DEEP, "high": COL_FOLIAGE_MID, "dark": COL_FOLIAGE_DARKEST},
		{"cx": 16, "cy": 10, "rx": 9, "ry": 8, "base": COL_FOLIAGE_LIGHT, "high": COL_FOLIAGE_HIGHLIGHT, "dark": COL_FOLIAGE_MID}
	]
	
	for layer in canopy_layers:
		var lcx: int = layer["cx"]
		var lcy: int = layer["cy"]
		var rx: int = layer["rx"]
		var ry: int = layer["ry"]
		for y in range(lcy - ry, lcy + ry + 1):
			for x in range(lcx - rx, lcx + rx + 1):
				if x < 0 or x >= 32 or y < 0 or y >= 48:
					continue
				var dx := float(x - lcx) / float(rx)
				var dy := float(y - lcy) / float(ry)
				if (dx * dx + dy * dy) <= 1.0:
					var col: Color = layer["base"]
					if dx < -0.2 and dy < 0.0:
						col = layer["high"] # NW light source
					elif dx > 0.2 or dy > 0.3:
						col = layer["dark"] # SE shadow
					img.set_pixel(x, y, col)
					
	# Ground shadow underneath tree
	for y in range(38, 44):
		for x in range(10, 22):
			if _is_inside_diamond(x - 16 + 16, y - 40 + 8, 32, 16):
				if img.get_pixel(x, y).a == 0.0:
					img.set_pixel(x, y, Color(0.1, 0.15, 0.1, 0.4))
					
	img.save_png(path)
	print("Generated: %s" % path)

## 4. Rock Prop (32x24 px, Ground footprint 1x1, base pivot at (16, 18))
func _generate_rock_prop(path: String) -> void:
	var img := Image.create(32, 24, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	for y in range(6, 20):
		for x in range(8, 24):
			var dx := float(x - 16) / 7.0
			var dy := float(y - 14) / 5.0
			if (dx * dx + dy * dy) <= 1.0:
				var col := COL_STONE_MID
				if dx < 0.0 and dy < 0.0:
					col = COL_STONE_LIGHT
					if dx < -0.4:
						col = COL_STONE_HIGHLIGHT
				elif dx > 0.2 or dy > 0.2:
					col = COL_STONE_DEEP
					if dy > 0.5:
						col = COL_STONE_DARKEST
				img.set_pixel(x, y, col)
				
	img.save_png(path)
	print("Generated: %s" % path)

## 5. Citizen Sprite (24x32 px canvas, Visible figure 14x24, foot pivot at (12, 30))
func _generate_citizen_sprite(path: String) -> void:
	var img := Image.create(24, 32, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	# Head / Hair (y: 6..11, x: 9..14)
	for y in range(6, 12):
		for x in range(9, 15):
			var col := COL_EARTH_HIGHLIGHT
			if y < 8:
				col = COL_EARTH_MID # Hair cap
			elif x == 10 and y == 9:
				col = COL_STONE_DARKEST # Eye
			img.set_pixel(x, y, col)
			
	# Torso / Tunic (y: 12..21, x: 8..15)
	for y in range(12, 22):
		for x in range(8, 16):
			var col := COL_WATER_MID # Blue tunic
			if x < 12:
				col = COL_WATER_SHALLOW # NW lit side
			else:
				col = COL_WATER_DEEP # SE shaded side
			if y == 17:
				col = COL_EARTH_DARKEST # Belt
			img.set_pixel(x, y, col)
			
	# Legs / Trousers (y: 22..28)
	for y in range(22, 29):
		for x in range(9, 12):
			img.set_pixel(x, y, COL_EARTH_DEEP)
		for x in range(12, 15):
			img.set_pixel(x, y, COL_EARTH_DARKEST)
			
	# Boots / Feet (y: 29..30, ground contact pivot at (12, 30))
	for x in range(9, 12):
		img.set_pixel(x, 29, COL_STONE_DEEP)
		img.set_pixel(x, 30, COL_STONE_DARKEST)
	for x in range(12, 15):
		img.set_pixel(x, 29, COL_STONE_DEEP)
		img.set_pixel(x, 30, COL_STONE_DARKEST)
		
	# Ground contact foot shadow
	img.set_pixel(11, 31, Color(0, 0, 0, 0.4))
	img.set_pixel(12, 31, Color(0, 0, 0, 0.5))
	img.set_pixel(13, 31, Color(0, 0, 0, 0.4))
	
	img.save_png(path)
	print("Generated: %s" % path)

## 6. House (64x56 px, 2x2 footprint = 64x32 base diamond, visible roof + SW/SE facades)
func _generate_house_building(path: String) -> void:
	var img := Image.create(64, 56, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	# Base diamond footprint spans x: 0..63, y: 24..55 (height 32, center (31.5, 39.5))
	# Walls rise vertically from base diamond upwards by 16 pixels
	# SW Wall (facing South-West): x: 0..31, y: 20..46
	for y in range(20, 48):
		for x in range(4, 32):
			var base_y := 36 + int(float(x) * 0.5)
			if y <= base_y and y >= base_y - 20:
				var col := COL_EARTH_LIGHT # Plaster / Timber
				if (x % 6 == 0) or (y % 10 == 0):
					col = COL_EARTH_DEEP # Timber beam
				img.set_pixel(x, y, col)
				
	# SE Wall (facing South-East, shaded): x: 32..60, y: 20..48
	for y in range(20, 48):
		for x in range(32, 60):
			var base_y := 52 - int(float(x - 32) * 0.5)
			if y <= base_y and y >= base_y - 20:
				var col := COL_EARTH_MID # Shaded wall
				if ((x - 32) % 6 == 0) or (y % 10 == 0):
					col = COL_EARTH_DARKEST # Shaded timber beam
				img.set_pixel(x, y, col)

	# Door on SW Wall
	for y in range(32, 42):
		for x in range(14, 20):
			img.set_pixel(x, y, COL_EARTH_DARKEST)
			
	# Window on SE Wall
	for y in range(28, 34):
		for x in range(42, 48):
			img.set_pixel(x, y, COL_WATER_SHALLOW)
			
	# Gabled Rooftop (slanted plane facing NW and NE)
	# Ridge along y: 4..12, eaves overhang down to y: 22
	for y in range(4, 24):
		for x in range(2, 62):
			var cx := 31.5
			var dist_x := absf(float(x) - cx)
			var expected_y := 6.0 + (dist_x * 0.45)
			if y >= int(expected_y) and y <= int(expected_y) + 3:
				var col := COL_CRIMSON # Red tile roof
				if x < 32:
					col = Color("#ba3b49") # NW light slope
				else:
					col = Color("#751923") # SE shaded slope
				if (x + y) % 4 == 0:
					col = COL_EARTH_DARKEST # Shingle outline
				img.set_pixel(x, y, col)
				
	img.save_png(path)
	print("Generated: %s" % path)

## 7. Town Hall (96x80 px, 3x3 footprint = 96x48 base diamond, visible roof + clock tower)
func _generate_townhall_building(path: String) -> void:
	var img := Image.create(96, 80, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	# Stone Walls
	for y in range(32, 70):
		for x in range(6, 48):
			var base_y := 52 + int(float(x) * 0.5)
			if y <= base_y and y >= base_y - 28:
				var col := COL_STONE_LIGHT
				if (x % 8 == 0) or (y % 6 == 0):
					col = COL_STONE_DEEP # Stone brick line
				img.set_pixel(x, y, col)
				
	for y in range(32, 70):
		for x in range(48, 90):
			var base_y := 76 - int(float(x - 48) * 0.5)
			if y <= base_y and y >= base_y - 28:
				var col := COL_STONE_MID
				if ((x - 48) % 8 == 0) or (y % 6 == 0):
					col = COL_STONE_DARKEST # Shaded stone brick line
				img.set_pixel(x, y, col)
				
	# Grand Arched Doorway (SW facade)
	for y in range(48, 64):
		for x in range(22, 34):
			img.set_pixel(x, y, COL_EARTH_DARKEST)
			
	# Grand Roof
	for y in range(16, 40):
		for x in range(4, 92):
			var cx := 47.5
			var dist_x := absf(float(x) - cx)
			var exp_y := 18.0 + (dist_x * 0.40)
			if y >= int(exp_y) and y <= int(exp_y) + 4:
				var col := (COL_STONE_SPECULAR if x < 48 else COL_STONE_MID)
				img.set_pixel(x, y, col)

	# Central Clock Tower (x: 40..56, y: 2..28)
	for y in range(4, 28):
		for x in range(42, 54):
			var col := (COL_STONE_LIGHT if x < 48 else COL_STONE_MID)
			img.set_pixel(x, y, col)
	# Spire
	for y in range(0, 5):
		img.set_pixel(47, y, COL_GOLD)
		img.set_pixel(48, y, COL_GOLD_DARK)
	# Clock face
	for y in range(12, 16):
		for x in range(45, 49):
			img.set_pixel(x, y, COL_CREAM)
	img.set_pixel(46, 13, COL_STONE_DARKEST)
	img.set_pixel(46, 14, COL_STONE_DARKEST)

	img.save_png(path)
	print("Generated: %s" % path)

## 8. Farm Building (64x40 px, 2x2 footprint, barn + crops plot)
func _generate_farm_building(path: String) -> void:
	var img := Image.create(64, 40, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	# Crop Plot (Tilled soil in isometric rows)
	for y in range(12, 36):
		for x in range(4, 42):
			if _is_inside_diamond(x, y - 6, 48, 24):
				var col := (COL_EARTH_DEEP if (x + y) % 3 == 0 else COL_EARTH_MID)
				if (x * 2 + y) % 5 == 0:
					col = COL_FOLIAGE_LIGHT # Wheat / Sprouts
				img.set_pixel(x, y, col)
				
	# Small Rustic Barn (East side)
	for y in range(8, 28):
		for x in range(36, 58):
			var col := COL_EARTH_LIGHT
			if x >= 46:
				col = COL_EARTH_MID
			if y < 14:
				col = COL_FOLIAGE_DRY # Thatch roof
			img.set_pixel(x, y, col)
			
	img.save_png(path)
	print("Generated: %s" % path)

## 9. Storehouse (64x56 px, 2x2 footprint, sturdy wooden warehouse + crates)
func _generate_storehouse_building(path: String) -> void:
	var img := Image.create(64, 56, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	# Heavy Timber Frame
	for y in range(20, 48):
		for x in range(4, 60):
			var base_y := (36 + int(float(x) * 0.5)) if x < 32 else (52 - int(float(x - 32) * 0.5))
			if y <= base_y and y >= base_y - 22:
				var col := (COL_EARTH_MID if x < 32 else COL_EARTH_DEEP)
				if (x % 5 == 0) or (y % 8 == 0):
					col = COL_EARTH_DARKEST # Iron reinforcement
				img.set_pixel(x, y, col)
				
	# Barrel / Crate outside
	for y in range(40, 48):
		for x in range(10, 16):
			img.set_pixel(x, y, COL_EARTH_LIGHT)
			
	# Roof
	for y in range(8, 24):
		for x in range(2, 62):
			var cx := 31.5
			var dist_x := absf(float(x) - cx)
			var exp_y := 10.0 + (dist_x * 0.40)
			if y >= int(exp_y) and y <= int(exp_y) + 3:
				var col := (COL_STONE_LIGHT if x < 32 else COL_STONE_DEEP) # Slate shingle
				img.set_pixel(x, y, col)

	img.save_png(path)
	print("Generated: %s" % path)

## 10. Woodcutter Camp (64x48 px, 2x2 footprint, timber shed + log piles)
func _generate_woodcutter_building(path: String) -> void:
	var img := Image.create(64, 48, false, Image.FORMAT_RGBA8)
	img.fill(COL_TRANSPARENT)
	
	# Open Log Canopy
	for y in range(16, 38):
		for x in range(8, 40):
			if (x == 10 or x == 36) and y >= 20:
				img.set_pixel(x, y, COL_EARTH_DARKEST) # Pillars
			elif y < 22:
				img.set_pixel(x, y, (COL_EARTH_LIGHT if x < 24 else COL_EARTH_DEEP)) # Roof
				
	# Log Piles (Isometric stacked logs)
	for y in range(28, 42):
		for x in range(32, 56):
			var col := COL_EARTH_MID
			if (x % 6 == 0):
				col = COL_EARTH_LIGHT # Tree ring end
			elif (y % 4 == 0):
				col = COL_EARTH_DARKEST
			img.set_pixel(x, y, col)
			
	img.save_png(path)
	print("Generated: %s" % path)
