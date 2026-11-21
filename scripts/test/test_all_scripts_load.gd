extends SceneTree
## Automated Test Suite for KINGDOMS UNBOUND — GAP-006: Headless All-Scripts Load & Compilation Validator
## Recursively traverses res://scripts/ and verifies every .gd file compiles and loads cleanly.

var failed_scripts: Array[String] = []
var passed_count: int = 0
var total_count: int = 0

func _init() -> void:
	print("\n========================================================")
	print("  STARTING GAP-006 ALL-SCRIPTS LOAD & COMPILE VALIDATOR")
	print("========================================================\n")

	_scan_directory("res://scripts")

	print("\n--------------------------------------------------------")
	print("  GAP-006 RESULTS: %d / %d Scripts Compiled Successfully" % [passed_count, total_count])
	if failed_scripts.is_empty() and total_count > 0:
		print("  ALL %d SCRIPTS LOADED AND COMPILED WITHOUT ERRORS! (Exit Code 0)" % total_count)
		print("--------------------------------------------------------\n")
		quit(0)
	else:
		printerr("  GAP-006 FAILED! %d scripts failed to compile:" % failed_scripts.size())
		for f in failed_scripts:
			printerr("    - %s" % f)
		print("--------------------------------------------------------\n")
		quit(1)

func _scan_directory(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		printerr("  [FAIL] Cannot open directory: %s" % dir_path)
		return

	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name == "." or file_name == "..":
			file_name = dir.get_next()
			continue

		var full_path := dir_path.path_join(file_name)
		if dir.current_is_dir():
			# Recursively scan subdirectories
			_scan_directory(full_path)
		elif file_name.ends_with(".gd"):
			total_count += 1
			_verify_script(full_path)

		file_name = dir.get_next()
	dir.list_dir_end()

func _verify_script(path: String) -> void:
	# Attempt to load the script resource
	var res := load(path)
	if res == null:
		printerr("  [FAIL] Failed to load script: %s" % path)
		failed_scripts.append(path)
	elif not (res is GDScript):
		printerr("  [FAIL] Loaded resource is not GDScript: %s (type: %s)" % [path, res.get_class()])
		failed_scripts.append(path)
	else:
		passed_count += 1
		# Output periodic progress every 20 scripts
		if passed_count % 25 == 0:
			print("  [PROGRESS] %d scripts verified..." % passed_count)
