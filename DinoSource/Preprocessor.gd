class_name DSPreprocessor

var _included_files: Array[String] = []  # To protect against cyclic switching
var _base_path: String = ""

func process(code: String, base_path: String = "") -> String:
	_included_files.clear()
	_base_path = base_path if base_path != "" else _get_script_dir()
	
	return _process_includes(code, _base_path)


func _process_includes(code: String, current_path: String) -> String:
	var lines = code.split("\n")
	var result = []
	
	for line in lines:
		var trimmed = line.strip_edges()
		
		if trimmed.begins_with("include "):
			var filename = trimmed.substr(8).strip_edges()
			var included_code = _include_file(filename, current_path)
			result.append(included_code)
			result.append("")  # Blank line for readability
		else:
			result.append(line)
	
	return "\n".join(result)


func _include_file(filename: String, current_path: String) -> String:
	# Добавляем расширение если нет
	if not filename.ends_with(".txt") and not filename.ends_with(".gd"):
		filename = filename + ".txt"
	
	# Полный путь к файлу
	var full_path = current_path.path_join(filename)
	
	# Protection against cyclic switching on
	if _included_files.has(full_path):
		push_error("Cyclic inclusion: " + full_path)
		return ""
	
	_included_files.append(full_path)
	
	if not FileAccess.file_exists(full_path):
		push_error("File not found: " + full_path)
		return ""
	
	var file = FileAccess.open(full_path, FileAccess.READ)
	var content = file.get_as_text()
	file.close()
	
	# Recursively process includes within the included file
	return _process_includes(content, current_path)


func _get_script_dir() -> String:
	# We get the directory of the current script
	var script_path = get_script().resource_path
	return script_path.get_base_dir()


func get_included_files() -> Array[String]:
	return _included_files
