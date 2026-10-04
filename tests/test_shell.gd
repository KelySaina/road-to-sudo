extends "res://tests/test_base.gd"


func test_basics() -> void:
	var sh := new_shell()
	check_eq(out(sh, "whoami"), "player\n", "whoami")
	check_eq(out(sh, "pwd"), "/home/player\n", "pwd")
	check(out(sh, "ls").contains("welcome.txt"), "ls lists welcome")
	check(not out(sh, "ls").contains(".hidden_note"), "ls hides dotfiles")
	check(out(sh, "ls -a").contains(".hidden_note"), "ls -a shows dotfiles")
	check(out(sh, "ls -la").contains("-rw-r--r--"), "ls -l shows modes")
	check(out(sh, "cat welcome.txt").contains("LANTERN"), "cat")
	check_eq(out(sh, "echo hello   world"), "hello world\n", "echo")
	check_eq(out(sh, "echo \"$USER in $HOME\""), "player in /home/player\n", "variables")
	check_eq(out(sh, "echo '$USER'"), "$USER\n", "single quotes are literal")
	check_eq(out(sh, "echo \\$USER"), "$USER\n", "backslash escape")


func test_control_flow() -> void:
	var sh := new_shell()
	check_eq(out(sh, "for i in 1 2 3; do echo n=$i; done"), "n=1\nn=2\nn=3\n", "for over a list")
	check_eq(out(sh, "for i in a b; do echo $i; done; echo end"), "a\nb\nend\n", "compound then a command")
	check_eq(out(sh, "if [ 2 -gt 1 ]; then echo yes; else echo no; fi"), "yes\n", "if/then true branch")
	check_eq(out(sh, "if [ 1 -gt 2 ]; then echo yes; else echo no; fi"), "no\n", "if/then else branch")
	check_eq(out(sh, "if false; then echo a; elif true; then echo b; else echo c; fi"), "b\n", "elif branch")
	check_eq(out(sh, "echo today: $(whoami)"), "today: player\n", "command substitution")
	check_eq(out(sh, "echo $(echo one; echo two)"), "one two\n", "substitution joins lines with spaces")
	# nested loop + conditional
	check_eq(out(sh, "for n in 1 2 3; do if [ $n -eq 2 ]; then echo hit; fi; done"), "hit\n", "nested if inside for")
	# test / [ as a command
	check_eq(run(sh, "test -f welcome.txt").exit_code, 0, "test -f on a real file is true")
	check_eq(run(sh, "[ -f nope ]").exit_code, 1, "[ -f ] on a missing file is false")
	check_eq(run(sh, "[ abc = abc ]").exit_code, 0, "string equality")
	# a while that drains a condition
	run(sh, "touch /tmp/lock")
	check_eq(out(sh, "while [ -f /tmp/lock ]; do echo working; rm /tmp/lock; done"), "working\n", "while runs until its condition fails")
	# globs feed the loop
	check(out(sh, "for f in *.txt; do echo got $f; done").contains("got welcome.txt"), "for over a glob")


func test_arithmetic() -> void:
	var sh := new_shell()
	check_eq(out(sh, "echo $((2 + 3))"), "5\n", "addition")
	check_eq(out(sh, "echo $(( (2+3) * 4 ))"), "20\n", "parentheses and precedence")
	check_eq(out(sh, "echo $((10 / 3))"), "3\n", "integer division")
	check_eq(out(sh, "echo $((10 % 3))"), "1\n", "modulo")
	check_eq(out(sh, "echo $((7 / 0))"), "0\n", "division by zero is 0, not a crash")
	check_eq(out(sh, "echo $((-3 + 1))"), "-2\n", "unary minus")
	check_eq(out(sh, "echo $((2 > 1))"), "1\n", "comparison is 1 when true")
	check_eq(out(sh, "echo $((2 < 1))"), "0\n", "comparison is 0 when false")
	check_eq(out(sh, "echo $((5 == 5))"), "1\n", "equality")
	check_eq(out(sh, "echo $((1 && 0))"), "0\n", "logical and")
	check_eq(out(sh, "echo a$((1+1))b"), "a2b\n", "expansion sits inside a word")
	run(sh, "i=5")
	check_eq(out(sh, "echo $((i + 1))"), "6\n", "bare variable name resolves")
	check_eq(out(sh, "echo $(($i * 2))"), "10\n", "$-prefixed variable resolves")
	check_eq(out(sh, "echo $((nope + 2))"), "2\n", "an unset variable reads as 0")
	check_eq(out(sh, "for n in 1 2 3; do echo $((n * n)); done"), "1\n4\n9\n", "arithmetic inside a loop")


func test_glob_classes() -> void:
	var sh := new_shell()
	run(sh, "cd /tmp")
	for f in ["a1.txt", "a2.txt", "b1.txt", "c9.log"]:
		run(sh, "echo x > " + f)
	check_eq(out(sh, "echo [ab]1.txt"), "a1.txt b1.txt\n", "[ab] character class")
	check_eq(out(sh, "echo a[0-9].txt"), "a1.txt a2.txt\n", "[0-9] range")
	check_eq(out(sh, "echo [!a]1.txt"), "b1.txt\n", "[!a] negation")
	check_eq(out(sh, "echo nomatch[0-9].zz"), "nomatch[0-9].zz\n", "no match stays literal")


func test_case() -> void:
	var sh := new_shell()
	run(sh, "x=start")
	check_eq(out(sh, "case $x in start) echo GO ;; stop) echo HALT ;; esac"), "GO\n", "first pattern matches")
	run(sh, "x=stop")
	check_eq(out(sh, "case $x in start) echo GO ;; stop) echo HALT ;; esac"), "HALT\n", "later pattern matches")
	check_eq(out(sh, "case notes.txt in *.log) echo log ;; *.txt) echo text ;; esac"), "text\n", "glob pattern")
	check_eq(out(sh, "case c in a|b|c) echo abc ;; *) echo other ;; esac"), "abc\n", "alternation with |")
	check_eq(out(sh, "case zzz in a) echo A ;; *) echo DEFAULT ;; esac"), "DEFAULT\n", "* is the default")
	check_eq(out(sh, "case 5 in [0-9]) echo digit ;; *) echo no ;; esac"), "digit\n", "[0-9] character class")
	check_eq(out(sh, "case q in a) echo A ;; esac"), "", "no match runs nothing")
	# only the first matching clause runs
	check_eq(out(sh, "case ab in a*) echo one ;; *b) echo two ;; esac"), "one\n", "first match wins, not every match")
	# a multi-line case in a script
	var src := "#!/bin/bash\nfor w in cat dog fish\ndo\n  case $w in\n    cat|dog) echo $w is a pet ;;\n    *) echo $w is not ;;\n  esac\ndone\n"
	sh.session.machine.vfs.put_file("/home/player/pets.sh", src, "player", "player", Permissions.from_octal("755"))
	check_eq(out(sh, "./pets.sh"), "cat is a pet\ndog is a pet\nfish is not\n", "multi-line case inside a for loop")


func test_multiline_script() -> void:
	var sh := new_shell()
	var src := "#!/bin/bash\nfor n in 1 2 3\ndo\n  if [ $n -gt 1 ]\n  then\n    echo big $n\n  fi\ndone\n"
	sh.session.machine.vfs.put_file("/home/player/s.sh", src, "player", "player", Permissions.from_octal("755"))
	check_eq(out(sh, "./s.sh"), "big 2\nbig 3\n", "multi-line for+if block runs from a script")


func test_cd() -> void:
	var sh := new_shell()
	run(sh, "cd /var/log")
	check_eq(sh.session.cwd, "/var/log", "cd absolute")
	run(sh, "cd ..")
	check_eq(sh.session.cwd, "/var", "cd ..")
	run(sh, "cd -")
	check_eq(sh.session.cwd, "/var/log", "cd -")
	run(sh, "cd")
	check_eq(sh.session.cwd, "/home/player", "cd home")
	var o := run(sh, "cd /home/alice")
	check(o.all_text().contains("Permission denied"), "cannot enter alice's home")
	check(o.has_event("permission_denied"), "permission event")
	check(text(sh, "cd nowhere").contains("No such file or directory"), "cd missing")


func test_files() -> void:
	var sh := new_shell()
	run(sh, "mkdir -p a/b/c && touch a/b/c/f.txt")
	check(sh.session.machine.vfs.exists("/home/player/a/b/c/f.txt"), "mkdir -p && touch")
	run(sh, "echo one > a/x.txt; echo two >> a/x.txt")
	check_eq(out(sh, "cat a/x.txt"), "one\ntwo\n", "> and >>")
	run(sh, "cp a/x.txt a/y.txt && mv a/y.txt a/b/")
	check(sh.session.machine.vfs.exists("/home/player/a/b/y.txt"), "cp + mv")
	check(text(sh, "rm a").contains("Is a directory"), "rm dir without -r")
	run(sh, "rm -r a")
	check(not sh.session.machine.vfs.exists("/home/player/a"), "rm -r")
	check(text(sh, "rm -rf /").contains("dangerous"), "rm -rf / refused")
	check(text(sh, "touch /etc/nope").contains("Permission denied"), "no write in /etc")


func test_glob_and_find() -> void:
	var sh := new_shell()
	run(sh, "mkdir logs && echo ERROR one > logs/a.log && echo fine > logs/b.log && echo ERROR two > logs/c.txt")
	check_eq(out(sh, "echo logs/*.log"), "logs/a.log logs/b.log\n", "glob expansion")
	check_eq(out(sh, "echo 'logs/*.log'"), "logs/*.log\n", "quoted glob stays literal")
	check_eq(out(sh, "echo nomatch*"), "nomatch*\n", "unmatched glob stays literal")
	check_eq(out(sh, "find logs -name '*.log'"), "logs/a.log\nlogs/b.log\n", "find -name")
	check_eq(out(sh, "find logs -name '*.log' -exec grep ERROR {} \\;"), "ERROR one\n", "find -exec")
	check_eq(out(sh, "grep -r ERROR logs"), "logs/a.log:ERROR one\nlogs/c.txt:ERROR two\n", "grep -r")
	check_eq(out(sh, "find logs -type d"), "logs\n", "find -type d")


func test_pipes_and_text() -> void:
	var sh := new_shell()
	var count := out(sh, "grep 'Failed password' /var/log/auth.log | grep -c mallory").strip_edges()
	check_eq(count, "64", "intruder hit count")
	var top := out(sh, "grep \"Failed password\" /var/log/auth.log | grep -o \"for [a-z]*\" | sort | uniq -c | sort -rn | head -1")
	check(top.contains("mallory"), "classic top-N pipeline finds mallory: " + top)
	check_eq(out(sh, "cat /var/log/auth.log | wc -l").strip_edges(), "3000", "wc -l via pipe")
	check_eq(out(sh, "ls | wc -l").strip_edges(), "1", "ls is one-per-line into a pipe")
	check_eq(out(sh, "echo hello | tr a-z A-Z"), "HELLO\n", "tr")
	check_eq(out(sh, "cut -d: -f1 /etc/passwd | head -n 2"), "root\nplayer\n", "cut + head")
	check_eq(out(sh, "echo -e 'b\\na\\nb' | sort | uniq -c"), "      1 a\n      2 b\n", "sort | uniq -c")
	check_eq(out(sh, "wc -l < /etc/passwd").strip_edges(), "4", "input redirect")


func test_exit_codes_and_chains() -> void:
	var sh := new_shell()
	check_eq(out(sh, "false && echo no || echo yes"), "yes\n", "&& / ||")
	check_eq(out(sh, "false; echo $?"), "1\n", "$?")
	check_eq(out(sh, "cat /nope 2> /dev/null; echo $?"), "1\n", "2> /dev/null")
	var o := run(sh, "lss")
	check_eq(o.exit_code, 127, "not found = 127")
	check(o.all_text().contains("Did you mean:") and o.all_text().contains("    ls"), "suggests ls")
	check(text(sh, "Ls").contains("ls"), "case typo suggestion")
	run(sh, "GREETING=hi")
	check_eq(out(sh, "echo $GREETING"), "hi\n", "assignment")


func test_scripts_and_permissions() -> void:
	var sh := new_shell()
	run(sh, "echo 'echo from script' > s.sh")
	var o := run(sh, "./s.sh")
	check_eq(o.exit_code, 126, "not executable = 126")
	check(o.all_text().contains("Permission denied"), "permission denied message")
	check_eq(out(sh, "bash s.sh"), "from script\n", "bash only needs read")
	run(sh, "chmod u+x s.sh")
	check_eq(out(sh, "./s.sh"), "from script\n", "runs after chmod")
	check_eq(out(sh, "./s.sh > captured.txt; cat captured.txt"), "from script\n", "script output is redirectable")
	run(sh, "echo 'echo one; exit 3; echo never' > e.sh; chmod 755 e.sh")
	var e := run(sh, "./e.sh")
	check_eq(e.stdout_text(), "one\n", "exit stops script")
	check_eq(e.exit_code, 3, "script exit code")
	check(text(sh, "chmod 777 /etc/passwd").contains("Operation not permitted"), "chmod on others' files")
	check(text(sh, "chown alice welcome.txt").contains("Operation not permitted"), "only root gives files away")
	check(out(sh, "ls -l s.sh").begins_with("-rwxr--r--"), "mode after u+x")


func test_sudo() -> void:
	var sh := new_shell()
	var o := run(sh, "sudo cat /etc/shadow")
	check(o.all_text().contains("not in the sudoers file"), "sudo denied for player")
	check(o.has_event("sudo_denied"), "sudo_denied event")
	# Promote the player and try again.
	sh.session.machine.users.player.groups.append("sudo")
	check(out(sh, "sudo cat /etc/shadow").contains("root:"), "sudo runs as root")
	check_eq(sh.session.user, "player", "back to player afterwards")
	run(sh, "sudo -i")
	check_eq(sh.session.user, "root", "sudo -i")
	check_eq(sh.session.cwd, "/root", "root home")
	run(sh, "exit")
	check_eq(sh.session.user, "player", "exit returns")


func test_processes() -> void:
	var sh := new_shell()
	check(out(sh, "ps aux").contains("sshd"), "ps aux")
	check(text(sh, "kill 502").contains("Operation not permitted"), "cannot kill root's process")
	run(sh, "kill 1337")
	check(sh.session.machine.find_process(1337).is_empty(), "kill own process")


func test_help_and_man() -> void:
	var sh := new_shell()
	check(out(sh, "help").contains("chmod"), "help lists commands")
	check(out(sh, "man chmod").contains("SYNOPSIS"), "man page")
	check(text(sh, "man nothing").contains("No manual entry"), "no man page")
	check_eq(out(sh, "which ls"), "/usr/bin/ls\n", "which")
	check(registry().primary_names().size() >= 40, "at least 40 commands registered (%d)" % registry().primary_names().size())


func test_suggestions() -> void:
	check_eq(registry().suggest("lss")[0], "ls", "lss -> ls first")
	check(registry().suggest("sl").has("ls"), "transposition sl -> ls")
	check_eq(registry().suggest("grpe")[0], "grep", "grpe -> grep")
	check_eq(registry().suggest("LS")[0], "ls", "case-insensitive")
	check(registry().suggest("xyzzyplugh").is_empty(), "nonsense has no suggestion")


func test_fd_duplication() -> void:
	var sh := new_shell()
	check_eq(out(sh, "cat /nope 2>&1 | wc -l").strip_edges(), "1", "2>&1 sends errors down the pipe")
	run(sh, "ls /nope ~ > both.txt 2>&1")
	var both: String = sh.session.machine.vfs.get_node_at("/home/player/both.txt").content
	check(both.contains("No such file") and both.contains("welcome.txt"), "2>&1 into a file captures both streams")
	var o := run(sh, "echo oops >&2")
	check_eq(o.stdout_text(), "", ">&2 writes nothing to stdout")
	check(o.all_text().contains("oops"), ">&2 still shows on screen")
	check_eq(CommandParser.parse("cmd 2>&1 &").segments.size(), 1, "2>&1 is not a background operator")
