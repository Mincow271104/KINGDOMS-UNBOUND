class_name TechTree
extends RefCounted
## Technology Definitions & Tech Tree Configuration for KINGDOMS UNBOUND.
## Conforms to GDD Part IX: 4 branches with 10 data-driven technologies.

const BRANCH_SURVIVAL: String = "survival"
const BRANCH_PRODUCTION: String = "production"
const BRANCH_MILITARY: String = "military"
const BRANCH_MAGIC: String = "magic"

const BRANCH_NAMES: Dictionary = {
	BRANCH_SURVIVAL: "Sinh Tồn & Nông Nghiệp",
	BRANCH_PRODUCTION: "Sản Xuất & Vận Tải",
	BRANCH_MILITARY: "Quân Sự & Phòng Thủ",
	BRANCH_MAGIC: "Huyền Thuật & Tri Thức"
}

const TECHNOLOGIES: Dictionary = {
	"crop_rotation": {
		"id": "crop_rotation",
		"name": "Luân Canh Nông Nghiệp",
		"branch": BRANCH_SURVIVAL,
		"cost": {EconomyConfig.RES_WOOD: 20, EconomyConfig.RES_FOOD: 10},
		"duration_hours": 12.0,
		"prereqs": [],
		"description": "Tăng 20% sản lượng lương thực thu hoạch từ Nông Trại."
	},
	"food_preservation": {
		"id": "food_preservation",
		"name": "Bảo Quản Thực Phẩm",
		"branch": BRANCH_SURVIVAL,
		"cost": {EconomyConfig.RES_WOOD: 30, EconomyConfig.RES_HERBS: 15},
		"duration_hours": 16.0,
		"prereqs": ["crop_rotation"],
		"description": "Tăng 50% sức chứa kho tạm tại nông trại (từ 50 lên 75)."
	},
	"selective_breeding": {
		"id": "selective_breeding",
		"name": "Chọn Lọc Giống Cây",
		"branch": BRANCH_SURVIVAL,
		"cost": {EconomyConfig.RES_FOOD: 20, EconomyConfig.RES_WOOD: 30, EconomyConfig.RES_HERBS: 10},
		"duration_hours": 24.0,
		"prereqs": ["crop_rotation"],
		"description": "Tăng hiệu suất làm nông vụ Mùa Đông từ 0.5 lên 0.7."
	},
	"advanced_tools": {
		"id": "advanced_tools",
		"name": "Công Cụ Tiên Tiến",
		"branch": BRANCH_PRODUCTION,
		"cost": {EconomyConfig.RES_WOOD: 30, EconomyConfig.RES_STONE: 10},
		"duration_hours": 12.0,
		"prereqs": [],
		"description": "Tăng 25% sản lượng khai thác gỗ của Trại Tiều Phu."
	},
	"improved_hauling": {
		"id": "improved_hauling",
		"name": "Đòn Gánh & Xe Đẩy",
		"branch": BRANCH_PRODUCTION,
		"cost": {EconomyConfig.RES_WOOD: 35, EconomyConfig.RES_STONE: 15},
		"duration_hours": 16.0,
		"prereqs": ["advanced_tools"],
		"description": "Tăng sức mang vác của người vận chuyển từ 10 lên 15 đơn vị."
	},
	"reinforced_storage": {
		"id": "reinforced_storage",
		"name": "Kho Hàng Kiên Cố",
		"branch": BRANCH_PRODUCTION,
		"cost": {EconomyConfig.RES_WOOD: 40, EconomyConfig.RES_STONE: 30},
		"duration_hours": 24.0,
		"prereqs": ["improved_hauling"],
		"description": "Tăng thêm 500 sức chứa cho tất cả tài nguyên tại kho trung tâm."
	},
	"watchtower_survey": {
		"id": "watchtower_survey",
		"name": "Vọng Lâu Tuần Tra",
		"branch": BRANCH_MILITARY,
		"cost": {EconomyConfig.RES_WOOD: 25, EconomyConfig.RES_STONE: 15},
		"duration_hours": 12.0,
		"prereqs": [],
		"description": "Tăng tầm nhìn sương mù (Fog of War) của cư dân thêm +2 ô."
	},
	"fortified_palisade": {
		"id": "fortified_palisade",
		"name": "Tường Rào Phòng Ngự",
		"branch": BRANCH_MILITARY,
		"cost": {EconomyConfig.RES_WOOD: 30, EconomyConfig.RES_STONE: 25},
		"duration_hours": 18.0,
		"prereqs": ["watchtower_survey"],
		"description": "Gia cố công trình, tăng 25% độ bền và sức kháng cự."
	},
	"crystal_resonance": {
		"id": "crystal_resonance",
		"name": "Cộng Hưởng Pha Lê",
		"branch": BRANCH_MAGIC,
		"cost": {EconomyConfig.RES_CRYSTAL: 5, EconomyConfig.RES_WOOD: 20},
		"duration_hours": 16.0,
		"prereqs": [],
		"description": "Tăng 25% tốc độ nghiên cứu các công nghệ tiếp theo."
	},
	"ancient_lore": {
		"id": "ancient_lore",
		"name": "Cổ Thư Khai Sáng",
		"branch": BRANCH_MAGIC,
		"cost": {EconomyConfig.RES_CRYSTAL: 10, EconomyConfig.RES_GOLD: 30},
		"duration_hours": 24.0,
		"prereqs": ["crystal_resonance"],
		"description": "Giải mã phế tích, tăng tỷ lệ nhận thưởng quý hiếm khi khám phá."
	}
}
