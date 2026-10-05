class_name SoundEffects
extends Object

static var _cache: Dictionary = {}
static var _snow_steps: Array[AudioStream] = []
static var _concrete_steps: Array[AudioStream] = []
static var _shovel_scrapes: Array[AudioStream] = []
static var _swishes: Array[AudioStream] = []
static var _snow_thuds: Array[AudioStream] = []

static func _init_arrays() -> void:
	if not _snow_steps.is_empty():
		return
	
	# Snow footsteps (Kenney + OpenGameArt)
	for i in range(1, 6):
		var s = load("res://audio/snow_step_%d.ogg" % i) as AudioStream
		if s: _snow_steps.append(s)
	var sw1 = load("res://audio/SnowWalk.ogg") as AudioStream
	if sw1: _snow_steps.append(sw1)
	var sw2 = load("res://audio/SnowWalk2.ogg") as AudioStream
	if sw2: _snow_steps.append(sw2)
	
	# Asphalt/concrete footsteps
	for i in range(1, 6):
		var s = load("res://audio/concrete_step_%d.ogg" % i) as AudioStream
		if s: _concrete_steps.append(s)
	
	# Shovel scrapes on asphalt
	for i in range(1, 9):
		var s = load("res://audio/shovel_scrape_%d.ogg" % i) as AudioStream
		if s: _shovel_scrapes.append(s)
	var s_dig = load("res://audio/shovel_dig.ogg") as AudioStream
	if s_dig: _shovel_scrapes.append(s_dig)
	
	# Shovel-throw swishes / whooshes
	for name in ["swish_1", "swish_2", "swish_10", "swish_11", "swish_12", "swish_13"]:
		var s = load("res://audio/%s.wav" % name) as AudioStream
		if s: _swishes.append(s)
	
	# Muffled snow impacts
	for i in range(1, 4):
		var s = load("res://audio/snow_thud_%d.ogg" % i) as AudioStream
		if s: _snow_thuds.append(s)

static func get_snow_step() -> AudioStream:
	_init_arrays()
	if not _snow_steps.is_empty():
		return _snow_steps.pick_random()
	return get_sound("snow_step")

static func get_concrete_step() -> AudioStream:
	_init_arrays()
	if not _concrete_steps.is_empty():
		return _concrete_steps.pick_random()
	return get_sound("pavement_step")

static func get_shovel_scrape() -> AudioStream:
	_init_arrays()
	if not _shovel_scrapes.is_empty():
		return _shovel_scrapes.pick_random()
	return get_sound("shovel_scrape")

static func get_swish() -> AudioStream:
	_init_arrays()
	if not _swishes.is_empty():
		return _swishes.pick_random()
	return get_sound("snow_toss")

static func get_snow_thud() -> AudioStream:
	_init_arrays()
	if not _snow_thuds.is_empty():
		return _snow_thuds.pick_random()
	return get_sound("snow_impact")

static func get_sound(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	
	var stream: AudioStream = null
	match name:
		"snowblower":
			stream = load("res://audio/snowblower_loop.mp3")
			if stream and stream is AudioStreamMP3:
				(stream as AudioStreamMP3).loop = true
		"wind":
			stream = load("res://audio/wind_loop.ogg")
			if stream and stream is AudioStreamOggVorbis:
				(stream as AudioStreamOggVorbis).loop = true
		"salt_shake":
			stream = load("res://audio/salt_pour.ogg")
		"coin":
			stream = _create_coin()
		"victory":
			stream = _create_victory()
	
	if stream:
		_cache[name] = stream
	return stream

static func _create_wav(samples: Array[float], rate: int = 22050) -> AudioStreamWAV:
	var wav = AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = rate
	wav.stereo = false
	var bytes = PackedByteArray()
	bytes.resize(samples.size() * 2)
	for i in range(samples.size()):
		var val = clampf(samples[i], -1.0, 1.0)
		bytes.encode_s16(i * 2, int(val * 32000.0))
	wav.data = bytes
	return wav

static func _create_coin() -> AudioStreamWAV:
	var rate = 22050
	var count = int(rate * 0.3)
	var samples: Array[float] = []
	samples.resize(count)
	for i in range(count):
		var t = float(i) / float(count)
		var env = exp(-t * 9.0)
		var tone1 = sin(float(i) * (1318.5 * TAU / rate)) * 0.5
		var tone2 = sin(float(i) * (1975.5 * TAU / rate)) * 0.4
		samples[i] = (tone1 + tone2) * env * 0.55
	return _create_wav(samples, rate)

static func _create_victory() -> AudioStreamWAV:
	var rate = 22050
	var count = int(rate * 0.85)
	var samples: Array[float] = []
	samples.resize(count)
	var notes = [523.25, 659.25, 783.99, 1046.5]
	var note_dur: int = int(float(count) / 4.0)
	for i in range(count):
		var note_idx = mini(int(float(i) / float(note_dur)), 3)
		var note_t = float(i % note_dur) / float(note_dur)
		var freq = notes[note_idx]
		var env = exp(-note_t * 5.0)
		var tone = sin(float(i) * (freq * TAU / rate)) * 0.6
		var harmonic = sin(float(i) * (freq * 2.0 * TAU / rate)) * 0.2
		samples[i] = (tone + harmonic) * env * 0.65
	return _create_wav(samples, rate)
