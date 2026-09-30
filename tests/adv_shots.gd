extends Node
## Renders adventure-mode screens to PNG (needs a display).
##   godot --path . res://tests/adv_shots.tscn -- <dir>
var out_dir := "user://adv_shots"

func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if not a.is_empty(): out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveManager.save_path = "user://adv_shot_save.json"
	SaveManager.delete_save(); Game.reset_progress()
	Game.profile.settings["text_speed"] = "instant"
	await _run(); SaveManager.delete_save(); get_tree().quit()

func _frames(n:=4) -> void:
	for i in n: await get_tree().process_frame

func _shot(name:String) -> void:
	await _frames(6); await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name+".png"))

func _submit(screen, line:String) -> void:
	screen.terminal.set_speed("instant")
	screen.terminal._on_submitted(line)
	await _frames(2)

func _run() -> void:
	var main:Control = load("res://scenes/main/main.tscn").instantiate()
	add_child(main); await _frames()
	var menu = main.host.get_child(main.host.get_child_count()-1)
	await _shot("a1_menu")
	menu.adventure_requested.emit(); await _frames(3)
	var screen = main.host.get_child(main.host.get_child_count()-1)
	screen.terminal.set_speed("instant")
	await _shot("a2_home")
	await _submit(screen, "cat OPERATOR.txt")
	await _submit(screen, "go east")
	await _submit(screen, "ls -l keycard.sh")
	await _submit(screen, "hint")
	await _shot("a3_gate_fight")
	await _submit(screen, "chmod +x keycard.sh")
	await _submit(screen, "./keycard.sh")
	await _shot("a4_gate_won")
	# fast-forward to the boss
	Game.adventure.state.add_flag("keycard"); Game.adventure.state.add_flag("intel"); Game.adventure.state.add_flag("cpu_freed")
	Game.adventure.state.cleared["gate"]=true; Game.adventure.state.cleared["swamp"]=true; Game.adventure.state.cleared["foundry"]=true
	Game.adventure._enter("gatekeeper", false); await _frames(2)
	await _submit(screen, "go north")
	await _submit(screen, "sudo -i")
	await _submit(screen, "ps aux")
	await _submit(screen, "kill 1313")
	await _shot("a5_boss_respawn")
	await _submit(screen, "rm /opt/initd-imposter/imposterd")
	await _submit(screen, "kill 1313")
	await _shot("a6_victory")
