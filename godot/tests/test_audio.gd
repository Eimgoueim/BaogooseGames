extends SceneTree

const LegacyAudio = preload("res://scripts/legacy_audio.gd")
var failures := 0

func check(condition: bool, message: String) -> void:
	if not condition:
		failures += 1
		printerr(message)

func _initialize() -> void:
	call_deferred("_run_test")

func _run_test() -> void:
	var audio := LegacyAudio.new()
	check(is_equal_approx(audio.get_music_gain(), 0.10), "音乐总线音量应与原版 0.10 一致")
	check(is_equal_approx(audio.get_sfx_gain(), 0.34), "音效总线音量应与原版 0.34 一致")
	check(is_equal_approx(audio.get_music_bus_cutoff(), 2400.0), "音乐主总线应沿用 2400 Hz 低通")
	check(audio.SAMPLE_RATE == 22050, "应使用有效的本地合成采样率")

	audio.cry("goose")
	var cry: Dictionary = audio._voices.back()
	check(is_equal_approx(float(cry.end - cry.start) / audio.SAMPLE_RATE, 0.28), "叫声振荡器应持续 0.28 秒")
	check(is_equal_approx(cry.freq, 900.0) and is_equal_approx(cry.glide, 430.0), "各物种叫声应沿用统一的 900 到 430 Hz 滑音")
	check(is_equal_approx(cry.glide_duration, 0.18), "叫声频率应在 0.18 秒内完成指数滑音，振荡器仍持续 0.28 秒")
	check(is_equal_approx(audio._frequency_at(cry, 0.09), sqrt(900.0 * 430.0)), "叫声滑音中点应符合 Web Audio 指数频率曲线")
	check(is_equal_approx(float(cry.attack) / audio.SAMPLE_RATE, 0.02), "叫声攻击包络应为 0.02 秒")
	check(is_equal_approx(float(cry.decay - cry.start) / audio.SAMPLE_RATE, 0.26), "叫声衰减应从 0.26 秒开始")
	var splash_audio := LegacyAudio.new()
	splash_audio.splash()
	var splash: Dictionary = splash_audio._voices.back()
	check(is_equal_approx(float(splash.end - splash.start) / splash_audio.SAMPLE_RATE, 0.32), "入浴声振荡器应持续 0.32 秒")
	check(is_equal_approx(splash.freq, 260.0) and is_equal_approx(splash.glide, 880.0), "入浴声应沿用 260 到 880 Hz 滑音")
	check(is_equal_approx(splash.glide_duration, 0.14), "入浴声应在 0.14 秒内完成滑音，振荡器仍持续 0.32 秒")
	check(is_equal_approx(splash_audio._frequency_at(splash, 0.07), sqrt(260.0 * 880.0)), "入浴声滑音中点应符合 Web Audio 指数频率曲线")

	# 检查非零 attack 和尾部指数衰减确实进入采样，而不是只记录元数据。
	var envelope_probe := LegacyAudio.new()
	envelope_probe._add_tone(0, 900.0, 0.28, "triangle", 0.28, false, 430.0, 0.02, 0.26, 0.0, 0.0, 0.18)
	var early := absf(envelope_probe._sample_at(307))
	var late := absf(envelope_probe._sample_at(6000))
	check(early > 0.0 and late <= early, "合成样本应包含攻击和衰减包络")

	audio.play_track("home")
	check(is_equal_approx(audio.get_step_duration(), 60.0 / 74.0 / 2.0), "home 音符应按 74 BPM 八分音符调度")
	audio._schedule_until(int(audio.get_step_duration() * audio.SAMPLE_RATE * 2.1))
	check(audio.step == 3, "home 应按原节奏推进三个已到时的步进")
	audio.play_track("dungeon")
	check(is_equal_approx(audio.get_step_duration(), 60.0 / 152.0 / 4.0), "dungeon 音符应按 152 BPM 十六分音符调度")
	audio._voices.clear()
	audio._schedule_step("dungeon", 0, 0, int(round(audio.SAMPLE_RATE * 60.0 / 152.0 / 4.0)))
	var dungeon_glide: Dictionary = {}
	for voice: Dictionary in audio._voices:
		if is_equal_approx(float(voice.get("freq", 0.0)), 130.0):
			dungeon_glide = voice
			break
	check(not dungeon_glide.is_empty() and is_equal_approx(dungeon_glide.glide, 45.0) and is_equal_approx(dungeon_glide.glide_duration, 0.16), "地牢底鼓应保留 130 到 45 Hz、0.16 秒指数滑音")
	check(is_equal_approx(float(dungeon_glide.envelope_end - dungeon_glide.start) / audio.SAMPLE_RATE, 0.16) and is_equal_approx(float(dungeon_glide.end - dungeon_glide.start) / audio.SAMPLE_RATE, 0.18), "地牢底鼓音量包络与振荡器停止时刻应分别为 0.16 和 0.18 秒")
	audio.set_music_enabled(false)
	var frozen_step: int = audio.step
	audio._schedule_until(audio.sample_cursor + audio.SAMPLE_RATE)
	check(audio.step == 0 and frozen_step == 0, "静音时应重置并停止曲目步进")
	audio.set_music_enabled(true)
	audio._schedule_until(audio.sample_cursor + 1)
	check(audio.step > 0, "重新启用音乐后应从曲目起点恢复调度")
	audio.play_track("unknown")
	check(audio.track == "dungeon", "未知曲目不应破坏当前播放状态")

	if failures == 0:
		print("旧版音频合成参数、包络与节拍校验通过")
	audio.free()
	splash_audio.free()
	envelope_probe.free()
	quit(0 if failures == 0 else 1)
