extends "res://tests/test_base.gd"
## Guards the audio layer: every track and sound effect the game asks for must
## exist, or that cue is silently silent — a gap you'd only notice by ear.


func test_music_tracks_exist() -> void:
	for track in ["menu", "campaign", "adventure", "victory"]:
		var path := "res://assets/sounds/music/%s.mp3" % track
		check(ResourceLoader.exists(path), "music track exists: %s" % track)
		if ResourceLoader.exists(path):
			check(load(path) is AudioStreamMP3, "%s is a loopable stream" % track)


func test_sfx_exist() -> void:
	# Every role Audio.play() is ever called with, across the codebase.
	var roles := ["navigate", "select", "back", "submit", "error", "success",
		"hint", "rankup", "achievement", "orb", "jump", "setback", "portal"]
	for role in roles:
		check(ResourceLoader.exists("res://assets/sounds/sfx/%s.ogg" % role),
			"sound effect exists: %s" % role)
