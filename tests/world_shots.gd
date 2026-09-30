extends Node
## Dev helper: screenshots of Adventure mode (skill worlds). Needs a display.
##   godot --path . res://tests/world_shots.tscn -- <output_dir>
var out_dir := "user://world_shots"
func _ready():
	var a := OS.get_cmdline_user_args()
	if not a.is_empty(): out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveManager.save_path = "user://world_shot_save.json"; SaveManager.delete_save(); Game.reset_progress()
	Game.profile.settings["text_speed"] = "instant"
	await _run(); SaveManager.delete_save(); get_tree().quit()
func _frames(n := 4):
	for i in n: await get_tree().process_frame
func _phys(n := 8):
	for i in n: await get_tree().physics_frame
func _shot(nm):
	await _frames(8); await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(nm + ".png"))
func _run():
	var main: Control = load("res://scenes/main/main.tscn").instantiate(); add_child(main); await _frames()
	var menu = main.host.get_child(main.host.get_child_count() - 1)
	menu.adventure_requested.emit(); await _frames(6)
	var world = main.host.get_child(main.host.get_child_count() - 1)
	while world._dialogue.visible: world._advance_dialogue()
	await _frames(2)
	world._terminal.set_speed("instant")
	# The course: ledges, pits, skill orbs, the console and the portal.
	await _shot("e1_world_course")
	# Reach an orb -> a skill-learned lesson card.
	if not world._orbs.is_empty():
		world._player.global_position = world._orbs[0].node.global_position
		await _frames(3)
	await _shot("e2_orb_lesson")
	while world._dialogue.visible: world._advance_dialogue()
	await _frames(3)
	# The lesson hands over to a prompt to try the command on.
	world._terminal.set_speed("instant")
	Game.submit("ls -l keycard.sh"); await _frames(3)
	await _shot("e3_orb_practice")
	if world._overlay.visible: world._close_terminal()
	await _frames(2)
	# Collect the rest, then open the trial and ask it to teach a command.
	for guard in 8:
		if world._orbs.is_empty(): break
		world._player.global_position = world._orbs[0].node.global_position
		await _frames(3)
		while world._dialogue.visible: world._advance_dialogue()
		await _frames(2)
		if world._overlay.visible: world._close_terminal()
		await _frames(1)
	# The end plateau: the trial console and the portal.
	world._player.global_position = world._console.global_position + Vector2(-70, 0)
	await _frames(6)
	await _shot("e4_console_and_portal")
	world._interact(world._console); await _frames(3)
	Game.submit("talk chmod"); await _frames(3)
	await _shot("e5_trial_console")
	if world._overlay.visible: world._close_terminal()
	# One wide shot of each world's course, to compare their obstacles.
	for wi in range(Game.adventure.world.count()):
		Game.adventure.state.mark_passed(str(Game.adventure.world.world_at(wi).get("id", "")))
	for wi in range(Game.adventure.world.count()):
		world._load_world(wi)
		await _frames(2)
		while world._dialogue.visible: world._advance_dialogue()
		await _frames(2)
		if world._overlay.visible: world._close_terminal()
		world._camera.zoom = Vector2(0.62, 0.62)
		world._player.global_position = Vector2(world.TILE * 20, world.GROUND_ROW * world.TILE)
		await _frames(10)
		await _shot("w%d_course" % (wi + 1))
