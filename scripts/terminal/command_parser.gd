class_name CommandParser
extends RefCounted
## Grammar (subset of POSIX sh):
##   list      := pipeline ( ("&&" | "||" | ";" | "&") pipeline )* [";" | "&"]
##   pipeline  := command ( "|" command )*
##   command   := ( word | redirect )+
##   redirect  := (">" | ">>" | "<" | "2>" | "2>>") word  |  "2>&1"  |  ">&2"
##
## Result: {"segments": [{"join": "", "pipeline": [ParsedCommand, ...]}, ...], "error": ""}
## `join` tells the executor how a segment relates to the previous one.

const REDIRECT_OPS := [">", ">>", "<", "2>", "2>>"]
const DUP_OPS := ["2>&1", ">&2"]
const LIST_OPS := ["&&", "||", ";", "&"]


static func parse(line: String) -> Dictionary:
	var lexed := ShellLexer.tokenize(line)
	if lexed.error != "":
		return {"segments": [], "error": lexed.error}
	var tokens: Array = lexed.tokens
	var segments: Array = []
	var pipeline: Array = []
	var current := ParsedCommand.new()
	var join := ""
	var i := 0

	while i < tokens.size():
		var tok: Dictionary = tokens[i]
		if tok.type == "word":
			current.words.append(tok)
			i += 1
			continue

		var op: String = tok.value
		if op in DUP_OPS:
			current.redirects.append({"op": op})
			i += 1
			continue
		if op in REDIRECT_OPS:
			if i + 1 >= tokens.size() or tokens[i + 1].type != "word":
				var next_tok: String = "newline" if i + 1 >= tokens.size() else tokens[i + 1].value
				return _error("syntax error near unexpected token `%s'" % next_tok)
			current.redirects.append({"op": op, "target": tokens[i + 1]})
			i += 2
			continue

		if current.words.is_empty():
			return _error("syntax error near unexpected token `%s'" % op)

		if op == "|":
			pipeline.append(current)
			current = ParsedCommand.new()
			if i + 1 >= tokens.size():
				return _error("syntax error: pipe with nothing after it")
			i += 1
			continue

		# list operator ends the pipeline
		if op == "&":
			current.background = true
		pipeline.append(current)
		segments.append({"join": join, "pipeline": pipeline})
		pipeline = []
		current = ParsedCommand.new()
		join = op if op != "&" else ";"
		i += 1
		if (op == "&&" or op == "||") and i >= tokens.size():
			return _error("syntax error: `%s' needs a command after it" % op)

	if not current.words.is_empty() or not current.redirects.is_empty():
		if current.words.is_empty():
			return _error("syntax error: redirection without a command")
		pipeline.append(current)
	if not pipeline.is_empty():
		segments.append({"join": join, "pipeline": pipeline})
	return {"segments": segments, "error": ""}


static func _error(message: String) -> Dictionary:
	return {"segments": [], "error": message}
