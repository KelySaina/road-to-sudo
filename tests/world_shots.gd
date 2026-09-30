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
	world._terminal.set_speed("instant")
	var gate=_find(world,"gate"); world._player.global_position=gate.global_position+Vector2(0,48)
	await _phys(6); await _frames(3)
	world._interact(gate); await _frames(3)
	# reproduce the reported sequence: cd around, prompt must follow
	for c in ["ls","cd /etc","pwd","cd /var/log","pwd","ls"]:
		Game.submit(c)
	await _frames(3)
	await _shot("fix_prompt_follows_cd")
