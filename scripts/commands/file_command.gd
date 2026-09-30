class_name FileCommand
extends BaseCommand


func get_command_name() -> String: return "file"
func get_category() -> String: return "files"
func get_summary() -> String: return "guess what kind of file something is"
func get_usage() -> String: return "file FILE..."
func get_manual() -> String:
	return "Linux does not trust file extensions: `file` looks at the content instead."


func execute(ctx: CommandContext) -> int:
	if ctx.args().is_empty():
		return usage_error(ctx)
	var code := 0
	for f in ctx.args():
		var res := ctx.vfs().lookup(ctx.resolve(f), ctx.access())
		if not res.ok:
			ctx.out("%s: cannot open `%s' (%s)\n" % [f, f, res.error])
			code = 1
			continue
		ctx.out("%s: %s\n" % [f, describe(res.node)])
	return code


static func describe(n: VFSNode) -> String:
	if n.is_dir():
		return "directory"
	var c := n.content
	if c == "":
		return "empty"
	if c.begins_with("\u007fELF"):
		return "ELF 64-bit LSB pie executable, x86-64, dynamically linked, stripped"
	var exec_text := " executable" if (n.mode & 73) != 0 else ""
	if c.begins_with("#!/bin/bash") or c.begins_with("#!/usr/bin/env bash"):
		return "Bourne-Again shell script, ASCII text%s" % exec_text
	if c.begins_with("#!/bin/sh"):
		return "POSIX shell script, ASCII text%s" % exec_text
	if c.begins_with("#!"):
		return "script, ASCII text%s" % exec_text
	if c.strip_edges().begins_with("{"):
		return "JSON text data"
	return "ASCII text"
