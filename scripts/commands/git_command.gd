class_name GitCommand
extends BaseCommand
## A teaching subset of git: init, status, add, commit, log, diff — backed by a
## real index-and-commits model (GitModel) that diffs the working tree live.


func get_command_name() -> String: return "git"
func get_category() -> String: return "vcs"
func get_summary() -> String: return "track changes to files with version control"
func get_usage() -> String: return "git [init|status|add|commit|log|diff] ..."
func get_manual() -> String:
	return """git records the history of a project so you can see and undo changes.
  git init             start tracking the current directory
  git status           what's changed, staged, or untracked
  git add FILE         stage a change for the next commit  (git add . stages all)
  git commit -m \"msg\"   save the staged changes as a commit
  git log              the history of commits
The flow is always: edit → `git add` → `git commit`. `.gitignore` lists files
git should ignore (secrets, build output). `status` is your compass — run it
often."""


func execute(ctx: CommandContext) -> int:
	var args := ctx.args()
	if args.is_empty():
		ctx.err("usage: git <command> [<args>]\n")
		return 1
	var sub := str(args[0])
	var rest := args.slice(1)
	var m := ctx.machine()
	if sub == "init":
		return _init_repo(ctx, rest)
	if sub == "config":
		# Accept identity config as a no-op; commits use the login user.
		return 0
	var root := GitModel.repo_root_for(m, ctx.session.cwd)
	if root == "":
		ctx.err("fatal: not a git repository (or any of the parent directories): .git\n")
		return 128
	match sub:
		"status": return _status(ctx, root)
		"add": return _add(ctx, root, rest)
		"commit": return _commit(ctx, root, rest)
		"log": return _log(ctx, root, rest)
		"diff": return _diff(ctx, root, rest)
		"rm": return _rm(ctx, root, rest)
		"branch":
			ctx.out("* %s\n" % GitModel.get_repo(m, root).get("branch", "main"), "exec")
			return 0
		_:
			ctx.err("git: '%s' is not a git command. See 'git --help'.\n" % sub)
			return 1


func _init_repo(ctx: CommandContext, rest: Array) -> int:
	var target := ctx.session.cwd
	for a in rest:
		if not str(a).begins_with("-"):
			target = ctx.resolve(str(a))
			ctx.vfs().ensure_dir(target)
	if GitModel.init(ctx.machine(), ctx.vfs(), target):
		ctx.out("Initialized empty Git repository in %s/.git/\n" % target)
		ctx.emit("git_init", {"root": target})
		return 0
	ctx.out("Reinitialized existing Git repository in %s/.git/\n" % target)
	return 0


func _status(ctx: CommandContext, root: String) -> int:
	var st := GitModel.status(ctx.machine(), ctx.vfs(), root)
	ctx.out("On branch %s\n" % st.branch)
	if not st.has_commits:
		ctx.out("\nNo commits yet\n", "dim")
	if not st.staged.is_empty():
		ctx.out("\nChanges to be committed:\n", "header")
		ctx.out("  (use \"git restore --staged <file>...\" to unstage)\n", "dim")
		for e in st.staged:
			ctx.out("\t%s:   %s\n" % [str(e.kind).rpad(10), e.path], "exec")
	if not st.modified.is_empty() or not st.deleted.is_empty():
		ctx.out("\nChanges not staged for commit:\n", "header")
		ctx.out("  (use \"git add <file>...\" to update what will be committed)\n", "dim")
		for p in st.deleted:
			ctx.out("\tdeleted:    %s\n" % p, "warn")
		for p in st.modified:
			ctx.out("\tmodified:   %s\n" % p, "warn")
	if not st.untracked.is_empty():
		ctx.out("\nUntracked files:\n", "header")
		ctx.out("  (use \"git add <file>...\" to include in what will be committed)\n", "dim")
		for p in st.untracked:
			ctx.out("\t%s\n" % p, "warn")
	if GitModel.is_clean(st):
		if st.has_commits:
			ctx.out("nothing to commit, working tree clean\n")
		else:
			ctx.out("nothing to commit (create/copy files and use \"git add\" to track)\n")
	return 0


func _add(ctx: CommandContext, root: String, rest: Array) -> int:
	var specs: Array = []
	for a in rest:
		if not str(a).begins_with("-") or str(a) == ".":
			specs.append(str(a))
	if specs.is_empty():
		ctx.err("Nothing specified, nothing added.\nhint: Maybe you wanted to say 'git add .'?\n")
		return 1
	var errors := GitModel.add(ctx.machine(), ctx.vfs(), root, ctx.session.cwd, specs)
	for e in errors:
		ctx.err("fatal: pathspec '%s' did not match any files\n" % e)
	if not errors.is_empty():
		return 128
	ctx.emit("git_add", {})
	return 0


func _commit(ctx: CommandContext, root: String, rest: Array) -> int:
	var message := ""
	var stage_all := false
	var i := 0
	while i < rest.size():
		var a := str(rest[i])
		if a == "-m" or a == "--message":
			if i + 1 < rest.size():
				message = str(rest[i + 1])
				i += 1
		elif a == "-a" or a == "--all":
			stage_all = true
		elif a == "-am" or a == "-ma":
			stage_all = true
			if i + 1 < rest.size():
				message = str(rest[i + 1])
				i += 1
		i += 1
	if stage_all:
		GitModel.add(ctx.machine(), ctx.vfs(), root, root, ["."])
	if message == "":
		ctx.err("Aborting commit due to empty commit message.\n")
		ctx.out("hint: use  git commit -m \"your message\"\n", "dim")
		return 1
	var author := "%s <%s@%s>" % [ctx.session.user, ctx.session.user, ctx.machine().hostname]
	var commit := GitModel.commit(ctx.machine(), ctx.vfs(), root, message, author)
	if commit.is_empty():
		var st := GitModel.status(ctx.machine(), ctx.vfs(), root)
		ctx.out("On branch %s\n" % st.branch)
		ctx.out("nothing to commit, working tree clean\n")
		return 1
	var short: String = str(commit.hash).substr(0, 7)
	var repo := GitModel.get_repo(ctx.machine(), root)
	var root_note := "(root-commit) " if repo.commits.size() == 1 else ""
	ctx.out("[%s %s%s] %s\n" % [repo.branch, root_note, short, commit.message])
	ctx.out(" %d file%s changed\n" % [int(commit.files), "" if int(commit.files) == 1 else "s"], "dim")
	ctx.emit("git_commit", {"message": commit.message, "hash": short})
	return 0


func _log(ctx: CommandContext, root: String, rest: Array) -> int:
	var oneline := false
	for a in rest:
		if str(a) == "--oneline":
			oneline = true
	var repo := GitModel.get_repo(ctx.machine(), root)
	var commits: Array = repo.get("commits", [])
	if commits.is_empty():
		ctx.err("fatal: your current branch '%s' does not have any commits yet\n" % repo.get("branch", "main"))
		return 128
	for idx in range(commits.size() - 1, -1, -1):
		var c: Dictionary = commits[idx]
		var short: String = str(c.hash).substr(0, 7)
		if oneline:
			ctx.out("%s " % short, "warn")
			ctx.out("%s\n" % c.message)
		else:
			ctx.out("commit %s%s\n" % [c.hash, " (HEAD -> %s)" % repo.branch if idx == commits.size() - 1 else ""], "warn")
			ctx.out("Author: %s\n" % c.author, "dim")
			ctx.out("\n    %s\n\n" % c.message)
	return 0


func _diff(ctx: CommandContext, root: String, _rest: Array) -> int:
	var st := GitModel.status(ctx.machine(), ctx.vfs(), root)
	if st.modified.is_empty() and st.deleted.is_empty():
		return 0
	for p in st.modified:
		ctx.out("diff --git a/%s b/%s\n" % [p, p], "header")
		ctx.out("--- a/%s\n+++ b/%s\n" % [p, p], "dim")
		ctx.out("(file %s has uncommitted changes)\n" % p)
	for p in st.deleted:
		ctx.out("diff --git a/%s b/%s\ndeleted file\n" % [p, p], "header")
	return 0


func _rm(ctx: CommandContext, root: String, rest: Array) -> int:
	var vfs := ctx.vfs()
	for a in rest:
		if str(a).begins_with("-"):
			continue
		var abs_path := ctx.resolve(str(a))
		vfs.remove(abs_path, ctx.access(), false)
		GitModel.add(ctx.machine(), vfs, root, ctx.session.cwd, [str(a)])
		ctx.out("rm '%s'\n" % a)
	return 0
