extends "res://tests/test_base.gd"


func test_paths() -> void:
	check_eq(PathUtils.normalize("/a/b/../c/./d/"), "/a/c/d", "normalize")
	check_eq(PathUtils.normalize("/.."), "/", "root parent is root")
	check_eq(PathUtils.join("/home/player", "../alice"), "/home/alice", "join relative")
	check_eq(PathUtils.join("/tmp", "/etc"), "/etc", "join absolute")
	check_eq(PathUtils.basename("/var/log/auth.log"), "auth.log", "basename")
	check_eq(PathUtils.dirname("/var/log/auth.log"), "/var/log", "dirname")
	check_eq(PathUtils.dirname("/var"), "/", "dirname of top level")
	check_eq(PathUtils.prettify("/home/player/x", "/home/player"), "~/x", "prettify")


func test_permissions() -> void:
	check_eq(Permissions.from_octal("755"), 493, "755")
	check_eq(Permissions.from_octal("9"), -1, "invalid octal")
	check_eq(Permissions.to_symbolic(Permissions.from_octal("750"), "d"), "drwxr-x---", "symbolic")
	check_eq(Permissions.to_octal(Permissions.from_octal("644")), "644", "to_octal")
	var m := Permissions.from_octal("644")
	check_eq(Permissions.to_octal(Permissions.apply_spec(m, "u+x")), "744", "u+x")
	check_eq(Permissions.to_octal(Permissions.apply_spec(m, "+x")), "755", "+x")
	check_eq(Permissions.to_octal(Permissions.apply_spec(m, "go-r")), "600", "go-r")
	check_eq(Permissions.to_octal(Permissions.apply_spec(m, "u=rwx,g=rx,o=")), "750", "multi clause")
	check_eq(Permissions.apply_spec(m, "u+q"), -1, "bad spec")


func test_vfs_permissions() -> void:
	var vfs := VirtualFileSystem.new()
	vfs.ensure_dir("/home/alice", "alice", "alice", Permissions.from_octal("700"))
	vfs.put_file("/home/alice/secret", "x", "alice", "alice", Permissions.from_octal("600"))
	var player := AccessContext.new("player", PackedStringArray(["player"]))
	check_eq(vfs.read_file("/home/alice/secret", player).error, VirtualFileSystem.EACCES, "cannot traverse 700 dir")
	check(vfs.read_file("/home/alice/secret", AccessContext.new("root", PackedStringArray(["root"]))).ok, "root reads anything")
	vfs.ensure_dir("/tmp").mode = Permissions.from_octal("777")
	check(vfs.write_file("/tmp/x", "hi", player).ok, "write in /tmp")
	check_eq(vfs.get_node_at("/tmp/x").owner, "player", "new file owned by creator")
	check_eq(vfs.write_file("/etc/passwd2", "x", player).error, VirtualFileSystem.ENOENT, "missing /etc")
	vfs.ensure_dir("/etc")
	check_eq(vfs.write_file("/etc/passwd2", "x", player).error, VirtualFileSystem.EACCES, "no write in /etc")


func test_vfs_copy_move_remove() -> void:
	var vfs := VirtualFileSystem.new()
	vfs.ensure_dir("/w")
	vfs.put_file("/w/a.txt", "A")
	vfs.ensure_dir("/w/dir")
	check(vfs.copy("/w/a.txt", "/w/dir").ok, "copy into dir")
	check_eq(vfs.get_node_at("/w/dir/a.txt").content, "A", "copied content")
	check(vfs.move("/w/a.txt", "/w/b.txt").ok, "rename")
	check(not vfs.exists("/w/a.txt") and vfs.exists("/w/b.txt"), "moved")
	check_eq(vfs.remove("/w/dir").error, VirtualFileSystem.EISDIR, "rm dir needs -r")
	check(vfs.remove("/w/dir", null, true).ok, "rm -r")
	check_eq(vfs.move("/w", "/w/inner").error, "cannot move a directory into itself", "mv into self")


func test_vfs_serialization() -> void:
	var m := MachineBuilder.load_machine("workstation", ["ls"])
	var restored := Machine.from_dict(JSON.parse_string(JSON.stringify(m.to_dict())))
	check_eq(restored.hostname, "workstation", "hostname survives")
	check_eq(restored.vfs.get_node_at("/home/player/welcome.txt").content, m.vfs.get_node_at("/home/player/welcome.txt").content, "content survives JSON")
	check_eq(restored.vfs.get_node_at("/home/alice").mode, Permissions.from_octal("750"), "mode survives JSON")
	check_eq(restored.processes.size(), m.processes.size(), "processes survive")


func test_lexer_and_parser() -> void:
	var p := CommandParser.parse("echo 'a | b' \"c $HOME\" | grep a > out.txt && ls; pwd")
	check_eq(p.error, "", "parses")
	check_eq(p.segments.size(), 3, "three segments")
	check_eq(p.segments[0].pipeline.size(), 2, "pipeline of two")
	check_eq(p.segments[0].pipeline[1].redirects[0].op, ">", "redirect")
	check_eq(p.segments[1].join, "&&", "and-join")
	check_eq(p.segments[2].join, ";", "semicolon join")
	check(CommandParser.parse("ls |").error != "", "dangling pipe")
	check(CommandParser.parse("| ls").error != "", "leading pipe")
	check(CommandParser.parse("echo >").error.contains("newline"), "missing redirect target")
	check(CommandParser.parse("echo 'unterminated").error != "", "unterminated quote")
	check_eq(CommandParser.parse("ls # a comment").segments[0].pipeline[0].words.size(), 1, "comment stripped")
	check_eq(CommandParser.parse("find . -exec rm {} \\;").segments.size(), 1, "escaped semicolon is a word")


func test_profile_roundtrip() -> void:
	var p := PlayerProfile.new()
	p.xp = 321
	p.completed["t01_identity"] = {"xp": 150, "hints": 0, "solution": false}
	p.achievements["first_command"] = 1
	p.bump("pipes", 3)
	var q := PlayerProfile.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	check_eq(q.xp, 321, "xp")
	check(q.completed.has("t01_identity"), "completed")
	check_eq(int(q.stats.pipes), 3, "stats")
	check(q.achievements.has("first_command"), "achievements")


func test_progression() -> void:
	var p := PlayerProfile.new()
	var prog := Progression.new(p)
	check_eq(prog.current_rank().name, "Newbie", "starts as Newbie")
	prog.award(460)
	check_eq(prog.current_rank().name, "Shell Apprentice", "rank from xp")
	prog.award(100000)
	check_eq(prog.current_rank().name, "Linux Operator", "gated ranks need their challenge")
	var c := Challenge.from_dict({"id": "x", "xp": 100})
	var beginner := DifficultySettings.load_id("beginner")
	check_eq(Progression.score_challenge(c, 0, false, beginner, 10).total, 150, "no hints: +50")
	check_eq(Progression.score_challenge(c, 1, false, beginner, 10).total, 125, "one hint: +25")
	check_eq(Progression.score_challenge(c, 2, false, beginner, 10).total, 110, "two hints: +10")
	check_eq(Progression.score_challenge(c, 3, true, beginner, 10).total, 100, "solution: +0")


func test_achievements() -> void:
	var p := PlayerProfile.new()
	var a := AchievementSystem.load_default(p)
	var shell := new_shell()
	a.check_outcome(shell.run_line("sudo ls"))
	check(a.is_unlocked("sudo_please"), "sudo Please")
	a.check_outcome(shell.run_line("cat /etc/shadow"))
	check(a.is_unlocked("permission_denied"), "Permission Denied")
	check(a.is_unlocked("forbidden_fruit"), "hidden: shadow")
	a.check_outcome(shell.run_line("cat /var/log/auth.log | grep Failed | cut -d' ' -f1 | sort"))
	check(a.is_unlocked("pipe_dream"), "Pipe Dream")
	check(a.is_unlocked("pipe_organ"), "Pipe Organ (4 stages)")
	a.check_outcome(shell.run_line("sudo make me a sandwich"))
	check(a.is_unlocked("sandwich"), "xkcd")


func test_wrap_text() -> void:
	var view: GDScript = load("res://scripts/ui/terminal_view.gd")
	var wrapped: String = view.wrap_text("  OBJECTIVE  Find the account under attack and write just that name into a file.", 40)
	var lines := wrapped.split("\n")
	check(lines[0].begins_with("  OBJECTIVE  Find"), "first line keeps its indent: '%s'" % lines[0])
	check(lines[1].begins_with("             ") and not lines[1].begins_with("              "), "continuation aligns after the label: '%s'" % lines[1])
	for l in lines:
		check(l.length() <= 40, "line fits: '%s'" % l)
	check_eq(view.wrap_text("short", 40), "short", "short text untouched")
