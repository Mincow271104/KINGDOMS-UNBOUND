class_name LegacyProfileManager
extends RefCounted
## Authoritative Legacy Fund & Meta-Progression Profile Manager for KINGDOMS UNBOUND.
## Manages cross-world persistent Legacy balance, lifetime statistics, and exactly-once reward claims.
## Follows GDD §XII & §XIII and MASTER_PROMPT constraints.

signal balance_changed(new_balance: int)
signal reward_claimed(reward_id: String, amount: int, source: String, current_balance: int)
signal profile_saved(filepath: String)
signal profile_loaded(filepath: String)

const PROFILE_SCHEMA_VERSION: int = 1
const DEFAULT_PROFILE_PATH: String = "user://legacy_profile.json"
const BACKUP_PROFILE_PATH: String = "user://legacy_profile.json.bak"
const TEMP_PROFILE_PATH: String = "user://legacy_profile.json.tmp"

const VALID_REWARD_SOURCES: Array[String] = [
	"victory",
	"achievement"
]

const ACHIEVEMENTS: Dictionary = {
	"prosperity_victory": {
		"id": "prosperity_victory",
		"title": "Thịnh Vượng Toàn Diện",
		"description": "Duy trì thịnh vượng xuất sắc trong 5 ngày liên tục.",
		"reward_legacy": 100,
		"reward_source": "achievement"
	}
}

var profile_id: String = "legacy_profile_default"
var legacy_balance: int = 0
var lifetime_legacy_earned: int = 0
var lifetime_legacy_spent: int = 0
var claimed_rewards: Dictionary = {} # reward_id (String) -> Dictionary
var unlocked_achievements: Dictionary = {} # achievement_id (String) -> Dictionary
var active_filepath: String = DEFAULT_PROFILE_PATH

static var _instance = null

# -----------------------------------------------------------------------------
# Singleton & Factory Methods
# -----------------------------------------------------------------------------

static func get_instance(filepath: String = "") -> RefCounted:
	if _instance == null:
		var script = load("res://scripts/legacy/legacy_profile_manager.gd")
		_instance = script.new(filepath)
		_instance.load_profile()
	elif not filepath.is_empty() and _instance.active_filepath != filepath:
		_instance.active_filepath = filepath
		_instance.load_profile()
	return _instance

static func set_instance(inst: RefCounted) -> void:
	_instance = inst

static func reset_instance() -> void:
	_instance = null

func _init(filepath: String = "") -> void:
	if not filepath.is_empty():
		active_filepath = filepath
	else:
		active_filepath = DEFAULT_PROFILE_PATH

# -----------------------------------------------------------------------------
# Fail-Closed Data Validation
# -----------------------------------------------------------------------------

static func validate_profile_data(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {"valid": false, "error": "Dữ liệu hồ sơ Legacy phải là Dictionary."}

	if not data.has("schema_version"):
		return {"valid": false, "error": "Thiếu trường 'schema_version' trong hồ sơ Legacy."}
	var sv = data["schema_version"]
	if not (sv is int or (sv is float and floor(float(sv)) == float(sv))):
		return {"valid": false, "error": "Trường 'schema_version' không phải số nguyên."}
	if int(sv) != PROFILE_SCHEMA_VERSION:
		return {"valid": false, "error": "Phiên bản hồ sơ không tương thích (Đọc được %d, yêu cầu %d)." % [int(sv), PROFILE_SCHEMA_VERSION]}

	if not data.has("profile_id"):
		return {"valid": false, "error": "Thiếu trường 'profile_id' trong hồ sơ Legacy."}
	var pid_str = str(data["profile_id"]).strip_edges()
	if pid_str.is_empty():
		return {"valid": false, "error": "Trường 'profile_id' không được để trống."}

	for k in ["legacy_balance", "lifetime_legacy_earned", "lifetime_legacy_spent"]:
		if not data.has(k):
			return {"valid": false, "error": "Thiếu trường '%s' trong hồ sơ Legacy." % k}
		var val = data[k]
		if not (val is int or (val is float and not is_nan(float(val)) and not is_inf(float(val)) and floor(float(val)) == float(val))):
			return {"valid": false, "error": "Trường '%s' phải là số nguyên hợp lệ." % k}
		if int(val) < 0:
			return {"valid": false, "error": "Trường '%s' không được âm (%d)." % [k, int(val)]}

	var bal = int(data["legacy_balance"])
	var earned = int(data["lifetime_legacy_earned"])
	var spent = int(data["lifetime_legacy_spent"])

	# Mathematical balance consistency invariant
	if bal != (earned - spent):
		return {"valid": false, "error": "Không nhất quán số dư: legacy_balance (%d) != earned (%d) - spent (%d)." % [bal, earned, spent]}

	if not data.has("claimed_rewards"):
		return {"valid": false, "error": "Thiếu trường 'claimed_rewards' trong hồ sơ Legacy."}
	var c_rew = data["claimed_rewards"]
	if not (c_rew is Dictionary):
		return {"valid": false, "error": "Mục 'claimed_rewards' phải là Dictionary."}

	var total_claimed_points: int = 0
	for r_id_key in c_rew:
		var r_id_str = str(r_id_key).strip_edges()
		if r_id_str.is_empty():
			return {"valid": false, "error": "Khóa phần thưởng trong 'claimed_rewards' không được rỗng."}

		var r_entry = c_rew[r_id_key]
		if not (r_entry is Dictionary):
			return {"valid": false, "error": "Bản ghi phần thưởng '%s' không phải Dictionary." % r_id_str}

		if not r_entry.has("reward_id"):
			return {"valid": false, "error": "Bản ghi phần thưởng '%s' thiếu trường 'reward_id'." % r_id_str}
		var rec_id = str(r_entry["reward_id"]).strip_edges()
		if rec_id != r_id_str:
			return {"valid": false, "error": "Khóa phần thưởng '%s' không khớp reward_id nội tại '%s'." % [r_id_str, rec_id]}

		if not r_entry.has("source"):
			return {"valid": false, "error": "Phần thưởng '%s' thiếu trường 'source'." % r_id_str}
		var src_str = str(r_entry["source"]).strip_edges()
		if not VALID_REWARD_SOURCES.has(src_str):
			return {"valid": false, "error": "Nguồn phần thưởng '%s' không hợp lệ: '%s'." % [r_id_str, src_str]}

		if not r_entry.has("amount"):
			return {"valid": false, "error": "Phần thưởng '%s' thiếu trường 'amount'." % r_id_str}
		var amt = r_entry["amount"]
		if not (amt is int or (amt is float and not is_nan(float(amt)) and not is_inf(float(amt)) and floor(float(amt)) == float(amt))):
			return {"valid": false, "error": "Số điểm phần thưởng '%s' không phải số nguyên." % r_id_str}
		var amt_int = int(amt)
		if amt_int <= 0:
			return {"valid": false, "error": "Số điểm phần thưởng '%s' phải lớn hơn 0 (%d)." % [r_id_str, amt_int]}

		total_claimed_points += amt_int

	# Claimed rewards total must strictly match lifetime earned
	if total_claimed_points != earned:
		return {"valid": false, "error": "Tổng điểm phần thưởng đã nhận (%d) không khớp lifetime_legacy_earned (%d)." % [total_claimed_points, earned]}

	if data.has("unlocked_achievements"):
		var ach_val = data["unlocked_achievements"]
		if not (ach_val is Dictionary):
			return {"valid": false, "error": "Mục 'unlocked_achievements' phải là Dictionary."}
		for ach_key in ach_val:
			var ach_id_str = str(ach_key).strip_edges()
			if ach_id_str.is_empty():
				return {"valid": false, "error": "Khóa thành tích không được rỗng."}
			var ach_entry = ach_val[ach_key]
			if not (ach_entry is Dictionary):
				return {"valid": false, "error": "Bản ghi thành tích '%s' không phải Dictionary." % ach_id_str}
			if not ach_entry.has("achievement_id"):
				return {"valid": false, "error": "Bản ghi thành tích '%s' thiếu trường 'achievement_id'." % ach_id_str}
			if str(ach_entry["achievement_id"]).strip_edges() != ach_id_str:
				return {"valid": false, "error": "Khóa thành tích '%s' không khớp achievement_id '%s'." % [ach_id_str, str(ach_entry["achievement_id"])]}

	return {"valid": true}

# -----------------------------------------------------------------------------
# Serialization & Atomic Staged Deserialization
# -----------------------------------------------------------------------------

func serialize() -> Dictionary:
	return {
		"schema_version": PROFILE_SCHEMA_VERSION,
		"profile_id": profile_id,
		"legacy_balance": legacy_balance,
		"lifetime_legacy_earned": lifetime_legacy_earned,
		"lifetime_legacy_spent": lifetime_legacy_spent,
		"claimed_rewards": claimed_rewards.duplicate(true),
		"unlocked_achievements": unlocked_achievements.duplicate(true)
	}

func deserialize(data: Dictionary) -> bool:
	var val_res := validate_profile_data(data)
	if not val_res.get("valid", false):
		push_error("LegacyProfileManager.deserialize failed validation: " + val_res.get("error", "Lỗi dữ liệu"))
		return false

	# Atomic stage and swap
	profile_id = str(data["profile_id"]).strip_edges()
	legacy_balance = int(data["legacy_balance"])
	lifetime_legacy_earned = int(data["lifetime_legacy_earned"])
	lifetime_legacy_spent = int(data["lifetime_legacy_spent"])
	claimed_rewards = data["claimed_rewards"].duplicate(true)
	unlocked_achievements = data.get("unlocked_achievements", {}).duplicate(true)

	balance_changed.emit(legacy_balance)
	return true

# -----------------------------------------------------------------------------
# Atomic File Persistence & Corrupt Recovery
# -----------------------------------------------------------------------------

func save_profile(filepath: String = "") -> bool:
	var target_path = filepath if not filepath.is_empty() else active_filepath
	var tmp_path = target_path + ".tmp"
	var bak_path = target_path + ".bak"

	# Validate state before writing
	var state_dict := serialize()
	var val_res := validate_profile_data(state_dict)
	if not val_res.get("valid", false):
		push_error("LegacyProfileManager.save_profile validation failed: " + val_res.get("error", ""))
		return false

	var json_str = JSON.stringify(state_dict, "  ")

	# Write to temporary file
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("LegacyProfileManager failed to open temporary file for writing: %s (Error: %d)" % [tmp_path, FileAccess.get_open_error()])
		return false

	file.store_string(json_str)
	file.close()

	# Rotate existing profile to backup
	if FileAccess.file_exists(target_path):
		var dir := DirAccess.open("user://")
		if dir != null:
			if FileAccess.file_exists(bak_path):
				dir.remove(bak_path)
			dir.rename(target_path, bak_path)

	# Rename temporary file to target
	var rename_dir := DirAccess.open("user://")
	if rename_dir != null:
		var err := rename_dir.rename(tmp_path, target_path)
		if err != OK:
			push_error("LegacyProfileManager failed to rename %s to %s (Error: %d)" % [tmp_path, target_path, err])
			return false

	profile_saved.emit(target_path)
	return true

func load_profile(filepath: String = "") -> Dictionary:
	var target_path = filepath if not filepath.is_empty() else active_filepath
	var bak_path = target_path + ".bak"

	var file_to_read = target_path
	var used_backup = false

	if not FileAccess.file_exists(target_path):
		if FileAccess.file_exists(bak_path):
			file_to_read = bak_path
			used_backup = true
		else:
			# Neither main nor backup exists -> initialize clean new profile
			_initialize_empty_profile()
			return {"success": true, "status": "new_profile", "balance": legacy_balance}

	# Read main file or backup
	var loaded_data = _read_and_validate_json_file(file_to_read)
	if not loaded_data.get("valid", false):
		# If primary failed, try backup
		if not used_backup and FileAccess.file_exists(bak_path):
			var bak_data = _read_and_validate_json_file(bak_path)
			if bak_data.get("valid", false):
				var apply_bak = deserialize(bak_data["data"])
				if apply_bak:
					profile_loaded.emit(bak_path)
					return {"success": true, "status": "recovered_from_backup", "balance": legacy_balance}

		# Fail closed: Do NOT reset corrupt profile to 0; preserve live state
		var err_msg = "Không thể tải hồ sơ Legacy do dữ liệu bị lỗi và không có bản sao lưu hợp lệ."
		push_error(err_msg)
		return {"success": false, "error": err_msg, "balance": legacy_balance}

	var apply_ok = deserialize(loaded_data["data"])
	if not apply_ok:
		return {"success": false, "error": "Không thể áp dụng dữ liệu hồ sơ Legacy.", "balance": legacy_balance}

	profile_loaded.emit(target_path)
	return {"success": true, "status": "loaded" if not used_backup else "recovered_from_backup", "balance": legacy_balance}

func _read_and_validate_json_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"valid": false, "error": "Tập tin không tồn tại: " + path}

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {"valid": false, "error": "Không thể mở tập tin: " + path}

	var content := file.get_as_text()
	file.close()

	var json := JSON.new()
	var parse_err := json.parse(content)
	if parse_err != OK:
		return {"valid": false, "error": "Lỗi cú pháp JSON trong %s: dòng %d" % [path, json.get_error_line()]}

	var data = json.get_data()
	var val_res := validate_profile_data(data)
	if not val_res.get("valid", false):
		return {"valid": false, "error": val_res.get("error", "Dữ liệu không hợp lệ")}

	return {"valid": true, "data": data}

func _initialize_empty_profile() -> void:
	profile_id = "legacy_profile_default"
	legacy_balance = 0
	lifetime_legacy_earned = 0
	lifetime_legacy_spent = 0
	claimed_rewards.clear()
	unlocked_achievements.clear()

func reset_profile(filepath: String = "") -> void:
	_initialize_empty_profile()
	var target_path = filepath if not filepath.is_empty() else active_filepath
	var dir := DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(target_path):
			dir.remove(target_path)
		if FileAccess.file_exists(target_path + ".bak"):
			dir.remove(target_path + ".bak")
		if FileAccess.file_exists(target_path + ".tmp"):
			dir.remove(target_path + ".tmp")
	balance_changed.emit(legacy_balance)

# -----------------------------------------------------------------------------
# Exactly-Once Reward Claim API (TASK-1Z.3)
# -----------------------------------------------------------------------------

func claim_reward(
	reward_id: String,
	source: String,
	amount: int,
	world_id: String = "",
	extra_details: Dictionary = {}
) -> Dictionary:
	var clean_id = reward_id.strip_edges()
	if clean_id.is_empty():
		return {"success": false, "reason": "empty_reward_id", "points_awarded": 0, "balance": legacy_balance}

	if amount <= 0:
		return {"success": false, "reason": "invalid_amount", "points_awarded": 0, "balance": legacy_balance}

	var clean_src = source.strip_edges()
	if not VALID_REWARD_SOURCES.has(clean_src):
		return {"success": false, "reason": "unsupported_source", "points_awarded": 0, "balance": legacy_balance}

	# Exactly-once claim check: Reject duplicate claim attempts
	if claimed_rewards.has(clean_id):
		return {
			"success": false,
			"reason": "already_claimed",
			"points_awarded": 0,
			"balance": legacy_balance,
			"claimed_record": claimed_rewards[clean_id].duplicate(true)
		}

	var record: Dictionary = {
		"reward_id": clean_id,
		"source": clean_src,
		"amount": amount,
		"world_id": world_id.strip_edges(),
		"claimed_at_unix": int(Time.get_unix_time_from_system()) if Time else 0
	}
	for k in extra_details:
		record[k] = extra_details[k]

	# Stage mutation
	claimed_rewards[clean_id] = record
	legacy_balance += amount
	lifetime_legacy_earned += amount

	# Atomically persist to disk
	var save_ok = save_profile()
	if not save_ok:
		# Rollback on disk failure to preserve atomic in-memory/disk symmetry
		claimed_rewards.erase(clean_id)
		legacy_balance -= amount
		lifetime_legacy_earned -= amount
		return {"success": false, "reason": "save_failed", "points_awarded": 0, "balance": legacy_balance}

	reward_claimed.emit(clean_id, amount, clean_src, legacy_balance)
	balance_changed.emit(legacy_balance)

	return {
		"success": true,
		"points_awarded": amount,
		"balance": legacy_balance,
		"record": record
	}

func is_reward_claimed(reward_id: String) -> bool:
	return claimed_rewards.has(reward_id.strip_edges())

func get_claimed_reward(reward_id: String) -> Dictionary:
	var clean_id = reward_id.strip_edges()
	if claimed_rewards.has(clean_id):
		return claimed_rewards[clean_id].duplicate(true)
	return {}

# -----------------------------------------------------------------------------
# Achievement Foundation (TASK-1Z.5)
# -----------------------------------------------------------------------------

func get_achievement_definitions() -> Dictionary:
	return ACHIEVEMENTS.duplicate(true)

func is_achievement_unlocked(achievement_id: String) -> bool:
	return unlocked_achievements.has(achievement_id.strip_edges())

func unlock_achievement(achievement_id: String, world_id: String = "") -> Dictionary:
	var clean_ach = achievement_id.strip_edges()
	if not ACHIEVEMENTS.has(clean_ach):
		return {"success": false, "reason": "unknown_achievement", "achievement_id": clean_ach}

	if unlocked_achievements.has(clean_ach):
		return {
			"success": false,
			"reason": "already_unlocked",
			"achievement_id": clean_ach,
			"record": unlocked_achievements[clean_ach].duplicate(true)
		}

	var def: Dictionary = ACHIEVEMENTS[clean_ach]
	var rew_amount: int = int(def.get("reward_legacy", 0))
	var rew_id: String = "ach_%s" % clean_ach

	var claim_res := claim_reward(rew_id, "achievement", rew_amount, world_id, {"achievement_id": clean_ach})

	unlocked_achievements[clean_ach] = {
		"achievement_id": clean_ach,
		"unlocked_at_unix": int(Time.get_unix_time_from_system()) if Time else 0,
		"reward_id": rew_id,
		"world_id": world_id.strip_edges()
	}

	save_profile()

	return {
		"success": true,
		"achievement_id": clean_ach,
		"claim_result": claim_res
	}

# -----------------------------------------------------------------------------
# Stable Treasury Conversion Extension Point (TASK-1Z.6)
# -----------------------------------------------------------------------------

func convert_surplus_treasury(
	_treasury_amount: int,
	_stability: float,
	_world_id: String = ""
) -> Dictionary:
	## Extension point for surplus treasury conversion per GDD §13.2.
	## Explicitly deferred pending authoritative game rules formula and conversion rate design decision.
	return {
		"converted": false,
		"legacy_awarded": 0,
		"gold_deducted": 0,
		"status": "deferred",
		"reason": "Chức năng chuyển đổi ngân khố thặng dư sang Legacy tạm hoãn do chưa có công thức và tỷ lệ quy đổi chính thức trong tài liệu thiết kế."
	}
