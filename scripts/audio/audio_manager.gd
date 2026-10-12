extends Node
## Procedural Audio & Sound Effects Subsystem for KINGDOMS UNBOUND.
## Generates lightweight, retro 16-bit PCM waveforms dynamically at runtime
## to provide crisp auditory feedback (UI, Building, Tech, Fanfare, Alarms, Ambient)
## with zero external file dependencies or licensing risks.

signal sound_settings_changed(sfx_volume: float, music_volume: float, muted: bool)

# Audio Buses and Controls
var sfx_volume: float = 0.8:
	set(val):
		sfx_volume = clampf(val, 0.0, 1.0)
		_apply_volumes()
var music_volume: float = 0.5:
	set(val):
		music_volume = clampf(val, 0.0, 1.0)
		_apply_volumes()
var is_muted: bool = false:
	set(val):
		is_muted = val
		_apply_volumes()

# SFX Player Pool
const POOL_SIZE: int = 8
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_index: int = 0
var _music_player: AudioStreamPlayer = null

# Sound library cache
var _streams: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Run even when game paused
	_init_players()
	_generate_sound_library()
	_apply_volumes()

func _init_players() -> void:
	# Pool of SFX players to allow polyphonic overlapping sounds
	for i in range(POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFXPlayer_%d" % i
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)
		
	# Dedicated looping music player
	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	_music_player.bus = "Master"
	add_child(_music_player)

func _generate_sound_library() -> void:
	const SR: int = 22050
	
	# 1. UI Click: crisp 750Hz sine blip (40ms)
	_streams["click"] = _synth_tone(750.0, 0.045, SR, 35.0, "sine", 0.6)
	
	# 2. Building Placed: satisfying low thud + hammer ring (120ms)
	_streams["build"] = _synth_build_sound(SR)
	
	# 3. Placement Error: double low buzz (160ms)
	_streams["error"] = _synth_error_sound(SR)
	
	# 4. Tech Unlocked: rising 4-note major arpeggio chime (C5-E5-G5-C6, 320ms)
	_streams["tech"] = _synth_arpeggio([523.25, 659.25, 783.99, 1046.50], 0.08, SR, "sine")
	
	# 5. Coin / Trade: royal pleasant chime (1200Hz + 2400Hz overtone, 90ms)
	_streams["coin"] = _synth_coin_sound(SR)
	
	# 6. Victory Fanfare: triumphant brass-style chord sequence (C - G - C6, 750ms)
	_streams["fanfare"] = _synth_fanfare(SR)
	
	# 7. Collapse / Crisis Alarm: rapid alternating minor warning buzz (240ms)
	_streams["alarm"] = _synth_alarm_sound(SR)
	
	# 8. Ambient Pastoral Loop: calm, gentle pentatonic melodic progression (8.0s)
	_streams["ambient"] = _synth_ambient_loop(SR)

# --- Procedural Synthesis Algorithms ---

func _synth_tone(freq: float, duration: float, sample_rate: int, decay: float = 10.0, wave_type: String = "sine", gain: float = 0.7) -> AudioStreamWAV:
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-decay * t)
		var phase: float = t * freq * TAU
		var s: float = 0.0
		
		if wave_type == "sine":
			s = sin(phase)
		elif wave_type == "square":
			s = 0.8 if sin(phase) >= 0.0 else -0.8
		elif wave_type == "triangle":
			s = 2.0 * abs(2.0 * (t * freq - floor(t * freq + 0.5))) - 1.0
		elif wave_type == "noise":
			s = randf_range(-1.0, 1.0)
			
		s *= env * gain
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_build_sound(sample_rate: int) -> AudioStreamWAV:
	var duration: float = 0.12
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-18.0 * t)
		# Combination of low punch (110Hz -> 60Hz drop) and wood transient noise
		var f: float = 140.0 - (t / duration) * 80.0
		var thud: float = sin(t * f * TAU) * 0.7
		var noise: float = randf_range(-0.3, 0.3) * exp(-40.0 * t)
		var s: float = (thud + noise) * env * 0.8
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_error_sound(sample_rate: int) -> AudioStreamWAV:
	var duration: float = 0.16
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		# Two 70ms pulses with 20ms silence in between
		var active: bool = (t < 0.07) or (t > 0.09 and t < 0.16)
		var s: float = 0.0
		if active:
			var phase: float = t * 180.0 * TAU
			s = (0.7 if sin(phase) >= 0.0 else -0.7) * 0.5
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_coin_sound(sample_rate: int) -> AudioStreamWAV:
	var duration: float = 0.10
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var env: float = exp(-22.0 * t)
		# Dual chime harmonics: 987Hz (B5) and 1318Hz (E6)
		var s: float = (sin(t * 987.77 * TAU) * 0.5 + sin(t * 1318.51 * TAU) * 0.5) * env * 0.6
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_arpeggio(freqs: Array, note_duration: float, sample_rate: int, wave_type: String = "sine") -> AudioStreamWAV:
	var total_duration: float = note_duration * float(freqs.size())
	var total_samples: int = int(total_duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var note_idx: int = int(t / note_duration)
		if note_idx >= freqs.size():
			note_idx = freqs.size() - 1
		var note_t: float = t - (float(note_idx) * note_duration)
		var env: float = exp(-12.0 * note_t)
		var freq: float = freqs[note_idx]
		var s: float = sin(note_t * freq * TAU) * env * 0.7
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_fanfare(sample_rate: int) -> AudioStreamWAV:
	# C4(261), E4(329), G4(392), C5(523), lasting 0.8s
	var duration: float = 0.80
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var chords: Array = [
		{"start": 0.00, "dur": 0.18, "f": [261.63, 329.63, 392.00]}, # C major
		{"start": 0.18, "dur": 0.18, "f": [293.66, 369.99, 440.00]}, # D major
		{"start": 0.36, "dur": 0.44, "f": [523.25, 659.25, 783.99]}  # C5 octave triumph
	]
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var s: float = 0.0
		for chord in chords:
			if t >= chord["start"] and t < (chord["start"] + chord["dur"]):
				var ct: float = t - chord["start"]
				var env: float = (1.0 - ct / chord["dur"]) * 0.6
				for freq in chord["f"]:
					s += sin(ct * freq * TAU) * 0.22 * env
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_alarm_sound(sample_rate: int) -> AudioStreamWAV:
	var duration: float = 0.30
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var freq: float = 330.0 if fmod(t, 0.10) < 0.05 else 260.0
		var phase: float = t * freq * TAU
		var s: float = (0.7 if sin(phase) >= 0.0 else -0.7) * 0.45 * (1.0 - t / duration)
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	return wav

func _synth_ambient_loop(sample_rate: int) -> AudioStreamWAV:
	# Gentle 8-second looping ambient progression (pentatonic notes with soft envelope)
	var duration: float = 8.0
	var total_samples: int = int(duration * sample_rate)
	var bytes := PackedByteArray()
	bytes.resize(total_samples * 2)
	
	var melody: Array = [
		{"t": 0.0, "dur": 1.8, "f": 261.63}, # C4
		{"t": 1.8, "dur": 1.2, "f": 293.66}, # D4
		{"t": 3.0, "dur": 1.8, "f": 329.63}, # E4
		{"t": 4.8, "dur": 1.4, "f": 392.00}, # G4
		{"t": 6.2, "dur": 1.8, "f": 440.00}  # A4
	]
	
	for i in range(total_samples):
		var t: float = float(i) / float(sample_rate)
		var s: float = 0.0
		# Gentle base drone at 130.81 Hz (C3)
		s += sin(t * 130.81 * TAU) * 0.06
		
		# Melody notes
		for note in melody:
			if t >= note["t"] and t < (note["t"] + note["dur"]):
				var nt: float = t - note["t"]
				var env: float = sin((nt / note["dur"]) * PI) * 0.15 # Soft rounded bell envelope
				s += sin(nt * note["f"] * TAU) * env
				
		var val: int = int(clampf(s * 32767.0, -32768.0, 32767.0))
		bytes.encode_s16(i * 2, val)
		
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = sample_rate
	wav.stereo = false
	wav.data = bytes
	wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
	wav.loop_begin = 0
	wav.loop_end = total_samples
	return wav

# --- Public Playback API ---

func play_sfx(name: String, pitch_scale: float = 1.0) -> void:
	if is_muted or sfx_volume <= 0.001:
		return
	if not _streams.has(name):
		return
		
	var stream: AudioStreamWAV = _streams[name]
	var player: AudioStreamPlayer = _sfx_players[_sfx_index]
	_sfx_index = (_sfx_index + 1) % POOL_SIZE
	
	player.stream = stream
	player.pitch_scale = pitch_scale
	player.volume_db = linear_to_db(sfx_volume)
	player.play()

func play_click() -> void:
	play_sfx("click", randf_range(0.95, 1.05))

func play_build() -> void:
	play_sfx("build", randf_range(0.92, 1.08))

func play_error() -> void:
	play_sfx("error", 1.0)

func play_tech() -> void:
	play_sfx("tech", 1.0)

func play_coin() -> void:
	play_sfx("coin", randf_range(0.96, 1.04))

func play_fanfare() -> void:
	play_sfx("fanfare", 1.0)

func play_alarm() -> void:
	play_sfx("alarm", 1.0)

func start_ambient_music() -> void:
	if _music_player == null or not _streams.has("ambient"):
		return
	_music_player.stream = _streams["ambient"]
	_music_player.volume_db = linear_to_db(music_volume) if not is_muted else -80.0
	if not _music_player.playing:
		_music_player.play()

func stop_ambient_music() -> void:
	if _music_player != null and _music_player.playing:
		_music_player.stop()

func toggle_mute() -> bool:
	is_muted = not is_muted
	return is_muted

func _apply_volumes() -> void:
	var effective_sfx_db: float = linear_to_db(sfx_volume) if not is_muted else -80.0
	for p in _sfx_players:
		if p != null:
			p.volume_db = effective_sfx_db
			
	if _music_player != null:
		var effective_music_db: float = linear_to_db(music_volume) if not is_muted else -80.0
		_music_player.volume_db = effective_music_db
		
	sound_settings_changed.emit(sfx_volume, music_volume, is_muted)
