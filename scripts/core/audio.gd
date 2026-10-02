extends Node
## Audio (autoload). Background music, crossfaded per context, and sound effects
## wired to EventBus so most of the game makes sound with no call-site changes.
## Two buses — "Music" and "SFX" — are created in code and muted from the
## player's settings, so there's no bus-layout resource to keep in sync.
##
## All assets are CC0 (see assets/sounds/CREDITS.md). Music loop is set here
## rather than in the import files, so a track is just an .mp3 on disk.

const MUSIC_DIR := "res://assets/sounds/music/"
const SFX_DIR := "res://assets/sounds/sfx/"
const FADE := 0.8                     # music crossfade, seconds
const MUSIC_DB := -11.0               # music sits under the SFX and the voice of the game
const SFX_POLYPHONY := 6

# Per-SFX volume trim (dB). Frequent sounds (jump, submit) are pulled down so
# they stay felt rather than heard.
const SFX_GAIN := {
	"jump": -14.0, "submit": -16.0, "navigate": -8.0, "orb": -3.0,
	"success": -2.0, "rankup": 0.0, "achievement": -2.0, "setback": -5.0,
}

var _music_a: AudioStreamPlayer
var _music_b: AudioStreamPlayer
var _music_cur: AudioStreamPlayer     # the player currently foregrounded
var _music_name := ""
var _sfx: Array[AudioStreamPlayer] = []
var _sfx_next := 0
var _music_streams: Dictionary = {}
var _sfx_streams: Dictionary = {}


func _ready() -> void:
	_make_buses()
	_music_a = _make_music_player()
	_music_b = _make_music_player()
	_music_cur = _music_a
	for i in SFX_POLYPHONY:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx.append(p)

	apply_settings()
	EventBus.command_output.connect(_on_command_output)
	EventBus.challenge_completed.connect(func(_c, _r): play("success"))
	EventBus.hint_revealed.connect(func(_i, _t): play("hint"))
	EventBus.rank_up.connect(func(_r): play("rankup"))
	EventBus.achievement_unlocked.connect(func(_a): play("achievement"))
	EventBus.skill_learned.connect(func(_s, _l): play("orb"))
	EventBus.adventure_won.connect(func(): play_music("victory"))
	EventBus.campaign_finished.connect(func(): play_music("victory"))


# --- public API -------------------------------------------------------------

## Play one sound effect by role name (see assets/sounds/sfx/). Unknown names
## and a disabled SFX bus are no-ops, so call sites never have to check.
func play(sfx_name: String) -> void:
	if not _sfx_on():
		return
	var stream := _sfx_stream(sfx_name)
	if stream == null:
		return
	var p := _sfx[_sfx_next]
	_sfx_next = (_sfx_next + 1) % _sfx.size()
	p.stream = stream
	p.volume_db = float(SFX_GAIN.get(sfx_name, -4.0))
	p.play()


## Crossfade the background music to a track by role name (menu / campaign /
## adventure / victory). Asking for the track already playing does nothing.
func play_music(track: String) -> void:
	if track == _music_name:
		return
	_music_name = track
	var stream := _music_stream(track)
	if stream == null:
		return
	var incoming := _music_b if _music_cur == _music_a else _music_a
	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()
	var target := MUSIC_DB if _music_on() else -80.0
	_fade(incoming, target)
	_fade(_music_cur, -40.0, true)
	_music_cur = incoming


func stop_music() -> void:
	_music_name = ""
	_fade(_music_a, -40.0, true)
	_fade(_music_b, -40.0, true)


## Re-read the settings (called at boot and whenever a toggle changes).
func apply_settings() -> void:
	AudioServer.set_bus_mute(AudioServer.get_bus_index("Music"), not _music_on())
	AudioServer.set_bus_mute(AudioServer.get_bus_index("SFX"), not _sfx_on())


# --- internals --------------------------------------------------------------

func _make_buses() -> void:
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, name)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")


func _make_music_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Music"
	p.volume_db = -40.0
	add_child(p)
	return p


func _fade(player: AudioStreamPlayer, to_db: float, stop_after := false) -> void:
	var tw := create_tween()
	tw.tween_property(player, "volume_db", to_db, FADE)
	if stop_after:
		tw.tween_callback(player.stop)


func _music_stream(track: String) -> AudioStream:
	if _music_streams.has(track):
		return _music_streams[track]
	var path := MUSIC_DIR + track + ".mp3"
	if not ResourceLoader.exists(path):
		return null
	var s: AudioStream = load(path)
	if s is AudioStreamMP3:
		s.loop = true
	_music_streams[track] = s
	return s


func _sfx_stream(sfx_name: String) -> AudioStream:
	if _sfx_streams.has(sfx_name):
		return _sfx_streams[sfx_name]
	var path := SFX_DIR + sfx_name + ".ogg"
	var s: AudioStream = load(path) if ResourceLoader.exists(path) else null
	_sfx_streams[sfx_name] = s
	return s


func _music_on() -> bool:
	return bool(_setting("music", true))


func _sfx_on() -> bool:
	return bool(_setting("sfx", true))


func _setting(key: String, fallback: bool) -> bool:
	var g = get_node_or_null("/root/Game")
	if g != null and g.profile != null:
		return bool(g.profile.settings.get(key, fallback))
	return fallback


# A command that errored gets the error sting; anything else a soft submit tick.
func _on_command_output(outcome: ExecutionOutcome) -> void:
	for e in outcome.events:
		if e.name in ["permission_denied", "command_not_found"]:
			play("error")
			return
	play("submit")
