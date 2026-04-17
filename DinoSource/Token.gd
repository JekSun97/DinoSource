class_name Token

var type
var value
var line

func _init(_type, _value, _line):
	type = _type
	value = _value
	line = _line
	
func is_type(t):
	return type == t

func is_value(v):
	return value == v

func _to_string():
	return str(type) + ":" + str(value) + " (line " + str(line) + ")"
