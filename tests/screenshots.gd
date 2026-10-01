extends Node
## Dev helper: renders key screens to PNG (needs a display, not --headless).
##   godot --path . res://tests/screenshots.tscn -- <output_dir>

var out_dir := "user://screenshots"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	SaveManager.save_path = "user://screenshot_save.json"
	SaveManager.delete_save()
	Game.reset_progress()
	Game.profile.settings["text_speed"] = "instant"
	await _run()
	SaveManager.delete_save()
	get_tree().quit()


func _frames(n: int = 4) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await _frames(6)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out_dir.path_join(name + ".png"))


func _run() -> void:
	var main: Control = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await _shot("01_menu")
	var menu = main.host.get_child(main.host.get_child_count() - 1)
	menu._open_new_journey()
	await _shot("02_new_journey")
	menu.journey_requested.emit("beginner", false)
	await _frames()
	Game.profile.settings["text_speed"] = "instant"
	var screen = main.host.get_child(main.host.get_child_count() - 1)
	screen.terminal.set_speed("instant")
	for line in ["lss", "whoami"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("03_first_challenge")
	# Jump to the permission challenge and poke at it.
	Game.start_challenge("t09_permission")
	await _frames()
	for line in ["./backup.sh", "ls -l", ":hint", ":hint", "cat backup.sh"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	screen.terminal.input.text = "chmod u"
	screen.terminal._on_text_changed("chmod u")
	await _shot("04_permission_challenge")
	screen.terminal.input.text = ""
	for line in ["chmod u+x backup.sh", "./backup.sh"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("05_completed")
	Game.start_challenge("t08_needle")
	await _frames()
	for line in ["grep 'Failed password' /var/log/auth.log | grep -o 'for [a-z]*' | sort | uniq -c | sort -rn", "ls -la /home", "ps aux"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("06_pipes")
	# Level 7 — Services: the diagnostic loop on app-01.
	Game.start_challenge("l7_failed")
	await _frames()
	for line in ["systemctl status webapp", "journalctl -u webapp"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("08_services")
	# Level 8 — Networking: the operator's toolkit on net-01.
	Game.start_challenge("l8_ports")
	await _frames()
	for line in ["ip addr show eth0", "ss -tlnp", "ping -c 2 backup.lan"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("09_networking")
	# Level 9 — Packages: search, dependency-resolving install, audit.
	Game.start_challenge("l9_install")
	await _frames()
	for line in ["apt search tcpdump", "sudo apt install tcpdump", "dpkg -l openssl"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("10_packages")
	# Level 10 — Git: the init → add → commit loop.
	Game.start_challenge("l10_init")
	await _frames()
	for line in ["cd ~/site", "git status", "git init", "git add .", "git commit -m \"initial commit\"", "git log --oneline"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("11_git")
	# Level 11 — SSH: log into a remote box and fix it.
	Game.start_challenge("l11_login")
	await _frames()
	for line in ["curl -I http://web-01/", "ssh admin@web-01", "systemctl status nginx", "sudo systemctl start nginx", "systemctl is-active nginx"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("12_ssh")
	# Level 12 — Bash: loops and logic.
	Game.start_challenge("l12_if")
	await _frames()
	for line in ["cd ~/hosts", "ls", "for h in *; do if [ -s \"$h\" ]; then echo \"$h\" >> ~/up.txt; fi; done", "cat ~/up.txt"]:
		screen.terminal._on_submitted(line)
		await _frames(1)
	await _shot("13_bash")
	Game.submit(":menu")
	await _frames()
	menu = main.host.get_child(main.host.get_child_count() - 1)
	menu._open_achievements()
	await _shot("07_achievements")
