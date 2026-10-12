# KINGDOMS UNBOUND — ASSET STYLE GUIDE & VISUAL SPECIFICATION
**Version:** 1.0 — Authoritative Visual Standard  
**Perspective:** 2D Isometric / Dimetric (2:1 Ratio, Three-Quarter Top-Down)  
**Target Engine:** Godot 4.x (2D Pipeline)  
**Primary Visual Reference:** `docs/reference/kingdom_visual_reference.png`  

---

## 1. VISUAL NORTH STAR & ARTISTIC GOALS

KINGDOMS UNBOUND is a medieval-fantasy kingdom and colony management simulation rendered in crisp, deliberate pixel art. The visual presentation must convey tactile weight, architectural depth, and bustling life.

### 1.1. Authoritative Reference
All visual production, asset creation, and scene composition must align with `docs/reference/kingdom_visual_reference.png`.

Key characteristics demonstrated in the reference:
- **Diamond-shaped ground tiles** forming an isometric grid.
- **Three-quarter perspective** showcasing visible building rooftops and prominent front-facing facades.
- **Unified perspective and lighting** shared across terrain, structures, vegetation, resource nodes, walls, and citizens.
- **Clear depth sorting (Y-sorting)** allowing citizens and props to naturally occlude or be occluded by structures and terrain.
- **High legibility:** Restrained, readable terrain surfaces contrasted against sharply defined structures, interactive units, and UI overlays.

### 1.2. Strict Anti-Goals
- **NO straight overhead / flat top-down (90° bird's-eye) view.** Flat top-down perspectives where only roofs or character crowns are visible are strictly prohibited.
- **NO arbitrary sprite squashing or distortion.** Sprites must not be flattened into 2D rectangles to force-fit tile bounding boxes; objects feature vertical height projecting upward into screen space.
- **NO mixed pixel scales ("pixel salad").** All sprites must share a uniform 1:1 pixel scale at default zoom (1 sprite texel = 1 screen pixel at 1× zoom).
- **NO bilinear or anti-aliased texture filtering.** All pixel assets must render with crisp nearest-neighbor sampling.

---

## 2. PROJECTION MATHEMATICS & GEOMETRY

### 2.1. Standard 2:1 Dimetric ("Isometric") Projection
In classical 2D game pixel art, true isometric projection (30° inclination, $\tan(30^\circ) \approx 0.577$) results in uneven, aliased pixel stair-stepping. Instead, the game uses the industry-standard **2:1 dimetric projection** (commonly referred to as isometric in video games):

- **Horizontal-to-Vertical Pixel Step:** Exactly $2 : 1$ (for every 2 horizontal pixels, the grid line advances 1 vertical pixel).
- **Projection Angle:** $\arctan(0.5) \approx 26.565^\circ$.
- **Ground Tile Aspect Ratio:** Exactly $2 : 1$ (width is twice the height).

### 2.2. Tile Dimension Analysis & Selection
The ground tile projection uses a base diamond size of **32 pixels wide by 16 pixels high (32 × 16 px)**.

#### Comparative Evaluation:
| Tile Option | Bounding Size | Area (px²) | 64×64 World Pixel Span | Evaluation & Rationale |
|---|---|---|---|---|
| **16 × 8 px** | 16 × 8 | 64 px² | 1024 × 512 px | **Rejected.** Far too small for rich terrain textures. Grass tufts, tilled soil, cobblestone, and water edges become muddy single-pixel noise. Citizen sprites would be forced into 10–14 px heights, severely hurting readability and character personality. |
| **64 × 32 px** | 64 × 32 | 1024 px² | 4096 × 2048 px | **Rejected.** Quadruples asset drawing requirements. Character sprites would need to be 48–64 px tall and buildings 120–200 px tall. Viewport coverage on standard 1080p/720p monitors would be too narrow, obscuring macro colony layout and management overview. |
| **32 × 16 px (Selected)** | **32 × 16** | **256 px²** | **2048 × 1024 px** | **Selected standard.** The classic sweet spot for isometric strategy games. Provides ample space for expressive terrain textures and distinct multi-tile building footprints while keeping asset creation nimble. At 1080p, the full 64×64 world is easily navigated with 1×–2.5× camera zoom levels. |

### 2.3. Base Diamond Tile Geometry
A standard 32 × 16 ground tile centered at $(0, 0)$ is defined by four outer vertices:
- **Top vertex:** $(0, -8)$
- **Right vertex:** $(+16, 0)$
- **Bottom vertex:** $(0, +8)$
- **Left vertex:** $(-16, 0)$

---

## 3. COORDINATE DECOUPLING: SIMULATION GRID VS. SCREEN PROJECTION

The game strictly decouples the discrete logical world simulation from its 2D isometric screen presentation.

```
+------------------------------------------------------------------------+
|                      SIMULATION LAYER (Pure Data)                      |
|                                                                        |
|   Logical Grid: 64 x 64 Discrete Cells                                 |
|   Coordinates: Vector2i(grid_x, grid_y)  where 0 <= grid_x, grid_y < 64 |
|   Owned by: WorldState, NavigationSystem, JobSystem, BuildingSystem    |
|   Systems know ONLY integer grid cells, adjacency, and Manhattan dist. |
+------------------------------------------------------------------------+
                                    |
                    Isometric Coordinate Transform
                                    v
+------------------------------------------------------------------------+
|                     PRESENTATION LAYER (Godot 2D)                      |
|                                                                        |
|   Rendered Space: Continuous 2D Pixels                                 |
|   Coordinates: Vector2(screen_x, screen_y)                             |
|   Owned by: IsometricView, TileMapLayer, Entity Node2Ds, Camera2D      |
|   Manages: 32x16 diamond tiles, sprite offsets, Y-sorting, zoom        |
+------------------------------------------------------------------------+
```

### 3.1. Coordinate Transformations & Cell Selection

#### A. Coordinate Spaces
- **Global Viewport / Screen Space:** Raw cursor coordinate obtained via `get_global_mouse_position()`.
- **Map-Local Space:** Coordinate relative to the world / `TileMapLayer` origin `(0, 0)`. Converted via:
  ```gdscript
  var local_pos: Vector2 = tile_map_layer.to_local(get_global_mouse_position())
  ```
  All forward and inverse projection formulas operate strictly within this map-local space.
- **Logical Simulation Space:** Discrete integer coordinates `Vector2i(grid_x, grid_y)` where $0 \le \text{grid\_x}, \text{grid\_y} < 64$.

#### B. Forward Mapping (Logical Grid Cell $\to$ Map-Local Pixel Center):
Given integer cell coordinates $(\text{grid\_x}, \text{grid\_y})$ on the 64×64 grid:
$$\text{local\_x} = (\text{grid\_x} - \text{grid\_y}) \times \frac{W}{2} = (\text{grid\_x} - \text{grid\_y}) \times 16.0$$
$$\text{local\_y} = (\text{grid\_x} + \text{grid\_y}) \times \frac{H}{2} = (\text{grid\_x} + \text{grid\_y}) \times 8.0$$

#### C. Inverse Mapping (Map-Local Pixel $\to$ Logical Grid Cell):
To resolve any arbitrary map-local point $(\text{local\_x}, \text{local\_y})$ to its containing diamond tile:
1. Compute continuous isometric axis coordinates $(u, v)$:
   $$u = \frac{\text{local\_x}}{32.0} + \frac{\text{local\_y}}{16.0}$$
   $$v = \frac{\text{local\_y}}{16.0} - \frac{\text{local\_x}}{32.0}$$
2. Cell $(g_x, g_y)$ has its center at $(u = g_x, v = g_y)$ and its diamond boundaries at $u \in [g_x - 0.5, g_x + 0.5)$ and $v \in [g_y - 0.5, g_y + 0.5)$.
3. The mathematically exact cell selection formula (shifting by $+0.5$ before flooring to properly center the diamond around the tile origin) is:
   $$\text{grid\_x} = \left\lfloor u + 0.5 \right\rfloor = \left\lfloor \frac{\text{local\_x}}{32.0} + \frac{\text{local\_y}}{16.0} + 0.5 \right\rfloor$$
   $$\text{grid\_y} = \left\lfloor v + 0.5 \right\rfloor = \left\lfloor \frac{\text{local\_y}}{16.0} - \frac{\text{local\_x}}{32.0} + 0.5 \right\rfloor$$

*(Note on previous formula flaw: Taking $\lfloor u \rfloor$ without $+0.5$ shifted the sampling window by a half-tile to the top vertex $(0, -8)$, splitting the $(0, 0)$ cell and causing points in the upper-left quadrant to map incorrectly to negative indices).*

#### D. Godot 4 TileMapLayer Native Conversion
When using Godot 4's `TileMapLayer` configured with an isometric `TileSet` (`tile_shape = TileSet.TILE_SHAPE_ISOMETRIC`, `tile_size = Vector2i(32, 16)`), Godot provides built-in C++ conversion methods:
```gdscript
# Mouse to cell
var local_mouse: Vector2 = tile_map_layer.to_local(get_global_mouse_position())
var cell: Vector2i = tile_map_layer.local_to_map(local_mouse)

# Cell to local tile center
var tile_center_local: Vector2 = tile_map_layer.map_to_local(cell)
```

#### E. Map-Boundary Validation & Cell Consistency
Every selected cell must be verified against the finite 64×64 map boundaries:
```gdscript
func is_in_bounds(cell: Vector2i) -> bool:
    return cell.x >= 0 and cell.x < 64 and cell.y >= 0 and cell.y < 64
```
- **Unified Selection Rule:** Cursor highlighting, tile selection, and building placement MUST resolve the mouse position through the exact same coordinate mapping and boundary check.
- **Multi-Tile Buildings:** For a $K \times M$ building (e.g. 2×2 or 3×3) anchored at root `cell`, every cell `Vector2i(cell.x + dx, cell.y + dy)` for $dx \in [0, K-1], dy \in [0, M-1]$ must satisfy `is_in_bounds()` and be unoccupied. If any cell is out-of-bounds or blocked, placement is invalid.
- **Out-of-Bounds Behavior:** If the cursor falls outside the 64×64 map diamond, cursor highlighting is suppressed (or displayed in an invalid red state), and placement actions are rejected.

#### F. Coordinate Transformation Validation Cases
The following test cases demonstrate the mathematical correctness of the inverse mapping across centers, interior offsets, vertices, and out-of-bounds positions:

| Test Case | Map-Local Position $(x, y)$ | Continuous $(u, v)$ | Resolved Cell $(g_x, g_y)$ | Boundary Status | Description |
|---|---|---|---|---|---|
| **Origin Center** | $(0.0, 0.0)$ | $(0.0, 0.0)$ | `(0, 0)` | Valid | Center of origin tile $(0, 0)$ |
| **Origin Left Interior** | $(-8.0, 0.0)$ | $(-0.25, 0.25)$ | `(0, 0)` | Valid | Inside $(0, 0)$, left of center |
| **Origin Top Interior** | $(0.0, -4.0)$ | $(-0.25, -0.25)$ | `(0, 0)` | Valid | Inside $(0, 0)$, top of center |
| **Origin Right Interior** | $(8.0, 0.0)$ | $(0.25, -0.25)$ | `(0, 0)` | Valid | Inside $(0, 0)$, right of center |
| **Origin Bottom Interior** | $(0.0, 4.0)$ | $(0.25, 0.25)$ | `(0, 0)` | Valid | Inside $(0, 0)$, bottom of center |
| **Top Vertex Boundary** | $(0.0, -8.0)$ | $(-0.5, -0.5)$ | `(0, 0)` | Valid | Top vertex of $(0, 0)$ (half-open) |
| **Adjacent Cell $(1, 0)$** | $(16.0, 8.0)$ | $(1.0, 0.0)$ | `(1, 0)` | Valid | Center of adjacent South-East tile |
| **Adjacent Cell $(0, 1)$** | $(-16.0, 8.0)$ | $(0.0, 1.0)$ | `(0, 1)` | Valid | Center of adjacent South-West tile |
| **Diagonal Cell $(1, 1)$** | $(0.0, 16.0)$ | $(1.0, 1.0)$ | `(1, 1)` | Valid | Center of South tile $(1, 1)$ |
| **Map Corner $(63, 63)$** | $(0.0, 1008.0)$ | $(63.0, 63.0)$ | `(63, 63)` | Valid | Furthest South map tile center |
| **Outside North-West** | $(-32.0, 0.0)$ | $(-1.0, 1.0)$ | `(-1, 1)` | **Invalid** | Negative $X$, rejected by boundary check |
| **Outside Top Apex** | $(0.0, -8.1)$ | $(-0.506, -0.506)$ | `(-1, -1)` | **Invalid** | Beyond map top, rejected |
| **Outside South Apex** | $(0.0, 1024.0)$ | $(64.0, 64.0)$ | `(64, 64)` | **Invalid** | Beyond map bottom, rejected |

### 3.2. Sub-Tile Movement for Characters
While logical pathfinding plans paths cell-by-cell in `Vector2i`, visual citizen movement interpolates smoothly between tile screen positions using continuous float positions `Vector2(local_x, local_y)`. Logical arrival at the next tile is triggered when the entity reaches the target cell center.

---

## 4. SPRITE SCALE, DIMENSIONS & BUILDING PROPORTIONS

### 4.1. Entity Scale Hierarchy
Sprites must not be squashed into flat 32 × 16 boxes. Ground tiles establish ground contact; all physical entities extend vertically upwards along the negative Y axis ($-Y$).

```
             /\
            /  \       <-- Visible Rooftop (tilted planes facing NW & NE)
           /    \
          +------+
          |      |     <-- Front-facing Facades (vertical walls facing SW & SE)
          |      |
          \      /
           \    /      <-- Diamond Ground Footprint (anchored to grid, 32x16 per tile)
            \  /
             \/
```

### 4.2. Category Dimensions & Specifications

| Entity Type | Grid Footprint | Base Diamond Size | Visible Height Range | Default Canvas / Frame Size | Anchor / Ground Pivot |
|---|---|---|---|---|---|
| **Ground Tile (Terrain)** | 1 × 1 cell | 32 × 16 px | 16 px (flat) / up to 24 px (cliff) | 32 × 16 px (or 32 × 24 px) | Diamond center: `(16, 8)` |
| **Citizen (Adult Human)** | 1 × 1 cell | Center point | 22 – 26 px (width: 12–16 px) | 24 × 32 px standard | Feet contact: `(12, 30)` |
| **Small Prop / Rock / Well** | 1 × 1 cell | 32 × 16 px | 16 – 32 px | 32 × 32 px | Base center: `(16, 24)` |
| **Tree (Pine / Oak)** | 1 × 1 cell | 32 × 16 px | 40 – 64 px | 32 × 64 px | Trunk base: `(16, 56)` |
| **Modular Stone Wall** | 1 × 1 cell | 32 × 16 px | 24 – 32 px | 32 × 32 px / 32 × 48 px | Wall base center: `(16, 24)` |
| **Small Building (Watchtower)** | 1 × 1 cell | 32 × 16 px | 36 – 48 px | 32 × 48 px | Footprint center: `(16, 40)` |
| **Medium Building (House, Farm, Storehouse, Mine)** | 2 × 2 cells | 64 × 32 px | 48 – 64 px | 64 × 64 px / 64 × 80 px | Base center: `(32, 48)` or front edge |
| **Large Building (Town Hall, Barracks, Market)** | 3 × 3 cells | 96 × 48 px | 64 – 96 px | 96 × 96 px / 96 × 112 px | Base center: `(48, 72)` or front edge |

### 4.2.1. Standardized Citizen Sprite Specifications
To ensure consistency across character art assets, animation sheets, scene hierarchies, and physics/navigation, the following standards govern citizen sprites:

1. **Sprite Canvas Dimensions (Frame Bounds):**
   - **Default Frame Size:** Exactly **24 × 32 pixels** per animation cell.
   - All animation frames in a character's spritesheet must share identical 24×32 px boundaries.
2. **Visible Character Dimensions:**
   - **Visible Width:** Approximately **12 – 16 pixels**.
   - **Visible Height:** Approximately **22 – 26 pixels**.
   - **Proportion Preservation (No Forced Sizing):** The character figure does NOT fill the entire 24×32 canvas. The remaining 6–10 px of vertical headroom and 4–6 px of horizontal margin provide necessary clearance for hats, helmets, walk-cycle vertical bobbing, and held tools (axes, pickaxes, hammers, baskets) without requiring frame resizing or sprite stretching.
3. **Ground-Contact Pivot / Foot Position:**
   - Positioned at **Vector2(12, 30)** within the 24×32 px canvas (horizontally centered at $x=12$, vertically placed 2 pixels above the canvas bottom at $y=30$ to accommodate a subtle 1-pixel contact shadow).
4. **World-Space Footprint & Y-Sorting Anchor:**
   - **Simulation Footprint:** 1 × 1 cell on the logical grid (`Vector2i`).
   - **Visual Scene Tree:** The character's parent `Node2D` has its `position` set to the tile center (`tile_map_layer.map_to_local(cell)`).
   - **Sprite Visual Offset:** The child `Sprite2D` has its texture offset set to `Vector2(-12, -30)`. This guarantees that the character's feet land precisely at the node's local `(0, 0)` origin, allowing Godot's `y_sort_enabled = true` to calculate sorting using the actual foot contact line.
5. **Flexibility & Non-Standard Assets:**
   - The 24×32 canvas / 22–26 px visible figure is the authoritative default standard for standard humanoid citizens.
   - Specialized units (e.g. mounted riders, tall banners, oversized siege equipment) may use larger canvas sizes (such as 32×32 px or 32×48 px) when justified by gameplay, provided their ground-contact pivot remains strictly anchored at their base/feet.

### 4.3. Building Architectural Rules
1. **Visible Rooftops:** Every building features visible roof planes angled toward the North-West and North-East. Roof materials include slate tile, golden thatch, and wooden shakes.
2. **Front-Facing Facades:** The two visible exterior walls face South-West and South-East, directly angled toward the player's view. Doors, timber framings, windows, and entry porches are placed along these two front surfaces.
3. **Hidden Rear Facades:** Walls facing North-West and North-East are occluded by roofs and interiors and are not drawn.
4. **Footprint Alignment:** Multi-tile buildings must align precisely with multi-cell diamond bases:
   - 2×2 buildings occupy a 64 × 32 px diamond base.
   - 3×3 buildings occupy a 96 × 48 px diamond base.

---

## 5. DEPTH SORTING & Y-SORT ARCHITECTURE

Correct visual depth sorting is vital in an isometric perspective. Without proper Y-sorting, walking characters clip unnaturally through building roofs or render behind grass tiles.

### 5.1. Godot 2D Y-Sort Configuration
- The main world container (`Node2D` holding entities) must have `y_sort_enabled = true`.
- The `TileMapLayer` or entity parent containers must also have `y_sort_enabled = true`.
- All entity nodes (citizens, trees, buildings, props) must be direct children of a Y-sorted parent or participate in the Y-sort hierarchy.

### 5.2. Strict Anchor / Pivot Placement Rule
The sorting key in Godot 2D Y-sort is the global `position.y` of the node.
- **Rule:** The `position.y` of every entity node must be placed at the **ground-contact plane** (where the object meets the soil).
- **Citizen Pivot:** Positioned strictly between the citizen's feet on the ground plane (`Vector2(-12, -30)` offset relative to node origin).
- **Tree Pivot:** Positioned at the base of the trunk where it penetrates the earth.
- **Building Pivot:** Positioned at the center of the ground-contact diamond base (or bottom-most front edge of the base footprint).

### 5.3. Occlusion Behavior
With this pivot rule, Godot's Y-sort naturally handles depth:
- When a citizen moves behind a building (smaller screen Y / further North), the building's Y position is greater $\implies$ the building renders over the citizen, properly hiding them behind walls and roofs.
- When a citizen moves in front of a building (larger screen Y / further South), the citizen's Y position is greater $\implies$ the citizen renders on top of the building's front walls and doorstep.

---

## 6. COLOR PALETTE & LIGHTING SPECIFICATION

The game uses an authoritative **27-Color Core Fantasy Palette** inspired by `docs/reference/kingdom_visual_reference.png`. High saturation is reserved for gameplay feedback, interactive highlights, and UI elements.

### 6.1. Core 27-Color Palette Swatches
The palette consists of exactly 27 defined hex swatches organized into 5 cohesive functional material ramps:

#### Foliage & Flora (Deep Pinetree Greens & Moss):
- `#122420` — Deepest pine shadow / dark outline
- `#1e3e36` — Pine shadow tone
- `#2d5849` — Forest foliage mid-tone
- `#44775d` — Meadow grass base
- `#649c74` — Sunlit grass / foliage highlight
- `#8ec49a` — Top grass tuft highlight

#### Earth, Dirt & Timber (Loam, Soil & Wood):
- `#221610` — Darkest earth shadow / bark outline
- `#3b2416` — Dark loam / wet mud
- `#593a24` — Stained timber / dry soil
- `#7d5435` — Wood plank mid-tone / path gravel
- `#aa784c` — Light timber / thatch shadow
- `#d8a46b` — Straw thatch / bright wood highlight

#### Stone, Masonry & Metal (Slate Grays & Iron):
- `#181c24` — Deep basalt shadow / masonry outline
- `#2c3340` — Dark stone wall shadow
- `#444f60` — Cool slate stone mid-tone
- `#667488` — Weathered masonry
- `#92a0b2` — Bright stone highlight / polished iron
- `#c4d0de` — Sharp specular stone highlight

#### Water & Atmosphere (Teal Aqua & Depths):
- `#0e202c` — Abyssal pond depth
- `#183c50` — Deep water body
- `#28607a` — Clear pond mid-tone
- `#468ea8` — Shallow river / water edge
- `#7eccdc` — Water ripple foam / wave highlight

#### Accents & Gameplay Elements:
- `#e09c2a` — Warm gold / Treasury coin / lantern light
- `#f8d458` — Gold highlight / high-tier reward
- `#9c2834` — Royal banner crimson / enemy marker
- `#30d0c4` — Magic crystal cyan / card highlight / selection diamond

*(Note on Palette Discipline: These 27 documented swatches form the complete, authoritative core palette for the MVP. All primary gameplay sprites, tiles, and props must draw strictly from this set. If additional transitional shades or specialized UI borders are required during Phase 9 polish, they must strictly interpolate within these five established material ramps rather than introducing arbitrary disconnected hues).*

### 6.2. Directional Lighting & Shading Model
- **Primary Light Source:** Sun positioned at the **North-West** (upper-left of screen, elevated at approximately 45°).
- **Surface Lighting Values:**
  - **Rooftops & North-West Facing Planes:** Receive direct light (brightest ramp color).
  - **South-West Facades (Facing Left):** Receive direct/ambient light (mid-tone ramp color).
  - **South-East Facades (Facing Right):** Fall into primary shadow (dark ramp color).
  - **Cast Shadows:** Subtle contact shadows cast slightly toward the South-East (lower-right) beneath tree canopies, citizen feet, and building eaves.

---

## 7. OUTLINES & PIXEL ART DISCIPLINE

1. **Selective Dark Outlines:**
   - Exterior object silhouettes must use dark tinted outlines matched to the material (e.g. deep charcoal `#181c24` for stone; dark bark `#221610` for wood; deep pine `#122420` for foliage).
   - Avoid solid harsh black (`#000000`) across all edges. Black should be reserved for deep crevices or high-contrast separation.
2. **No Orphan Single Pixels ("Confetti Noise"):**
   - Pixels must be grouped in readable clusters. Avoid single stray pixels scattered across surfaces.
3. **Consistent Pixel Density:**
   - Assets must not mix pixel sizes. A citizen's eye pixel, a brick pixel, and a grass blade pixel must all be the exact same screen dimension at 1× zoom.
4. **No Sub-Pixel Anti-Aliasing on Edges:**
   - Edges against transparent backgrounds must be completely crisp (either fully opaque or fully transparent). No semi-transparent blended boundary pixels.

---

## 8. ANIMATION CONVENTIONS

### 8.1. Directional Framework
Characters use an **isometric 4-directional setup**:
1. **South-West (SW):** Facing front-left (towards camera).
2. **South-East (SE):** Facing front-right (towards camera).
3. **North-West (NW):** Facing back-left (away from camera).
4. **North-East (NE):** Facing back-right (away from camera).

*(Note: In 2D isometric engines, South-East and South-West frames can often be mirrored along the X-axis for symmetrical characters to conserve sprite sheet memory, provided asymmetric equipment or handedness is not required).*

### 8.2. Citizen Animation States & Frame Counts
- **Idle:** 2 – 4 frames, looping at 4 – 6 fps (subtle breathing, slight weight shift).
- **Walk:** 4 – 6 frames, looping at 6 – 8 fps (stride with clear leg crossover and ground contact).
- **Work / Action (Chop, Mine, Farm, Build):** 4 – 6 frames, looping at 6 – 8 fps (anticipation, impact strike, recovery).
- **Carry / Haul (Walk with crate/sack):** 4 – 6 frames, looping at 6 – 8 fps.

### 8.3. Spritesheet Standards
- All frames in a single spritesheet must share identical width and height.
- The ground-contact pivot must remain at the exact same pixel offset across all frames of an animation.

---

## 9. GODOT 4 ASSET IMPORT PIPELINE & PROJECT SETTINGS

To preserve pixel-perfect rendering in Godot 4:

### 9.1. Texture Import Settings
All PNG textures in `res://assets/` must be imported with:
- **Filter:** `Nearest` (`TEXTURE_FILTER_NEAREST`).
- **Mipmaps:** `Generate Mipmaps = false` (prevents blurry downsampling during zoom).
- **Compression Mode:** `Lossless`.
- **Repeat:** `Disabled` (except dedicated tiling patterns).

### 9.2. Display & Pixel Snapping Configuration
In `project.godot`:
- `display/window/stretch/mode = "canvas_items"`
- `display/window/stretch/aspect = "expand"` (or `"keep"`)
- `rendering/2d/snap/snap_2d_transforms_to_pixel = true`
- `rendering/2d/snap/snap_2d_vertices_to_pixel = true`
- `rendering/textures/canvas_textures/default_texture_filter = 0` (Nearest)

These settings prevent shimmering, sub-pixel edge tearing, and unwanted texture interpolation when moving the camera or scaling the window.

### 9.3. Asset Directory Hierarchy
All visual assets must be organized consistently in the project filesystem:
```
res://assets/
├── sprites/
│   ├── terrain/       # 32x16 ground tiles (grass, dirt, water, paths, crops)
│   ├── buildings/     # 1x1, 2x2, 3x3 isometric building sprites
│   ├── characters/    # Citizen directional spritesheets
│   ├── props/         # Trees, rocks, ore deposits, modular walls
│   └── effects/       # Smoke, dust puffs, construction dust
└── ui/
    ├── icons/         # Resource icons (Food, Wood, Stone, etc.)
    ├── panels/        # Isometric 9-slice frames and card templates
    └── cursors/       # Diamond grid highlight overlays (32x16, 64x32, 96x48)
```

---

## 10. VISUAL-VALIDATION GATE SPECIFICATION

Before producing or importing a large collection of final game assets in Phase 9, a dedicated **Visual-Validation Gate** must be satisfied.

### 10.1. Required Test Scene
The project must include and pass the test scene:
`res://scenes/test/visual_validation_test.tscn`

### 10.2. Acceptance Checklist for the Gate
To pass the Visual-Validation Gate, the test scene must demonstrate:
1. **Terrain:** 2:1 isometric diamond ground tiles (32 × 16 px) rendering seamlessly with zero pixel gaps or seam bleeding.
2. **Props:** At least two trees and one rock prop rendered in proper 2:1 isometric perspective.
3. **Building:** At least one multi-tile building (e.g. 2×2 House or 3×3 Town Hall) displaying visible tilted rooftops and front-facing facades (SW & SE).
4. **Moving Citizen:** One animated citizen moving across the isometric grid.
5. **Interactive Diamond Highlighting:** A 32 × 16 px diamond cursor overlay following the mouse and snapping precisely to the grid cell under the cursor.
6. **Flawless Depth / Y-Sorting:**
   - Citizen walking to a tile North of the building/tree is naturally hidden behind the roof/canopy.
   - Citizen walking to a tile South of the building/tree renders cleanly in front of the walls/trunk.
   - Zero visual popping, flickering, or sorting layer inversions.
7. **Crisp Nearest-Neighbor Pixels:** No blurred edges or bilinear smoothing at default or zoomed camera scales.

Only after this test scene is verified and passes inspection may large asset batches be produced and integrated into the project.
