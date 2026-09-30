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
func _find(w,nid,kind:=-1):
	for it in w._objects:
		if it.node_id==nid and (kind==-1 or it.kind==kind): return it
	return null
func _run():
	var main:Control = load("res://scenes/main/main.tscn").instantiate(); add_child(main); await _frames()
	var menu=main.host.get_child(main.host.get_child_count()-1)
	menu.adventure_requested.emit(); await _frames(6)
	var world=main.host.get_child(main.host.get_child_count()-1)
	while world._dialogue.visible: world._advance_dialogue()
	await _frames(2)
	world._terminal.set_speed("instant")
	# open the gate to reach the Locksmith's room (or just teleport into gate room)
	Game.adventure.state.cleared["gate"]=true  # so we can stand freely; still shows both chars
	var lock=_find(world,"gate",Interactable.Kind.NPC)
	world._player.global_position=lock.global_position+Vector2(40,40)
	await _phys(6); await _frames(3)
	await _shot("e1_room_with_teacher")     # Locksmith + Gate console in one room
	# talk to the Locksmith
	world._interact(lock); await _frames(3)
	await _shot("e2_npc_teaches")
	while world._dialogue.visible: world._advance_dialogue()
	# open a console and ask it to teach a command
	var con=_find(world,"gate",Interactable.Kind.CONSOLE)
	world._player.global_position=con.global_position+Vector2(0,48)
	await _phys(6); await _frames(3)
	Game.adventure.state.cleared.erase("gate")  # reopen the fight so the console engages
	world._interact(con); await _frames(3)
	Game.submit("talk chmod"); await _frames(3)
	await _shot("e3_talk_command")
