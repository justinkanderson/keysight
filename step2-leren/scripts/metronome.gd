class_name Metronome
extends Node
## Click track that follows the song clock, so it slows down with the tempo
## setting and stops while wait mode is waiting. Beat 1 of each bar gets a
## higher, accented click. The clicks are generated in code (no audio files).
##
## Modes: OFF, COUNT_IN (only before the first note, and in the lead-in bar
## of a loop) and ON (all the time).

enum { OFF, COUNT_IN, ON }

var mode := OFF
var volume_db := -4.0:
	set(v):
		volume_db = v
		if _hi:
			_hi.volume_db = v
			_lo.volume_db = v - 3.0
var clicks := 0                 # number of clicks played (for the self-test)
var last_beat_in_bar := -1      # for the beat indicator

var _hi: AudioStreamPlayer
var _lo: AudioStreamPlayer
var _last_t := INF


func _ready() -> void:
	_hi = _player(make_click(1760.0))
	_lo = _player(make_click(1175.0))
	volume_db = volume_db


func _player(stream: AudioStream) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	add_child(p)
	return p


## Short sine burst with a fast decay: a clean, woody click.
static func make_click(freq: float, ms := 40.0) -> AudioStreamWAV:
	var rate := 44100
	var n := int(rate * ms / 1000.0)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := exp(-float(i) / (rate * 0.007))
		var v := sin(TAU * freq * i / rate) * env * 0.9
		data.encode_s16(i * 2, int(v * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.stereo = false
	s.data = data
	return s


func cycle() -> void:
	mode = (mode + 1) % 3


## Call when the song clock jumps (start, restart), so no click is skipped
## or doubled.
func reset(t: float) -> void:
	_last_t = t - 0.0005


## Call once per frame after the session has advanced. Plays the click for
## any beat the song clock has just passed.
func step(s: PracticeSession) -> void:
	var now := s.t
	if mode == OFF or not s.playing or s.beats.is_empty():
		_last_t = now
		return
	# Trigger a little early to make up for the audio output latency.
	var to := now + AudioServer.get_output_latency() * s.speed
	var from := _last_t
	if to < from:
		# Clock went back (loop wrap or seek): start counting from here.
		from = now - 0.0005
	elif to - from > 1.0:
		# Big jump forward (wait mode skipping ahead): don't play a burst.
		from = to - 0.0005
	_last_t = to
	var i := s.beat_index_at(to)
	if i < 0:
		return
	var beat: Array = s.beats[i]
	if beat[0] <= from:
		return
	if mode == COUNT_IN and beat[0] >= s.count_in_end - 0.001:
		return
	last_beat_in_bar = beat[1]
	clicks += 1
	if beat[1] == 0:
		_hi.play()
	else:
		_lo.play()
