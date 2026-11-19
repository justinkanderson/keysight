extends Node
## Zelftest zonder headset of piano: `godot --headless --path . -- --selftest`
## Controleert het MIDI-inlezen, de kalibratiewiskunde en de oefenlogica.

var failures := 0


func _ready() -> void:
	print("=== SELF-TEST ===")
	_test_songs()
	_test_calibration()
	_test_session_play()
	_test_session_wait()
	_test_session_hand()
	_test_notation()
	_test_midi_no_watchdog()
	_test_loop()
	_test_metronome()
	print("=== SELF-TEST DONE: %s ===" % ("OK" if failures == 0 else "%d FAILURE(S)" % failures))
	get_tree().quit(1 if failures > 0 else 0)


func _check(cond: bool, what: String) -> void:
	if cond:
		print("  ok    ", what)
	else:
		failures += 1
		print("  FAIL  ", what)


func _test_songs() -> void:
	print("-- songs")
	var files := DirAccess.get_files_at("res://songs")
	_check(files.size() >= 4, "%d files in res://songs" % files.size())
	for f in files:
		if f.get_extension() != "mid":
			continue
		var s := MidiSong.load_file("res://songs/" + f)
		var l := 0
		var r := 0
		var lo := 200
		var hi := 0
		for n in s.notes:
			if n["hand"] == 0:
				l += 1
			else:
				r += 1
			lo = mini(lo, n["pitch"])
			hi = maxi(hi, n["pitch"])
		print("  %-42s %4d notes  %5.1f s  L%d/R%d  %s-%s  pedal %d  %s" % [
			s.title, s.notes.size(), s.duration, l, r, MidiMonitor.note_name(lo), MidiMonitor.note_name(hi), s.pedal.size(), s.hand_rule])
		_check(s.error == "" and s.notes.size() > 10 and s.duration > 5.0, "load " + f)
		var sorted := true
		for i in range(1, s.notes.size()):
			if s.notes[i]["start"] < s.notes[i - 1]["start"]:
				sorted = false
		_check(sorted, "sorted " + f)
	# Kapotte invoer mag niet crashen.
	var bad := MidiSong.new()
	bad.parse(PackedByteArray([1, 2, 3]))
	_check(bad.error != "", "broken file gives a clean error: " + bad.error)


## Maakt een klavier met bekende plek en schaal, simuleert drukpunten met
## ruis en een uitschieter, en kijkt of de fit de hoeken terugvindt.
func _test_calibration() -> void:
	print("-- calibration")
	var yaw := deg_to_rad(23.0)
	var scale := 0.985
	var xdir := Vector3(cos(yaw), 0, -sin(yaw))
	var zdir := xdir.cross(Vector3.UP).normalized()
	var left := Vector3(0.31, 0.72, -0.48)
	var w := PianoKeyboard.nominal_width()
	var right := left + xdir * w * scale
	var cal := AutoCalibrator.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var notes := [21, 108, 60, 40, 83, 66, 97]
	for note in notes:
		var kx := PianoKeyboard.key_center_x(note) * scale
		var depth := AutoCalibrator.DEPTH_BLACK if PianoKeyboard.is_black(note) else AutoCalibrator.DEPTH_WHITE
		depth += rng.randf_range(-0.01, 0.01)   # niet precies op dezelfde diepte gedrukt
		var p := left + xdir * kx - zdir * depth + Vector3.UP * (PianoKeyboard.key_top_y(note) - AutoCalibrator.BALL_BELOW_TOP)
		p += Vector3(rng.randf_range(-0.002, 0.002), rng.randf_range(-0.002, 0.002), rng.randf_range(-0.002, 0.002))
		cal.samples.append({"note": note, "p": p, "msec": 0})
	# Uitschieter (bv. andere hand gekozen): 6 cm ernaast.
	cal.samples.append({"note": 72, "p": left + xdir * PianoKeyboard.key_center_x(72) + Vector3(0, 0.06, 0.04), "msec": 0})
	var f := cal.fit()
	print("  fit: ok=%s n=%d dropped=%d scale=%.4f width=%.1f cm rms=%.1f mm %s" % [
		f.get("ok"), f.get("n", 0), f.get("dropped", 0), f.get("scale", 0), f.get("width", 0) * 100, f.get("rms", 0) * 1000, f.get("why", "")])
	_check(f.get("ok", false), "fit succeeded")
	if f.get("ok", false):
		var el: float = (f["left"] as Vector3).distance_to(left)
		var er: float = (f["right"] as Vector3).distance_to(right)
		print("  corner error left %.1f mm, right %.1f mm" % [el * 1000, er * 1000])
		_check(el < 0.012 and er < 0.012, "corners within 12 mm")
		_check(f["dropped"] >= 1, "outlier removed")
		_check(absf(f["scale"] - scale) < 0.01, "scale recovered")
		# Plaatsen op een echt klavier-node en een toets terugrekenen.
		var kb := PianoKeyboard.new()
		add_child(kb)
		kb.place_by_corners(f["left"], f["right"], Vector3.UP, true)
		var c4_world := kb.global_transform * Vector3(kb.local_x(60), 0, 0)
		var c4_true := left + xdir * PianoKeyboard.key_center_x(60) * scale
		print("  C4 centre error %.1f mm" % (c4_world.distance_to(c4_true) * 1000))
		_check(c4_world.distance_to(c4_true) < 0.012, "C4 is in the right place")
		kb.queue_free()
	# Te dicht bij elkaar -> geen fit.
	var cal2 := AutoCalibrator.new()
	cal2.samples.append({"note": 60, "p": Vector3(0, 0.7, 0), "msec": 0})
	cal2.samples.append({"note": 62, "p": Vector3(0.0235, 0.7, 0), "msec": 0})
	var f2 := cal2.fit()
	_check(not f2.get("ok", true), "too close together is rejected: " + f2.get("why", ""))
	# Verkeerde schaal (bv. step 1-fout: dubbele trekker) -> geweigerd.
	var cal3 := AutoCalibrator.new()
	cal3.samples.append({"note": 21, "p": Vector3(0, 0.7, 0), "msec": 0})
	cal3.samples.append({"note": 108, "p": Vector3(0.9, 0.7, 0), "msec": 0})
	var f3 := cal3.fit()
	_check(not f3.get("ok", true), "wrong width is rejected: " + f3.get("why", ""))


func _load_session(file: String) -> PracticeSession:
	var s := PracticeSession.new()
	s.load_song(MidiSong.load_file("res://songs/" + file))
	return s


## Speelt alle noten met ruis in de timing; 3 gemist, 2 fout.
func _test_session_play() -> void:
	print("-- play along (Ode to Joy, 80%)")
	var s := _load_session("03 Ode to Joy (Beethoven).mid")
	s.set_wait_mode(false)
	s.speed = 0.8
	s.playing = true
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var dt := 1.0 / 72.0
	var queue: Array = []   # [song_t, pitch, vel]
	var skip := [10, 40, 70]
	for i in s.notes.size():
		if i in skip:
			continue
		var n: Dictionary = s.notes[i]
		var off := rng.randfn(0.035, 0.03) * s.speed   # iets te laat
		queue.append([n["start"] + off, n["pitch"], clampi(n["vel"] + rng.randi_range(-10, 10), 1, 127), n["end"] + off * 0.7])
	queue.sort_custom(func(a, b): return a[0] < b[0])
	var qi := 0
	var offs: Array = []
	var wrong_sent := 0
	var guard := 0
	while not s.done and guard < 200000:
		guard += 1
		s.update(dt)
		while qi < queue.size() and queue[qi][0] <= s.t:
			var q: Array = queue[qi]
			s.note_on(q[1], q[2])
			offs.append([q[3], q[1]])
			if qi == 30 or qi == 60:
				s.note_on(q[1] + 1, 60)   # verkeerde toets ernaast
				wrong_sent += 1
			qi += 1
		for o in offs.duplicate():
			if o[0] <= s.t:
				s.note_off(o[1])
				offs.erase(o)
	print("  hit %d  missed %d  wrong %d  (notes %d)" % [s.hits, s.missed, s.wrong, s.notes.size()])
	_check(s.done, "song ends")
	_check(s.missed == 3, "3 missed detected")
	_check(s.wrong == wrong_sent, "%d wrong detected" % wrong_sent)
	_check(s.hits == s.notes.size() - 3, "the rest hit")
	var rep := s.build_report()
	print("  ---\n  " + rep.replace("\n", "\n  "))
	_check(rep.contains("Timing: average +"), "report detects late playing")


## Wachtmodus: de klok moet stilstaan tot de goede toetsen zijn ingedrukt.
func _test_session_wait() -> void:
	print("-- wait mode (Twinkle)")
	var s := _load_session("01 Twinkle Twinkle Little Star (traditional).mid")
	s.set_wait_mode(true)
	s.speed = 1.0
	# Klok start pas bij de eerste juiste toets.
	var r0 := s.note_on(s.notes[0]["pitch"] + 1, 60)
	_check(not s.playing and r0["kind"] == "free", "wrong key does not start the clock")
	var r1 := s.note_on(s.notes[0]["pitch"], 60)
	_check(s.playing and r1["kind"] == "hit", "correct first key starts the clock")
	# Rest van het eerste akkoord (bv. de linkerhand) ook spelen.
	for k in s.groups[0]["idx"]:
		if s.notes[k]["state"] == NoteHighway.PENDING:
			s.note_on(s.notes[k]["pitch"], 60)
	var dt := 1.0 / 72.0
	for i in 400:
		s.update(dt)
	var g1: float = s.groups[1]["time"]
	_check(absf(s.t - g1) < 0.001 and s.waiting, "clock waits for chord 2 (t=%.2f, chord %.2f)" % [s.t, g1])
	var r2 := s.note_on(40, 60)
	_check(r2["kind"] == "wrong" or r2["kind"] == "other", "other key counts as wrong")
	# Speel alle akkoorden.
	var guard := 0
	while not s.done and guard < 100000:
		guard += 1
		if s.waiting:
			for k in s.groups[s._gi]["idx"]:
				if s.notes[k]["state"] == NoteHighway.PENDING:
					s.note_on(s.notes[k]["pitch"], 70)
		s.update(dt)
	_check(s.done and s.missed == 0 and s.hits == s.notes.size(), "all %d notes hit in wait mode" % s.notes.size())


func _test_session_hand() -> void:
	print("-- per hand (Frere Jacques, right only)")
	var s := _load_session("02 Frere Jacques - round (traditional).mid")
	s.set_wait_mode(true)
	s.set_practice_hand(1)
	var right := 0
	for n in s.notes:
		if n["hand"] == 1:
			right += 1
	var guard := 0
	s.playing = true
	while not s.done and guard < 200000:
		guard += 1
		if s.waiting:
			for k in s.groups[s._gi]["idx"]:
				if s.notes[k]["state"] == NoteHighway.PENDING:
					s.note_on(s.notes[k]["pitch"], 70)
		s.update(1.0 / 72.0)
	_check(s.done and s.hits == right, "only right-hand notes needed (%d of %d)" % [s.hits, s.notes.size()])


func _test_notation() -> void:
	print("-- score")
	var sp := ScoreModel.spell(61, 2)
	_check(sp["letter"] == 0 and sp["alter"] == 1, "C#4 in D major spelled as C sharp")
	sp = ScoreModel.spell(61, -3)
	_check(sp["letter"] == 1 and sp["alter"] == -1, "C#4 in E-flat major spelled as D flat")
	_check(ScoreModel.staff_pos(ScoreModel.spell(64, 0)["step"], true) == 0, "E4 on the bottom line (treble clef)")
	_check(ScoreModel.staff_pos(ScoreModel.spell(77, 0)["step"], true) == 8, "F5 on the top line")
	_check(ScoreModel.staff_pos(ScoreModel.spell(43, 0)["step"], false) == 0, "G2 on the bottom line (bass clef)")
	_check(ScoreModel.staff_pos(ScoreModel.spell(60, 0)["step"], true) == -2, "middle C on the first ledger line")
	_check(ScoreModel.key_alter(3, 1) == 1 and ScoreModel.key_alter(6, -1) == -1 and ScoreModel.key_alter(0, 1) == 0, "key signature: F sharp in G, B flat in F")
	_check(ScoreModel.note_value(5) == 4 and ScoreModel.note_value(6) == 6 and ScoreModel.note_value(16) == 16, "note values quantize")
	# Toonsoortschatting: G-majeur toonladder
	var g_notes: Array = []
	var scale := [55, 57, 59, 60, 62, 64, 66, 67, 71, 74, 79, 62, 67]
	for i in scale.size():
		g_notes.append({"pitch": scale[i], "start": i * 0.5, "end": i * 0.5 + 0.45})
	_check(ScoreModel.estimate_key(g_notes)[0] == 1, "G major detected (1 sharp): %s" % [ScoreModel.estimate_key(g_notes)])
	# Ode to Joy: C-majeur, 4/4, eerste maat = vier kwartnoten rechts
	var song := MidiSong.load_file("res://songs/03 Ode to Joy (Beethoven).mid")
	var sess := PracticeSession.new()
	sess.load_song(song)
	var m := ScoreModel.new()
	m.build(song, sess.notes)
	print("  Ode to Joy: %d bars, %d/%d, key signature %d, %d bars per page" % [m.bars.size(), m.num, m.den, m.fifths, m.bars_per_page])
	_check(m.fifths == 0 and m.num == 4 and m.den == 4, "C major and 4/4")
	var first: Array = m.bars[0]["staves"][0]
	var durs := []
	for e in first:
		durs.append(e["dur"])
	_check(durs == [4, 4, 4, 4], "first bar right hand = four quarter notes: %s" % [durs])
	_check(m.bars.size() == 16, "16 bars")
	# Voortekens binnen een maat: F#4 en dan F4 -> herstellingsteken
	var acc_notes: Array = [
		{"pitch": 66, "start": 0.0, "end": 0.4, "start_tick": 0, "end_tick": 480, "hand": 1},
		{"pitch": 65, "start": 0.5, "end": 0.9, "start_tick": 480, "end_tick": 960, "hand": 1},
		{"pitch": 48, "start": 0.0, "end": 1.9, "start_tick": 0, "end_tick": 1920, "hand": 0},
	]
	var fake := MidiSong.new()
	fake.key_sig = 0
	var m2 := ScoreModel.new()
	m2.build(fake, acc_notes)
	var tre: Array = m2.bars[0]["staves"][0]
	_check(tre[0]["heads"][0]["acc"] == 1 and tre[1]["heads"][0]["acc"] == 0, "F sharp then F in one bar: sharp, then natural")
	_check(tre.size() == 3 and tre[2]["rest"], "rest filled in after the notes")
	var bas: Array = m2.bars[0]["staves"][1]
	_check(bas[0]["dur"] == 16, "whole note in the bass")


## Regressietest (bug van 14-11): een verbonden MIDI-apparaat mag nooit
## "losgekoppeld" worden omdat het stil is of omdat een systeembestand leeg
## lijkt. Na een minuut zonder events moet het apparaat er nog steeds zijn.
func _test_midi_no_watchdog() -> void:
	print("-- MIDI without watchdog")
	var m := MidiMonitor.new()   # bewust niet aan de boom hangen: geen echte MIDI openen
	m.devices = PackedStringArray(["Testpiano"])
	var lost := [false]
	m.devices_changed.connect(func(d: PackedStringArray) -> void:
		if d.is_empty():
			lost[0] = true)
	for i in 60 * 60:
		m._process(1.0 / 60.0)
	_check(not lost[0] and m.devices.size() == 1, "60 s of silence: piano stays connected")
	m.free()


## Bar grid and looping: a loop must repeat, record each pass, and never let
## the clock run past its end.
func _test_loop() -> void:
	print("-- bars and loop (Ode to Joy)")
	var s := _load_session("03 Ode to Joy (Beethoven).mid")
	_check(s.beats_per_bar == 4 and s.bar_index_at(0.0) == 0, "4/4, bar 0 starts at 0 s")
	var mono := true
	for i in range(1, s.bar_times.size()):
		if s.bar_times[i] <= s.bar_times[i - 1]:
			mono = false
	_check(mono and s.bar_times[0] < 0.0, "bar grid increases, with count-in bars before 0 s")
	_check(s.bar_index_at(s.bar_start(5) + 0.01) == 5 and s.bar_index_at(s.bar_start(5) - 0.01) == 4, "bar lookup")

	# Play along, loop bars 3-4, three passes, one note skipped in pass 2.
	s.set_wait_mode(false)
	s.playing = true
	s.set_loop(2, 3)
	var a := s.loop_start_t()
	var e := s.loop_end_t()
	_check(absf(s.t - s.bar_start(1)) < 0.001, "loop starts one bar early (lead-in)")
	var in_loop: Array[int] = []
	for i in s.notes.size():
		if s.notes[i]["start"] >= a - 0.001 and s.notes[i]["start"] < e - 0.001:
			in_loop.append(i)
	_check(in_loop.size() > 4, "%d notes in the loop" % in_loop.size())
	var dt := 1.0 / 72.0
	var guard := 0
	var max_t := -INF
	while s.loop_passes.size() < 3 and guard < 20000:
		guard += 1
		s.update(dt)
		max_t = maxf(max_t, s.t)
		var pass_i := s.loop_passes.size()
		for i in s.notes.size():
			var n: Dictionary = s.notes[i]
			if n["state"] != NoteHighway.PENDING or n["start"] > s.t:
				continue
			if pass_i == 1 and i == in_loop[0]:
				continue
			s.note_on(n["pitch"], 70)
	_check(s.loop_passes.size() == 3, "three passes recorded")
	_check(max_t < e, "clock never passes the loop end (%.2f < %.2f)" % [max_t, e])
	if s.loop_passes.size() == 3:
		_check(s.loop_passes[0]["acc"] == 100.0 and s.loop_passes[2]["acc"] == 100.0, "clean passes score 100%")
		_check(s.loop_passes[1]["hits"] == s.loop_passes[1]["total"] - 1, "skipped note shows in pass 2")
	var after_ok := true
	for n in s.notes:
		if n["start"] >= e + 0.01 and n["state"] != NoteHighway.PENDING:
			after_ok = false
	_check(after_ok, "notes after the loop untouched")
	var rep := s.build_report()
	_check(rep.contains("3 "), "report mentions the loop passes")
	s.clear_loop()
	guard = 0
	while not s.done and guard < 100000:
		guard += 1
		s.update(dt)
	_check(s.done, "loop off: song runs to the end")

	# Wait mode: loop bar 2 twice.
	var w := _load_session("03 Ode to Joy (Beethoven).mid")
	w.set_wait_mode(true)
	w.playing = true
	w.set_loop(1, 1)
	guard = 0
	while w.loop_passes.size() < 2 and guard < 20000:
		guard += 1
		w.update(dt)
		if w.waiting:
			for k in w.groups[w._gi]["idx"]:
				if w.notes[k]["state"] == NoteHighway.PENDING:
					w.note_on(w.notes[k]["pitch"], 70)
	_check(w.loop_passes.size() == 2 and w.loop_passes[1]["acc"] == 100.0 and w.wrong == 0, "wait mode loops cleanly")

	# Count-in: start on a bar line, at least 2 s before the first note.
	var c := _load_session("03 Ode to Joy (Beethoven).mid")
	c.count_in = true
	c.restart()
	var first: float = c.notes[0]["start"]
	var on_bar := absf(c.bar_start(c.bar_index_at(c.t)) - c.t) < 0.001
	_check(on_bar and first - c.t >= 2.0 and c.count_in_end == first, "count-in starts on a bar line, %.2f s early" % (first - c.t))


## Metronome: one click per beat, only before the first note in count-in mode.
func _test_metronome() -> void:
	print("-- metronome")
	var m := Metronome.new()
	add_child(m)
	var c := Metronome.make_click(1000.0)
	_check(c.data.size() > 1000, "click sound generated")
	for mode in [Metronome.ON, Metronome.COUNT_IN]:
		var s := _load_session("03 Ode to Joy (Beethoven).mid")
		s.set_wait_mode(false)
		s.count_in = true
		s.restart()
		s.playing = true
		m.mode = mode
		m.clicks = 0
		m.reset(s.t)
		var t0 := s.t
		for i in 72 * 6:
			s.update(1.0 / 72.0)
			for n in s.notes:
				if n["state"] == NoteHighway.PENDING and n["start"] <= s.t:
					s.note_on(n["pitch"], 70)
			m.step(s)
		var lat := AudioServer.get_output_latency() * s.speed
		var expect := 0
		for b in s.beats:
			if b[0] >= t0 - 0.0001 and b[0] <= s.t + lat and (mode == Metronome.ON or b[0] < s.count_in_end - 0.001):
				expect += 1
		_check(m.clicks == expect and expect > 0, "%s: %d clicks for %d beats" % [
			"on" if mode == Metronome.ON else "count-in", m.clicks, expect])
	m.queue_free()
