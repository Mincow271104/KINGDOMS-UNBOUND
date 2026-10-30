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
const MAX_SAFE_INT: int = 9223372036854775807
const FLOAT_INT64_EXCLUSIVE_UPPER: float = 9223372036854775808.0
const FLOAT_INT64_INCLUSIVE_LOWER: float = -9223372036854775808.0

# Test failure injection seams (FIX-1Z-M, FIX-1Z-V)
static var _test_inject_fail_write: bool = false
static var _test_inject_fail_rename: bool = false
static var _test_inject_fail_restore_copy: bool = false
static var _test_inject_fail_backup_rollback: bool = false

static func reset_test_injection() -> void:
	_test_inject_fail_write = false
	_test_inject_fail_rename = false
	_test_inject_fail_restore_copy = false
	_test_inject_fail_backup_rollback = false

const VALID_REWARD_SOURCES: Array[String] = [
	"victory",
	"achievement"
]

const STATUS_UNINITIALIZED: String = "uninitialized"
const STATUS_NEW_PROFILE: String = "new_profile"
const STATUS_LOADED: String = "loaded"
const STATUS_RECOVERED_FROM_BACKUP: String = "recovered_from_backup"
const STATUS_UNAVAILABLE: String = "unavailable"

static var ACHIEVEMENTS: Dictionary = {
	"prosperity_victory": {
		"id": "prosperity_victory",
		"title": "Thịnh Vượng Toàn Diện",
		"description": "Duy trì thịnh vượng xuất sắc trong 5 ngày liên tục.",
		"reward_legacy": 0,
		"reward_source": "achievement",
		"reward_status": "deferred"
	}
}

var profile_id: String = "legacy_profile_default"
var legacy_balance: int = 0
var lifetime_legacy_earned: int = 0
var lifetime_legacy_spent: int = 0
var claimed_rewards: Dictionary = {} # reward_id (String) -> Dictionary
var unlocked_achievements: Dictionary = {} # achievement_id (String) -> Dictionary
var active_filepath: String = DEFAULT_PROFILE_PATH
var profile_status: String = STATUS_UNINITIALIZED
var initialization_error: String = ""

static var _instance = null

# -----------------------------------------------------------------------------
# Singleton & Factory Methods
# -----------------------------------------------------------------------------

static func get_instance(filepath: String = "") -> RefCounted:
	if _instance == null:
		var script = load("res://scripts/legacy/legacy_profile_manager.gd")
		_instance = script.new(filepath)
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
	load_profile()

func is_available() -> bool:
	return profile_status in [STATUS_NEW_PROFILE, STATUS_LOADED, STATUS_RECOVERED_FROM_BACKUP]

func get_status() -> String:
	return profile_status

func get_initialization_error() -> String:
	return initialization_error

static func _is_valid_integer_val(val: Variant) -> bool:
	if val is int:
		return true
	if val is float:
		var f := float(val)
		if is_nan(f) or is_inf(f) or floor(f) != f:
			return false
		if f < FLOAT_INT64_INCLUSIVE_LOWER or f >= FLOAT_INT64_EXCLUSIVE_UPPER:
			return false
		return true
	return false

# -----------------------------------------------------------------------------
# Fail-Closed Data Validation
# -----------------------------------------------------------------------------

static func validate_profile_data(data: Variant) -> Dictionary:
	if not (data is Dictionary):
		return {"valid": false, "error": "Dữ liệu hồ sơ Legacy phải là Dictionary."}

	if not data.has("schema_version"):
		return {"valid": false, "error": "Thiếu trường 'schema_version' trong hồ sơ Legacy."}
	var sv = data["schema_version"]
	if not _is_valid_integer_val(sv):
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
		if not _is_valid_integer_val(val):
			return {"valid": false, "error": "Trường '%s' phải là số nguyên hợp lệ." % k}
		if val is float and (val < 0.0 or val >= FLOAT_INT64_EXCLUSIVE_UPPER):
			return {"valid": false, "error": "Trường '%s' vượt quá giới hạn số nguyên 64-bit." % k}
		var int_val := int(val)
		if int_val < 0:
			return {"valid": false, "error": "Trường '%s' không được âm (%d)." % [k, int_val]}
		if int_val > MAX_SAFE_INT:
			return {"valid": false, "error": "Trường '%s' vượt quá giới hạn số nguyên 64-bit." % k}

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
		if not _is_valid_integer_val(amt):
			return {"valid": false, "error": "Số điểm phần thưởng '%s' không phải số nguyên." % r_id_str}
		if amt is float and (amt <= 0.0 or amt >= FLOAT_INT64_EXCLUSIVE_UPPER):
			return {"valid": false, "error": "Số điểm phần thưởng '%s' vượt quá giới hạn số nguyên 64-bit." % r_id_str}
		var amt_int = int(amt)
		if amt_int <= 0:
			return {"valid": false, "error": "Số điểm phần thưởng '%s' phải lớn hơn 0 (%d)." % [r_id_str, amt_int]}
		if amt_int > MAX_SAFE_INT:
			return {"valid": false, "error": "Số điểm phần thưởng '%s' vượt quá giới hạn số nguyên 64-bit." % r_id_str}
		if amt_int > MAX_SAFE_INT - total_claimed_points:
			return {"valid": false, "error": "Tràn số nguyên khi tổng hợp điểm phần thưởng đã nhận."}

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

func _reconcile_backups(dir: DirAccess, bak_path: String, bak_old_path: String) -> bool:
	if not FileAccess.file_exists(bak_old_path):
		return true

	var bak_val := _read_and_validate_json_file(bak_path) if FileAccess.file_exists(bak_path) else {"valid": false}
	var bak_old_val := _read_and_validate_json_file(bak_old_path)

	if bak_old_val.get("valid", false):
		if not bak_val.get("valid", false):
			# bak is missing or invalid, but bak_old is valid. Promote bak_old to bak.
			if FileAccess.file_exists(bak_path):
				var rem_bak_err := dir.remove(bak_path)
				if rem_bak_err != OK:
					push_error("LegacyProfileManager: Failed to remove invalid backup %s during reconciliation (Error: %d)" % [bak_path, rem_bak_err])
					return false
			var ren_err := dir.rename(bak_old_path, bak_path)
			if ren_err != OK:
				push_error("LegacyProfileManager: Failed to promote %s to %s during reconciliation (Error: %d)" % [bak_old_path, bak_path, ren_err])
				return false
			print("[LegacyProfileManager] Reconciled interrupted rotation: promoted valid %s to %s" % [bak_old_path, bak_path])
			return true
		else:
			# Both bak and bak_old are valid. bak is the newer authoritative backup; remove bak_old.
			var rem_old_err := dir.remove(bak_old_path)
			if rem_old_err != OK:
				push_error("LegacyProfileManager: Failed to remove obsolete old backup %s (Error: %d)" % [bak_old_path, rem_old_err])
				return false
			return true
	else:
		# bak_old is invalid. Remove it safely.
		var rem_old_err := dir.remove(bak_old_path)
		if rem_old_err != OK:
			push_error("LegacyProfileManager: Failed to remove invalid old backup %s (Error: %d)" % [bak_old_path, rem_old_err])
			return false
		return true

func save_profile(filepath: String = "") -> bool:
	if not is_available():
		push_error("LegacyProfileManager: Cannot save while profile is unavailable.")
		return false

	var target_path: String = filepath if not filepath.is_empty() else active_filepath
	var tmp_path: String = target_path + ".tmp"
	var bak_path: String = target_path + ".bak"
	var bak_tmp_path: String = target_path + ".bak.tmp"
	var bak_old_path: String = target_path + ".bak.old"

	# Validate state before writing
	var state_dict := serialize()
	var val_res := validate_profile_data(state_dict)
	if not val_res.get("valid", false):
		push_error("LegacyProfileManager.save_profile validation failed: " + val_res.get("error", ""))
		return false

	var dir_path := target_path.get_base_dir()
	var dir := DirAccess.open(dir_path if not dir_path.is_empty() else "user://")
	if dir == null:
		push_error("LegacyProfileManager: Cannot access directory: %s" % dir_path)
		return false

	# FIX-1Z-T: Reconcile any interrupted backup rotation before touching temporary files
	if not _reconcile_backups(dir, bak_path, bak_old_path):
		push_error("LegacyProfileManager: Aborting save due to failed backup reconciliation.")
		return false

	# Clean up any leftover temporary file
	if FileAccess.file_exists(tmp_path):
		dir.remove(tmp_path)
	if FileAccess.file_exists(bak_tmp_path):
		dir.remove(bak_tmp_path)

	var json_str = JSON.stringify(state_dict, "  ")

	# Write to temporary file
	var file := FileAccess.open(tmp_path, FileAccess.WRITE)
	if file == null:
		push_error("LegacyProfileManager failed to open temporary file for writing: %s (Error: %d)" % [tmp_path, FileAccess.get_open_error()])
		return false

	if _test_inject_fail_write:
		file.close()
		if FileAccess.file_exists(tmp_path):
			dir.remove(tmp_path)
		return false

	file.store_string(json_str)
	file.flush()
	var write_err := file.get_error()
	file.close()

	if write_err != OK:
		push_error("LegacyProfileManager write error on temporary file: %s (Error: %d)" % [tmp_path, write_err])
		if FileAccess.file_exists(tmp_path):
			dir.remove(tmp_path)
		return false

	if not FileAccess.file_exists(tmp_path):
		push_error("LegacyProfileManager temporary file not found after write: " + tmp_path)
		return false

	# Validate written temporary file before replacing target
	var tmp_check := _read_and_validate_json_file(tmp_path)
	if not tmp_check.get("valid", false):
		push_error("LegacyProfileManager: Temporary file validation failed before rename: " + tmp_check.get("error", ""))
		if FileAccess.file_exists(tmp_path):
			dir.remove(tmp_path)
		return false

	# If existing target file exists, only rotate to backup if valid using staged backup (FIX-1Z-H, FIX-1Z-M, FIX-1Z-O)
	if FileAccess.file_exists(target_path):
		var target_check := _read_and_validate_json_file(target_path)
		if target_check.get("valid", false):
			if FileAccess.file_exists(bak_tmp_path):
				dir.remove(bak_tmp_path)

			var copy_err := dir.copy(target_path, bak_tmp_path)
			if copy_err != OK or not FileAccess.file_exists(bak_tmp_path):
				push_error("LegacyProfileManager failed to stage backup %s to %s (Error: %d)" % [target_path, bak_tmp_path, copy_err])
				if FileAccess.file_exists(bak_tmp_path):
					dir.remove(bak_tmp_path)
				if FileAccess.file_exists(tmp_path):
					dir.remove(tmp_path)
				return false

			# Verify staged backup contents before replacing authoritative backup (FIX-1Z-O)
			var staged_check := _read_and_validate_json_file(bak_tmp_path)
			var staged_valid: bool = staged_check.get("valid", false)
			if staged_valid and target_check.has("data") and staged_check.has("data"):
				if staged_check["data"] != target_check["data"]:
					staged_valid = false
					push_error("LegacyProfileManager: Staged backup data mismatch against previous target.")

			if not staged_valid:
				push_error("LegacyProfileManager: Staged backup validation failed: %s" % staged_check.get("error", "content mismatch"))
				if FileAccess.file_exists(bak_tmp_path):
					dir.remove(bak_tmp_path)
				if FileAccess.file_exists(tmp_path):
					dir.remove(tmp_path)
				return false

			# Safely replace authoritative backup with rollback protection (FIX-1Z-P)
			if FileAccess.file_exists(bak_path):
				if FileAccess.file_exists(bak_old_path):
					if not _reconcile_backups(dir, bak_path, bak_old_path):
						push_error("LegacyProfileManager: Failed to reconcile lingering old backup before rotation.")
						if FileAccess.file_exists(bak_tmp_path):
							dir.remove(bak_tmp_path)
						if FileAccess.file_exists(tmp_path):
							dir.remove(tmp_path)
						return false
				var rot_old_err := dir.rename(bak_path, bak_old_path)
				if rot_old_err != OK:
					push_error("LegacyProfileManager failed to protect old backup %s (Error: %d)" % [bak_path, rot_old_err])
					if FileAccess.file_exists(bak_tmp_path):
						dir.remove(bak_tmp_path)
					if FileAccess.file_exists(tmp_path):
						dir.remove(tmp_path)
					return false

			var ren_bak_err := dir.rename(bak_tmp_path, bak_path)
			if ren_bak_err != OK:
				push_error("LegacyProfileManager failed to rename staged backup %s to %s (Error: %d)" % [bak_tmp_path, bak_path, ren_bak_err])
				if FileAccess.file_exists(bak_old_path):
					var rollback_err := OK
					if _test_inject_fail_backup_rollback:
						rollback_err = ERR_CANT_CREATE
					else:
						rollback_err = dir.rename(bak_old_path, bak_path)
					if rollback_err != OK:
						push_error("LegacyProfileManager: Failed to rollback old backup from %s to %s" % [bak_old_path, bak_path])
				if FileAccess.file_exists(bak_tmp_path):
					dir.remove(bak_tmp_path)
				if FileAccess.file_exists(tmp_path):
					dir.remove(tmp_path)
				return false

			if FileAccess.file_exists(bak_old_path):
				var rem_old_err := dir.remove(bak_old_path)
				if rem_old_err != OK:
					push_warning("LegacyProfileManager: Could not remove old backup %s (Error: %d)" % [bak_old_path, rem_old_err])
		else:
			push_warning("LegacyProfileManager: Existing target %s is corrupt. Preserving existing backup untouched." % target_path)

		var rem_err := dir.remove(target_path)
		if rem_err != OK:
			push_error("LegacyProfileManager failed to remove target %s before rename (Error: %d)" % [target_path, rem_err])
			if FileAccess.file_exists(tmp_path):
				dir.remove(tmp_path)
			return false

	# Rename temporary file to target
	var rename_err := OK
	if _test_inject_fail_rename:
		rename_err = ERR_CANT_CREATE
	else:
		rename_err = dir.rename(tmp_path, target_path)

	if rename_err != OK:
		push_error("LegacyProfileManager failed to rename %s to %s (Error: %d)" % [tmp_path, target_path, rename_err])
		# Restore target from backup if possible
		if FileAccess.file_exists(bak_path) and not FileAccess.file_exists(target_path):
			var restore_err := OK
			if _test_inject_fail_restore_copy:
				restore_err = ERR_CANT_CREATE
			else:
				restore_err = dir.copy(bak_path, target_path)
			if restore_err != OK:
				push_error("LegacyProfileManager: Failed to restore target from backup %s (Error: %d)" % [bak_path, restore_err])
		if FileAccess.file_exists(tmp_path):
			dir.remove(tmp_path)
		return false

	if not FileAccess.file_exists(target_path):
		push_error("LegacyProfileManager: Target file %s missing after rename." % target_path)
		return false

	var final_val := _read_and_validate_json_file(target_path)
	if not final_val.get("valid", false):
		push_error("LegacyProfileManager: Target file validation failed after rename: %s" % final_val.get("error", ""))
		if FileAccess.file_exists(target_path):
			dir.remove(target_path)
		if FileAccess.file_exists(bak_path) and not FileAccess.file_exists(target_path):
			var restore_err := OK
			if _test_inject_fail_restore_copy:
				restore_err = ERR_CANT_CREATE
			else:
				restore_err = dir.copy(bak_path, target_path)
			if restore_err != OK:
				push_error("LegacyProfileManager: Failed to restore target from backup after invalid write.")
		return false

	profile_saved.emit(target_path)
	return true

func load_profile(filepath: String = "") -> Dictionary:
	var target_path: String = filepath if not filepath.is_empty() else active_filepath
	var bak_path: String = target_path + ".bak"
	var bak_old_path: String = target_path + ".bak.old"

	# If neither main nor any backup exists -> genuine clean new profile
	if not FileAccess.file_exists(target_path) and not FileAccess.file_exists(bak_path) and not FileAccess.file_exists(bak_old_path):
		_initialize_empty_profile()
		profile_status = STATUS_NEW_PROFILE
		initialization_error = ""
		return {"success": true, "status": STATUS_NEW_PROFILE, "balance": legacy_balance}

	# Check primary first
	if FileAccess.file_exists(target_path):
		var loaded_data = _read_and_validate_json_file(target_path)
		if loaded_data.get("valid", false):
			var apply_ok = deserialize(loaded_data["data"])
			if apply_ok:
				profile_status = STATUS_LOADED
				initialization_error = ""
				profile_loaded.emit(target_path)
				return {"success": true, "status": STATUS_LOADED, "balance": legacy_balance}
			else:
				push_error("LegacyProfileManager: Failed to deserialize primary profile.")
		else:
			push_warning("LegacyProfileManager: Primary profile %s invalid (%s), attempting backup recovery..." % [target_path, loaded_data.get("error", "")])
	else:
		push_warning("LegacyProfileManager: Primary profile %s not found, attempting backup recovery..." % target_path)

	# Try authoritative backup
	if FileAccess.file_exists(bak_path):
		var bak_data = _read_and_validate_json_file(bak_path)
		if bak_data.get("valid", false):
			var apply_bak = deserialize(bak_data["data"])
			if apply_bak:
				profile_status = STATUS_RECOVERED_FROM_BACKUP
				initialization_error = ""
				profile_loaded.emit(bak_path)
				return {"success": true, "status": STATUS_RECOVERED_FROM_BACKUP, "balance": legacy_balance}
			else:
				push_error("LegacyProfileManager: Failed to deserialize backup profile.")
		else:
			push_warning("LegacyProfileManager: Backup profile %s invalid (%s), attempting old backup recovery..." % [bak_path, bak_data.get("error", "")])

	# FIX-1Z-T: Try temporary protection old backup if authoritative backup unavailable
	if FileAccess.file_exists(bak_old_path):
		var bak_old_data = _read_and_validate_json_file(bak_old_path)
		if bak_old_data.get("valid", false):
			var apply_old = deserialize(bak_old_data["data"])
			if apply_old:
				profile_status = STATUS_RECOVERED_FROM_BACKUP
				initialization_error = ""
				profile_loaded.emit(bak_old_path)
				return {"success": true, "status": STATUS_RECOVERED_FROM_BACKUP, "balance": legacy_balance}
			else:
				push_error("LegacyProfileManager: Failed to deserialize old backup profile.")
		else:
			push_warning("LegacyProfileManager: Old backup profile %s invalid: %s" % [bak_old_path, bak_old_data.get("error", "")])

	# Fail closed: Do NOT reset corrupt profile to 0; mark UNAVAILABLE
	profile_status = STATUS_UNAVAILABLE
	initialization_error = "Không thể tải hồ sơ Legacy do tệp bị lỗi hoặc hỏng cấu trúc và không có bản sao lưu hợp lệ."
	push_error(initialization_error)
	return {"success": false, "status": STATUS_UNAVAILABLE, "error": initialization_error, "balance": legacy_balance}

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
	profile_status = STATUS_NEW_PROFILE
	initialization_error = ""
	var target_path = filepath if not filepath.is_empty() else active_filepath
	var dir_path := target_path.get_base_dir()
	var dir := DirAccess.open(dir_path if not dir_path.is_empty() else "user://")
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
	amount: Variant,
	world_id: String = "",
	extra_details: Dictionary = {}
) -> Dictionary:
	if not is_available():
		return {
			"success": false,
			"reason": "profile_unavailable",
			"error": initialization_error,
			"points_awarded": 0,
			"balance": legacy_balance
		}

	var clean_id = reward_id.strip_edges()
	if clean_id.is_empty():
		return {"success": false, "reason": "empty_reward_id", "points_awarded": 0, "balance": legacy_balance}

	if not _is_valid_integer_val(amount):
		return {"success": false, "reason": "invalid_amount", "points_awarded": 0, "balance": legacy_balance}

	if amount is float and (amount <= 0.0 or amount >= FLOAT_INT64_EXCLUSIVE_UPPER):
		return {"success": false, "reason": "invalid_amount", "points_awarded": 0, "balance": legacy_balance}

	var amt_int: int = int(amount)
	if amt_int <= 0 or amt_int > MAX_SAFE_INT:
		return {"success": false, "reason": "invalid_amount", "points_awarded": 0, "balance": legacy_balance}

	# Numeric Overflow Protection (FIX-1Z-J)
	if amt_int > MAX_SAFE_INT - legacy_balance or amt_int > MAX_SAFE_INT - lifetime_legacy_earned:
		return {
			"success": false,
			"reason": "overflow",
			"error": "Phần thưởng làm tràn số nguyên 64-bit của số dư hoặc tổng tích lũy.",
			"points_awarded": 0,
			"balance": legacy_balance
		}

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
		"amount": amt_int,
		"world_id": world_id.strip_edges(),
		"claimed_at_unix": int(Time.get_unix_time_from_system()) if Time else 0
	}
	for k in extra_details:
		record[k] = extra_details[k]

	# Stage mutation
	claimed_rewards[clean_id] = record
	legacy_balance += amt_int
	lifetime_legacy_earned += amt_int

	# Atomically persist to disk
	var save_ok = save_profile()
	if not save_ok:
		# Rollback on disk failure to preserve atomic in-memory/disk symmetry
		claimed_rewards.erase(clean_id)
		legacy_balance -= amt_int
		lifetime_legacy_earned -= amt_int
		return {"success": false, "reason": "save_failed", "points_awarded": 0, "balance": legacy_balance}

	reward_claimed.emit(clean_id, amt_int, clean_src, legacy_balance)
	balance_changed.emit(legacy_balance)

	return {
		"success": true,
		"points_awarded": amt_int,
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
# Achievement Foundation (TASK-1Z.5 & FIX-1Z-B)
# -----------------------------------------------------------------------------

func get_achievement_definitions() -> Dictionary:
	return ACHIEVEMENTS.duplicate(true)

func is_achievement_unlocked(achievement_id: String) -> bool:
	return unlocked_achievements.has(achievement_id.strip_edges())

func unlock_achievement(achievement_id: String, world_id: String = "") -> Dictionary:
	if not is_available():
		return {
			"success": false,
			"reason": "profile_unavailable",
			"error": initialization_error,
			"achievement_id": achievement_id
		}

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

	# If this achievement has a documented positive reward, verify it hasn't been claimed
	if rew_amount > 0:
		if claimed_rewards.has(rew_id):
			return {
				"success": false,
				"reason": "already_claimed",
				"achievement_id": clean_ach
			}
		if rew_amount > MAX_SAFE_INT or rew_amount > MAX_SAFE_INT - legacy_balance or rew_amount > MAX_SAFE_INT - lifetime_legacy_earned:
			return {
				"success": false,
				"reason": "overflow",
				"achievement_id": clean_ach
			}

	# Stage mutations in memory
	var ach_record = {
		"achievement_id": clean_ach,
		"unlocked_at_unix": int(Time.get_unix_time_from_system()) if Time else 0,
		"reward_id": rew_id if rew_amount > 0 else "",
		"world_id": world_id.strip_edges(),
		"reward_status": def.get("reward_status", "awarded" if rew_amount > 0 else "deferred")
	}

	var claim_record = {}
	if rew_amount > 0:
		claim_record = {
			"reward_id": rew_id,
			"source": "achievement",
			"amount": rew_amount,
			"world_id": world_id.strip_edges(),
			"claimed_at_unix": ach_record["unlocked_at_unix"],
			"achievement_id": clean_ach
		}
		claimed_rewards[rew_id] = claim_record
		legacy_balance += rew_amount
		lifetime_legacy_earned += rew_amount

	unlocked_achievements[clean_ach] = ach_record

	# Save atomically to disk
	var save_ok = save_profile()
	if not save_ok:
		# Rollback staged in-memory mutations completely
		unlocked_achievements.erase(clean_ach)
		if rew_amount > 0:
			claimed_rewards.erase(rew_id)
			legacy_balance -= rew_amount
			lifetime_legacy_earned -= rew_amount
		return {
			"success": false,
			"reason": "save_failed",
			"achievement_id": clean_ach
		}

	if rew_amount > 0:
		reward_claimed.emit(rew_id, rew_amount, "achievement", legacy_balance)
		balance_changed.emit(legacy_balance)

	return {
		"success": true,
		"achievement_id": clean_ach,
		"record": ach_record,
		"points_awarded": rew_amount,
		"balance": legacy_balance
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
