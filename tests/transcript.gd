extends SceneTree
## Dev helper: prints a transcript of commands for eyeballing output format.
##   godot --headless --path . --script res://tests/transcript.gd

func _initialize() -> void:
	var reg := CommandRegistry.create_default()
	var m := MachineBuilder.load_machine("workstation", reg.primary_names())
	var sh := Shell.new(ShellSession.new(m, "player"), reg)
	for line in ["ls -la", "ls -l /home", "id", "ps aux", "cat .bashrc", "lss -la", "sl", "grep -n codeword welcome.txt", "tree -L 2 /home", "stat welcome.txt", "file /usr/bin/ls .bashrc", "wc welcome.txt .bashrc", "man grep", "ls /nope /home", "cd /root", "sudo -l", "chmod", "echo $PATH | tr : '\\n'", "cat /var/log/auth.log | head -n 3", "find /home -name '*.txt'", "history | tail -n 3"]:
		var o := sh.run_line(line)
		print("player@workstation:%s$ %s" % [sh.session.pretty_cwd(), line])
		var t := ""
		for c in o.chunks:
			t += ("!" if c.stream == "err" else "") + c.text
		printraw(t)
	quit()
