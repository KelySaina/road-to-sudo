extends Node
var out_dir := "user://world_shots"
func _ready():
	var a := OS.get_cmdline_user_args()
	if not a.is_empty(): out_dir = a[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveManager.save_path="user://world_shot_save.json"; SaveManager.delete_save(); Game.reset_progress()
	Game.profile.settings["text_speed"]="instant"
	await _run(); SaveManager.delete_save(); get_tree().quit()
func _frames(n:=4):
	for i in n: await get_tree().process_frame
func _phys(n:=8):
	for i in n: await get_tree().physics_frame
func _shot(nm):
	await _frames(8); await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(nm+".png"))
func _find(w,nid):
	for it in w._objects:
		if it.node_id==nid: return it
	return null
func _run():
	var main:Control = load("res://scenes/main/main.tscn").instantiate(); add_child(main); await _frames()
	var menu=main.host.get_child(main.host.get_child_count()-1)
	menu.adventure_requested.emit(); await _frames(6)
	var world=main.host.get_child(main.host.get_child_count()-1)
	while world._dialogue.visible: world._advance_dialogue()
	await _frames(2)
	# jump straight into the archive fight and hunt with ls to trigger the nudge
	Game.adventure.state.add_flag("keycard"); Game.adventure.state.add_flag("intel"); Game.adventure.state.add_flag("cpu_freed")
	Game.adventure.state.cleared["gate"]=true; Game.adventure.state.cleared["swamp"]=true; Game.adventure.state.cleared["foundry"]=true
	var arc=_find(world,"archive"); world._player.global_position=arc.global_position+Vector2(0,50)
	await _phys(6); await _frames(3)
	world._terminal.set_speed("instant")
	world._interact(arc); await _frames(3)
	Game.submit("ls /etc"); await _frames(3)
	await _shot("nudge_find")
