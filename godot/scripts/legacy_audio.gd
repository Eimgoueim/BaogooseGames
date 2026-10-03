extends Node
"""无外部音频资源地移植旧 HTML 的 BGM、叫声与入浴声。"""

const MUSIC_VOL := 0.10
const SFX_VOL := 0.34
const MUSIC_BUS_CUTOFF := 2400.0
const TEMPO := {"home": 74.0, "dungeon": 152.0}
const RESOLUTION := {"home": 2, "dungeon": 4}
const CHORDS := {
	"home": [[60, 64, 67, 72], [57, 60, 64, 69], [53, 57, 60, 65], [55, 59, 62, 67]],
	"dungeon": [[57, 60, 64], [53, 57, 60], [60, 64, 67], [55, 59, 62]],
}
const SAMPLE_RATE := 22050
const CHUNK_FRAMES := 512
const LOOKAHEAD := 0.45

var enabled := true
var track := ""
var step := 0
var sample_cursor := 0
var _step_sample := 0
var _playback: AudioStreamGeneratorPlayback
var _voices: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _duck_start := 0
var _duck_end := 0
var _ducking := false
var _music_bus_lowpass_state := 0.0

func setup(music_enabled: bool = true) -> void:
	enabled = music_enabled
	_rng.randomize()

func _ensure_audio() -> void:
	if not is_inside_tree() or DisplayServer.get_name() == "headless":
		return
	if is_instance_valid(get_node_or_null("AudioPlayer")):
		return
	var player := AudioStreamPlayer.new()
	player.name = "AudioPlayer"
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = SAMPLE_RATE
	generator.buffer_length = 0.25
	player.stream = generator
	add_child(player)
	player.play()
	_playback = player.get_stream_playback() as AudioStreamGeneratorPlayback

func _exit_tree() -> void:
	var player := get_node_or_null("AudioPlayer") as AudioStreamPlayer
	if player != null:
		player.stop()
		# 等音频线程处理完停止命令，再释放它持有的 playback。
		OS.delay_msec(50)
	if player != null:
		player.stream = null
	_playback = null
	if player != null:
		player.free()
	_voices.clear()

func set_music_enabled(value: bool) -> void:
	if enabled == value:
		return
	enabled = value
	if not enabled:
		step = 0
		_step_sample = sample_cursor
		_voices = _voices.filter(func(v: Dictionary) -> bool: return not bool(v.get("music", false)))
	elif track != "":
		step = 0
		_step_sample = sample_cursor
		_ensure_audio()

func play_track(name: String) -> void:
	if not TEMPO.has(name):
		return
	if track == name:
		return
	track = name
	step = 0
	_step_sample = sample_cursor
	_voices = _voices.filter(func(v: Dictionary) -> bool: return not bool(v.get("music", false)))
	if enabled:
		_ensure_audio()

func cry(species: String = "dragon") -> void:
	_ensure_audio()
	# 舊版 CRIES 只決定氣泡文案；所有種類播放完全相同的音高與包絡。
	_add_tone(sample_cursor, 900.0, 0.28, "triangle", 0.28, false, 430.0, 0.02, 0.26, 0.0, 0.0, 0.18, 0.0)
	duck(0.6)

func splash() -> void:
	_ensure_audio()
	_add_tone(sample_cursor, 260.0, 0.32, "sine", 0.24, false, 880.0, 0.02, 0.30, 0.0, 0.0, 0.14, 0.0)
	duck(0.4)

func duck(duration: float) -> void:
	if not _ducking:
		_duck_start = sample_cursor
	_ducking = true
	_duck_end = maxi(sample_cursor, _duck_start) + int(maxf(0.0, duration) * SAMPLE_RATE)

func _process(_delta: float) -> void:
	if _playback == null:
		return
	var available := _playback.get_frames_available()
	while available >= CHUNK_FRAMES:
		_schedule_until(sample_cursor + int(LOOKAHEAD * SAMPLE_RATE))
		var buffer := PackedVector2Array()
		buffer.resize(CHUNK_FRAMES)
		for i in CHUNK_FRAMES:
			var frame := sample_cursor + i
			var sample := _sample_at(frame)
			buffer[i] = Vector2(sample, sample)
		_playback.push_buffer(buffer)
		sample_cursor += CHUNK_FRAMES
		available = _playback.get_frames_available()

func _schedule_until(until_sample: int) -> void:
	if not enabled or track == "":
		return
	var samples_per_step := int(round(SAMPLE_RATE * 60.0 / TEMPO[track] / RESOLUTION[track]))
	while _step_sample <= until_sample:
		_schedule_step(track, step, _step_sample, samples_per_step)
		step += 1
		_step_sample += samples_per_step

func _schedule_step(which: String, st: int, at: int, step_samples: int) -> void:
	var chords: Array = CHORDS[which]
	var per_bar: int = int(RESOLUTION[which]) * 4
	var bar := int(st / per_bar) % chords.size()
	var k := st % per_bar
	var chord: Array = chords[bar]
	var root: int = chord[0] - 24
	var step_duration := float(step_samples) / SAMPLE_RATE
	if which == "home":
		if k == 0:
			for midi in chord:
				_add_tone(at, _midi(float(midi)), step_duration * RESOLUTION[which] * 4, "triangle", 0.05, true, 0.0, 0.05, -1.0, 1600.0, 900.0)
		if k == 0 or k == per_bar / 2:
			_add_tone(at, _midi(float(root)), step_duration * RESOLUTION[which] * 1.6, "sine", 0.075, true, 0.0, 0.05, -1.0)
		var arp: Array = chord.duplicate()
		for i in range(chord.size() - 2, 0, -1):
			arp.append(chord[i])
		_add_tone(at, _midi(float(arp[st % arp.size()] + 12)), step_duration * 1.5, "triangle", 0.045, true, 0.0, 0.05, -1.0)
		if k == 0 and bar % 2 == 1:
			_add_tone(at, _midi(float(chord[2] + 24)), step_duration * 3, "sine", 0.07, true, 0.0, 0.05, -1.0)
	else:
		if k % 2 == 0:
			_add_tone(at, _midi(float(root)), step_duration * 1.4, "sawtooth", 0.055, true, 0.0, 0.05, -1.0, 900.0, 260.0)
		_add_tone(at, _midi(float(chord[(st * 2) % chord.size()] + 12)), step_duration * 0.8, "square", 0.032, true, 0.0, 0.05, -1.0, 2600.0, 1200.0)
		if k == 0 or k == per_bar / 2:
			_add_tone(at, 130.0, 0.16, "sine", 0.13, true, 45.0, 0.05, -1.0, 0.0, 0.0, 0.16)
		if k == int(RESOLUTION[which]) or k == per_bar - int(RESOLUTION[which]):
			_add_hit(at, 0.075, 0.12, 1400.0, true)
		if k % 2 == 0:
			_add_hit(at, 0.028, 0.045, 5200.0, true)
		if k == 0 and (bar == 0 or bar == 2):
			_add_tone(at, _midi(float(chord[1] + 24)), step_duration * 2, "sawtooth", 0.045, true, 0.0, 0.05, -1.0, 3200.0, 1200.0)

func _add_tone(at: int, frequency: float, duration: float, wave: String, volume: float, music: bool, glide: float = 0.0, attack: float = 0.05, decay: float = -1.0, filter_start: float = 0.0, filter_end: float = 0.0, glide_duration: float = -1.0, release_tail: float = 0.02) -> void:
	var envelope_end := at + int(duration * SAMPLE_RATE)
	var attack_time := minf(attack, duration * 0.3) if music else attack
	_voices.append({"start": at, "end": envelope_end + int(release_tail * SAMPLE_RATE), "envelope_end": envelope_end, "freq": frequency, "glide": glide, "glide_duration": glide_duration if glide_duration > 0.0 else duration, "wave": wave, "volume": volume, "music": music, "attack": maxi(1, int(attack_time * SAMPLE_RATE)), "decay": (at + int(decay * SAMPLE_RATE)) if decay >= 0.0 else envelope_end, "filter_start": filter_start, "filter_end": filter_end, "lowpass_state": 0.0, "phase": 0.0})

func _add_hit(at: int, volume: float, duration: float, highpass: float, music: bool) -> void:
	_voices.append({"start": at, "end": at + int(duration * SAMPLE_RATE), "volume": volume, "music": music, "hit": true, "highpass": highpass, "previous_input": 0.0, "previous_output": 0.0, "noise": _rng.randf_range(-1.0, 1.0), "lowpass_state": 0.0})

func _sample_at(frame: int) -> float:
	var music_mix := 0.0
	var sfx_mix := 0.0
	var alive: Array[Dictionary] = []
	var duck_gain := 1.0
	if _ducking:
		if frame < _duck_end:
			var recovery := maxi(1, _duck_end - _duck_start)
			duck_gain = lerpf(0.28, 1.0, clampf(float(frame - _duck_start) / recovery, 0.0, 1.0))
		else:
			_ducking = false
	for voice in _voices:
		var start: int = voice.start
		var end: int = voice.end
		if frame >= end:
			continue
		alive.append(voice)
		if frame < start:
			continue
		var t := float(frame - start) / SAMPLE_RATE
		var duration := float(voice.get("envelope_end", end) - start) / SAMPLE_RATE
		var sample := 0.0
		if voice.get("hit", false):
			var n := _rng.randf_range(-1.0, 1.0)
			var hp_alpha := exp(-2.0 * PI * float(voice.highpass) / SAMPLE_RATE)
			sample = hp_alpha * (float(voice.previous_output) + n - float(voice.previous_input))
			voice.previous_input = n
			voice.previous_output = sample
			sample *= float(voice.volume) * exp(-7.0 * t / duration)
		else:
			var phase_cycles := _phase_cycles(voice, t)
			var phase := 2.0 * PI * phase_cycles
			match String(voice.wave):
				"sine": sample = sin(phase)
				"triangle": sample = (2.0 / PI) * asin(sin(phase))
				"square": sample = 1.0 if sin(phase) >= 0.0 else -1.0
				"sawtooth": sample = fposmod(phase / (2.0 * PI), 1.0) * 2.0 - 1.0
			var attack_progress := clampf(float(frame - start) / float(voice.attack), 0.0, 1.0)
			var envelope := 0.0001 * exp(log(10000.0) * attack_progress)
			var decay_start: int = int(voice.decay) if int(voice.decay) > start else start + int(voice.attack)
			if frame > decay_start:
				envelope *= exp(-9.21 * float(frame - decay_start) / maxi(1, int(voice.envelope_end) - decay_start))
			sample *= envelope * float(voice.volume)
			var f0: float = voice.filter_start
			if f0 > 0.0:
				var f1: float = voice.filter_end
				var cutoff := lerpf(f0, f1, clampf(t / duration, 0.0, 1.0))
				var lp_alpha := 1.0 - exp(-2.0 * PI * cutoff / SAMPLE_RATE)
				voice.lowpass_state = float(voice.lowpass_state) + lp_alpha * (sample - float(voice.lowpass_state))
				sample = float(voice.lowpass_state)
		if voice.music:
			music_mix += sample * MUSIC_VOL * duck_gain
		else:
			sfx_mix += sample * SFX_VOL
	_voices = alive
	# 原版 music bus 经 2400 Hz 低通后与直通的 sfx bus 汇入主总线。
	var bus_alpha := 1.0 - exp(-2.0 * PI * MUSIC_BUS_CUTOFF / SAMPLE_RATE)
	_music_bus_lowpass_state += bus_alpha * (music_mix - _music_bus_lowpass_state)
	var mixed := _music_bus_lowpass_state + sfx_mix
	return clampf(mixed, -0.9, 0.9)

func _midi(note: float) -> float:
	return 440.0 * pow(2.0, (note - 69.0) / 12.0)

func _phase_cycles(voice: Dictionary, elapsed: float) -> float:
	var f0: float = voice.freq
	var target: float = voice.glide
	if target <= 0.0 or is_equal_approx(target, f0):
		return f0 * elapsed
	var glide_time: float = maxf(0.000001, voice.glide_duration)
	var t := minf(maxf(0.0, elapsed), glide_time)
	var log_ratio := log(target / f0)
	var cycles_during_glide := f0 * glide_time * (exp(log_ratio * t / glide_time) - 1.0) / log_ratio
	return cycles_during_glide + target * maxf(0.0, elapsed - glide_time)

func _frequency_at(voice: Dictionary, elapsed: float) -> float:
	var f0: float = voice.freq
	var target: float = voice.glide
	if target <= 0.0 or is_equal_approx(target, f0):
		return f0
	if elapsed >= float(voice.glide_duration):
		return target
	return f0 * pow(target / f0, maxf(0.0, elapsed) / float(voice.glide_duration))

# 给离线测试使用的原版节拍与声部信息。
func get_step_duration() -> float:
	return 60.0 / TEMPO[track] / RESOLUTION[track] if TEMPO.has(track) else 0.0

func get_music_gain() -> float:
	return MUSIC_VOL

func get_sfx_gain() -> float:
	return SFX_VOL

func get_music_bus_cutoff() -> float:
	return MUSIC_BUS_CUTOFF
