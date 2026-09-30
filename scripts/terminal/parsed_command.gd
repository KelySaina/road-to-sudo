class_name ParsedCommand
extends RefCounted
## One simple command inside a pipeline: its words plus redirections.

var words: Array = [] # lexer word tokens
var redirects: Array = [] # {"op": ">", "target": word token}
var background: bool = false
