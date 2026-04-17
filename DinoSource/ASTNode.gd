# Basic AST node
class_name ASTNode

var type: String
var data: Dictionary = {}
var line: int = -1

func _init(_type, _data = {}, _line = -1):
	type = _type
	data = _data
	line = _line

func _to_string():
	return type + " " + str(data)
