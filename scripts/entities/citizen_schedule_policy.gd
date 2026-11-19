class_name CitizenSchedulePolicy
extends RefCounted
## Stateless Daily Schedule Policy for Citizens (Day/Night Phase 2 - M1).
## Maps citizen roles to shift profiles and evaluates work, wind-down,
## curfew, rest-hold, and wake-up eligibility from TimeManager.DayPhase.

const TimeManagerScript = preload("res://scripts/core/time_manager.gd")

enum ShiftType {
	DAY_SHIFT = 0,
	NIGHT_EXEMPT = 1
}

const WAKE_FATIGUE_THRESHOLD: float = 15.0

const ROLE_SHIFTS: Dictionary = {
	"guard": ShiftType.NIGHT_EXEMPT,
	"idle": ShiftType.DAY_SHIFT,
	"farmer": ShiftType.DAY_SHIFT,
	"woodcutter": ShiftType.DAY_SHIFT,
	"builder": ShiftType.DAY_SHIFT,
	"hauler": ShiftType.DAY_SHIFT,
	"miner": ShiftType.DAY_SHIFT,
	"quarryman": ShiftType.DAY_SHIFT,
	"smith": ShiftType.DAY_SHIFT,
	"hunter": ShiftType.DAY_SHIFT
}

static func _is_valid_day_phase(day_phase: int) -> bool:
	return (
		day_phase == TimeManagerScript.DayPhase.DAWN
		or day_phase == TimeManagerScript.DayPhase.DAY
		or day_phase == TimeManagerScript.DayPhase.DUSK
		or day_phase == TimeManagerScript.DayPhase.NIGHT
	)

static func get_shift_for_role(role: String) -> int:
	return int(ROLE_SHIFTS.get(role, ShiftType.DAY_SHIFT))

static func can_accept_autonomous_job(role: String, day_phase: int) -> bool:
	if not _is_valid_day_phase(day_phase):
		return false
	if get_shift_for_role(role) == ShiftType.NIGHT_EXEMPT:
		return true
	return day_phase == TimeManagerScript.DayPhase.DAWN or day_phase == TimeManagerScript.DayPhase.DAY

static func should_wind_down(role: String, day_phase: int) -> bool:
	if not _is_valid_day_phase(day_phase):
		return false
	if get_shift_for_role(role) == ShiftType.NIGHT_EXEMPT:
		return false
	return day_phase == TimeManagerScript.DayPhase.DUSK

static func should_enforce_curfew(role: String, day_phase: int) -> bool:
	if not _is_valid_day_phase(day_phase):
		return false
	if get_shift_for_role(role) == ShiftType.NIGHT_EXEMPT:
		return false
	return day_phase == TimeManagerScript.DayPhase.NIGHT

static func should_hold_rest(role: String, day_phase: int) -> bool:
	if not _is_valid_day_phase(day_phase):
		return false
	if get_shift_for_role(role) == ShiftType.NIGHT_EXEMPT:
		return false
	return day_phase == TimeManagerScript.DayPhase.DUSK or day_phase == TimeManagerScript.DayPhase.NIGHT

static func should_wake_from_scheduled_rest(role: String, day_phase: int, fatigue: float) -> bool:
	if not _is_valid_day_phase(day_phase):
		return false
	if should_hold_rest(role, day_phase):
		return false
	return fatigue <= WAKE_FATIGUE_THRESHOLD
