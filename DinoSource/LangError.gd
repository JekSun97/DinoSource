class_name LangError

static func error(type: String, message: String, node: ASTNode, code: String):
	var line
	if node!=null:
		line = node.line
	else:
		line = 0
	
	push_error("\n====================")
	push_error("[" + type + "] Line: " + str(line))
	push_error(message)
	
	var lines = code.split("\n")
	if line >= 0 and line < lines.size():
		var src = lines[line]
		push_error("Code: " + src)
		push_error("      ^")
	
	push_error("====================\n")
