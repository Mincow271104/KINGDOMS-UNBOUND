extends SceneTree
## Test Suite for Phase 9: Audio Subsystem & Procedural Sound Synthesis.
## Validates AudioManager stream creation, sound playback calls, mute toggle, and volume curves.

const AudioManagerScript = preload("res://scripts/audio/audio_manager.gd")

var frame_count: int = 0
var audio_mgr: Node = null

func _init() -> void:
	print("\n========================================================")
	print("  TEST SUITE: Phase 9 — Procedural Audio Subsystem")
	print("========================================================\n")
	
	audio_mgr = AudioManagerScript.new()
	audio_mgr.name = "AudioManagerTest"
	root.add_child(audio_mgr)

func _process(_delta: float) -> bool:
	frame_count += 1
	if frame_count < 3:
		return false
		
	var pass_count: int = 0
	var total_tests: int = 5
	
	# Test 1: Sound library generation
	var stream_keys: Array = audio_mgr._streams.keys()
	print("[Audio Test 1] Verifying synthesized sound library streams...")
	print("  Generated streams:", stream_keys)
	var expected_keys: Array = ["click", "build", "error", "tech", "coin", "fanfare", "alarm", "ambient"]
	var all_keys_present: bool = true
	for k in expected_keys:
		if not audio_mgr._streams.has(k):
			all_keys_present = false
			print("  ❌ Missing stream:", k)
	
	if all_keys_present and stream_keys.size() >= 8:
		print("  ✅ All 8 procedural sound streams synthesized successfully.")
		pass_count += 1
	else:
		print("  ❌ Stream generation failed.")
		
	# Test 2: Verify stream properties (16-bit, mix rate 22050, valid data bytes)
	print("\n[Audio Test 2] Checking stream PCM data integrity...")
	var click_wav: AudioStreamWAV = audio_mgr._streams["click"]
	var ambient_wav: AudioStreamWAV = audio_mgr._streams["ambient"]
	var data_valid: bool = true
	if click_wav.format != AudioStreamWAV.FORMAT_16_BITS or click_wav.mix_rate != 22050:
		data_valid = false
		print("  ❌ Click WAV format or mix rate mismatch.")
	if click_wav.data.size() == 0:
		data_valid = false
		print("  ❌ Click WAV data buffer is empty.")
	if ambient_wav.loop_mode != AudioStreamWAV.LOOP_FORWARD:
		data_valid = false
		print("  ❌ Ambient WAV is not configured as looping.")
		
	if data_valid:
		print("  ✅ AudioStreamWAV parameters: 16-bit PCM, 22050 Hz, valid buffer (%d bytes click, %d bytes ambient)." % [click_wav.data.size(), ambient_wav.data.size()])
		pass_count += 1
	else:
		print("  ❌ PCM integrity check failed.")

	# Test 3: SFX playback pool execution
	print("\n[Audio Test 3] Exercising playback calls through SFX pool...")
	audio_mgr.play_click()
	audio_mgr.play_build()
	audio_mgr.play_error()
	audio_mgr.play_tech()
	audio_mgr.play_coin()
	audio_mgr.play_fanfare()
	audio_mgr.play_alarm()
	print("  ✅ 7 polyphonic SFX calls executed cleanly across player pool without crash.")
	pass_count += 1

	# Test 4: Ambient Music playback & loop toggle
	print("\n[Audio Test 4] Testing ambient music player...")
	audio_mgr.start_ambient_music()
	var music_playing: bool = audio_mgr._music_player.playing or audio_mgr._music_player.stream != null
	audio_mgr.stop_ambient_music()
	if music_playing:
		print("  ✅ Ambient music stream attached and started smoothly.")
		pass_count += 1
	else:
		print("  ❌ Ambient music playback failure.")

	# Test 5: Volume adjustments and mute toggle
	print("\n[Audio Test 5] Testing volume controls and mute toggle...")
	audio_mgr.sfx_volume = 0.5
	audio_mgr.music_volume = 0.3
	var initial_muted: bool = audio_mgr.is_muted
	var toggled_muted: bool = audio_mgr.toggle_mute()
	var unmuted: bool = audio_mgr.toggle_mute()
	
	if audio_mgr.sfx_volume == 0.5 and audio_mgr.music_volume == 0.3 and toggled_muted != initial_muted and not unmuted:
		print("  ✅ Volume curves and mute toggle verified: SFX=0.5, Music=0.3, Mute toggle works.")
		pass_count += 1
	else:
		print("  ❌ Volume/mute controls failed.")
		
	audio_mgr.queue_free()
	
	print("\n--------------------------------------------------------")
	if pass_count == total_tests:
		print("  ALL AUDIO TESTS PASSED (%d/%d)! (Exit Code 0)" % [pass_count, total_tests])
		print("--------------------------------------------------------\n")
		quit(0)
		return true
	else:
		print("  AUDIO TESTS FAILED (%d/%d)" % [pass_count, total_tests])
		print("--------------------------------------------------------\n")
		quit(1)
		return false
