class_name DSInterpreter

var source_code = ""
var globals: Dictionary = {}
var functions: Dictionary = {}
var native_functions: Dictionary = {}  #Функции на GDScript
var classes: Dictionary = {} 
var enums: Dictionary = {}
var constants: Dictionary = {}
var labels: Dictionary = {}

# =========================
# ЗАПУСК
# =========================
func run(ast: Array):
	#for node in ast:
		#exec(node, globals)
	globals.clear()
	functions.clear()
	classes.clear()
	enums.clear()
	constants.clear()
	labels.clear()
	
	#  Шаг 1: Собираем все метки (пре-процессинг)
	for i in range(ast.size()):
		if ast[i].type == "Point":
			labels[ast[i].data["label"]] = i
	
	#  Шаг 2: Выполняем код с поддержкой прыжков
	var i = 0
	while i < ast.size():
		var node = ast[i]
		var result = exec(node, globals)
		
		# Обработка возврата из функции
		if result is ReturnValue:
			return result.value
		
		#  Обработка прыжка
		if result is JumpValue:
			var target_label = result.label
			if labels.has(target_label):
				i = labels[target_label]  # Прыгаем на метку
				continue
			else:
				LangError.error("Runtime Error", "Метка не найдена: " + target_label, node, source_code)
		
		i += 1


# =========================
# EXEC (выполнение нод)
# =========================
func exec(node: ASTNode, scope: Dictionary):
	if node == null:
		return null
	
	match node.type:
		
		"VarDecl":
			if !scope.has(node.data["name"]):
				var var_type = node.data.get("var_type", null)
				var value = null
				
				# Если есть значение — вычисляем его
				if node.data["value"] != null:
					value = eval_expr(node.data["value"], scope)
					#  ТИП-ИНФЕРЕНС: если тип "var", определяем по значению
					if var_type == "var":
						match typeof(value):
							TYPE_INT:
								var_type = "int"
							TYPE_FLOAT:
								#  Если число дробное — тип float, иначе int
								if value == floor(value):
									var_type = "int"
								else:
									var_type = "float"
							TYPE_STRING:
								var_type = "string"
							TYPE_BOOL:
								var_type = "bool"
							TYPE_ARRAY:
								var_type = "array"
				# Если нет значения — берём дефолт по типу
				else:
					value = get_default_value(var_type, node)
				
				# Проверка типа (теперь value всегда не-null)
				if not check_type(var_type, value):
					LangError.error(
						"Type Error",
						"Нельзя присвоить " + type_to_string(value) + " в " + var_type,
						node,
						source_code
					)
					return
				
				scope[node.data["name"]] = {
					"type": var_type,
					"value": value
				}
			else:
				LangError.error(
					"Runtime Error",
					"Переменная уже существует: " + node.data["name"],
					node,
					source_code
				)
		
		"ConstDecl":
			var name = node.data["name"]
			var value = eval_expr(node.data["value"], scope)
			var const_type = node.data.get("const_type", null)
			
			# Проверка: константа уже существует?
			if constants.has(name):
				LangError.error(
					"Runtime Error",
					"Константа уже существует: " + name,
					node,
					source_code
				)
				return
			
			# Проверка типа (как у var)
			if not check_type(const_type, value):
				LangError.error(
					"Type Error",
					"Нельзя присвоить " + type_to_string(value) + " в " + const_type,
					node,
					source_code
				)
				return
			
			# Сохраняем константу
			constants[name] = {
				"type": const_type,
				"value": value
			}
		
		
		"Assign":
			var left = node.data["left"]
			var value = eval_expr(node.data["right"], scope)
			
			# ПРОВЕРКА: присваивание элементу массива? (arr[0] = 5)
			if left.type == "ArrayAccess":
				var array = eval_expr(left.data["array"], scope)
				var index = eval_expr(left.data["index"], scope)
				
				# Проверка: это массив?
				if typeof(array) != TYPE_ARRAY:
					LangError.error("Runtime Error", "Ожидается массив", node, source_code)
					return
				
				# Проверка: индекс — число?
				if typeof(index) != TYPE_FLOAT:
					LangError.error("Runtime Error", "Индекс должен быть числом", node, source_code)
					return
				
				var idx = int(index)
				
				# Отрицательные индексы
				if idx < 0:
					idx = array.size() + idx
				
				# Границы массива
				if idx < 0 or idx >= array.size():
					LangError.error("Runtime Error", "Индекс вне границ: " + str(idx), node, source_code)
					return
				
				array[idx] = value  # Меняем элемент массива!
				return  # Выходим, не выполняем код ниже
			
			# ПРОВЕРКА: присваивание полю объекта? (this.name = "x" или obj.field = 5)
			if left.type == "MemberAccess":
				var member = left.data["member"]
				var obj = eval_expr(left.data["object"], scope)
				
				# Проверка: это 'this'?
				if left.data["object"].type == "Identifier" and left.data["object"].data["name"] == "this":
					# 'this' уже должен быть в scope как экземпляр
					if scope.has("this") and typeof(scope["this"]) == TYPE_DICTIONARY:
						obj = scope["this"]
				
				# Проверка: это экземпляр класса?
				if typeof(obj) == TYPE_DICTIONARY and obj.get("__is_instance__", false):
					if obj["__fields__"].has(member):
						# Устанавливаем значение поля
						obj["__fields__"][member]["value"] = value
						return value
					else:
						LangError.error(
							"Runtime Error",
							"Поле не найдено: " + member,
							node,
							source_code
						)
						return null
				else:
					LangError.error(
						"Runtime Error",
						"Присваивание полю по не-объекту",
						node,
						source_code
					)
					return null
			
			# ОБЫЧНОЕ присваивание переменной (i = 5)
			var name = left.data["name"]
			
			var var_data = get_var_full(scope, name)
			if var_data != null:
				var expected_type = var_data["type"]
				
				if not check_type(expected_type, value):
					LangError.error(
						"Type Error",
						"Нельзя присвоить " + type_to_string(value) + " в " + expected_type,
						node,
						source_code
					)
			set_var(scope, name, value)
		
		
		"Delete":
			var name = node.data["name"]
			
			# 1. Находим переменную ПЕРЕД удалением (чтобы вызвать деструктор)
			var var_data = get_var_full(scope, name)
			
			# 2. Если это экземпляр класса — вызываем деструктор
			if var_data != null:
				var value = var_data["value"]
				
				# Проверка: это экземпляр класса?
				if typeof(value) == TYPE_DICTIONARY and value.get("__is_instance__", false):
					var _class_name = value.get("__class__")
					var class_def = classes.get(_class_name)
					
					# Если у класса есть деструктор — выполняем его
					if class_def != null and class_def.has("destructor") and class_def["destructor"] != null:
						var destructor = class_def["destructor"]
						
						# Создаём скоуп с this для деструктора
						var local = {"__parent__": scope, "this": value}
						
						# Выполняем тело деструктора
						exec_block(destructor["body"], local)
			
			# 3. Теперь удаляем переменную из скоупа
			delete_var(scope, name, node)
			
			# Не возвращаем значение, это инструкция
		
		# CompoundAssign (+=, -=, *=, /=, %=)
		"CompoundAssign":
			var left = node.data["left"]
			var op = node.data["op"]
			var right = eval_expr(node.data["right"], scope)
			
			# ПРОВЕРКА 1: это доступ к элементу массива? (arr[0] *= 2)
			if left.type == "ArrayAccess":
				var array = eval_expr(left.data["array"], scope)
				var index = eval_expr(left.data["index"], scope)
				
				# Проверка: это массив?
				if typeof(array) != TYPE_ARRAY:
					LangError.error("Runtime Error", "Ожидается массив", node, source_code)
					return null
				
				# Проверка: индекс — число?
				if typeof(index) != TYPE_FLOAT:
					LangError.error("Runtime Error", "Индекс должен быть числом", node, source_code)
					return null
				
				var idx = int(index)
				
				# Отрицательные индексы
				if idx < 0:
					idx = array.size() + idx
				
				# Границы массива
				if idx < 0 or idx >= array.size():
					LangError.error("Runtime Error", "Индекс вне границ: " + str(idx), node, source_code)
					return null
				
				# Вычисляем новое значение
				var current_value = array[idx]
				var new_value = null
				
				match op:
					"+=": new_value = current_value + right
					"-=": new_value = current_value - right
					"*=": new_value = current_value * right
					"/=": 
						if typeof(right) == TYPE_FLOAT and right == 0:
							LangError.error("Runtime Error", "Деление на ноль", node, source_code)
							return null
						new_value = current_value / right
					"%=": 
						if typeof(right) == TYPE_FLOAT and right == 0:
							LangError.error("Runtime Error", "Деление на ноль в операции %", node, source_code)
							return null
						new_value = fmod(current_value, right)
				
				array[idx] = new_value
				return new_value
			
			# ПРОВЕРКА 2: это доступ к полю? (this.value *= x или obj.field += 1)
			if left.type == "MemberAccess":
				var member = left.data["member"]
				var obj = eval_expr(left.data["object"], scope)
				
				# Проверка: это 'this'?
				if left.data["object"].type == "Identifier" and left.data["object"].data["name"] == "this":
					if scope.has("this") and typeof(scope["this"]) == TYPE_DICTIONARY:
						obj = scope["this"]
				
				# Проверка: это экземпляр класса?
				if typeof(obj) == TYPE_DICTIONARY and obj.get("__is_instance__", false):
					if obj["__fields__"].has(member):
						var current_value = obj["__fields__"][member]["value"]
						var new_value = null
						
						match op:
							"+=": new_value = current_value + right
							"-=": new_value = current_value - right
							"*=": new_value = current_value * right
							"/=": 
								if typeof(right) == TYPE_FLOAT and right == 0:
									LangError.error("Runtime Error", "Деление на ноль", node, source_code)
									return null
								new_value = current_value / right
							"%=": 
								if typeof(right) == TYPE_FLOAT and right == 0:
									LangError.error("Runtime Error", "Деление на ноль в операции %", node, source_code)
									return null
								new_value = fmod(current_value, right)
						
						obj["__fields__"][member]["value"] = new_value
						return new_value
					else:
						LangError.error(
							"Runtime Error",
							"Поле не найдено: " + member,
							node,
							source_code
						)
						return null
				else:
					LangError.error(
						"Runtime Error",
						"Присваивание полю по не-объекту",
						node,
						source_code
					)
					return null
			
			# ОБЫЧНОЕ присваивание переменной (x *= 5)
			var name = left.data["name"]
			var current_value = get_var(scope, name)
			
			var new_value = null
			match op:
				"+=": new_value = current_value + right
				"-=": new_value = current_value - right
				"*=": new_value = current_value * right
				"/=": 
					if typeof(right) == TYPE_FLOAT and right == 0:
						LangError.error("Runtime Error", "Деление на ноль", node, source_code)
						return null
					new_value = current_value / right
				"%=": 
					if typeof(right) == TYPE_FLOAT and right == 0:
						LangError.error("Runtime Error", "Деление на ноль в операции %", node, source_code)
						return null
					new_value = fmod(current_value, right)
			
			set_var(scope, name, new_value)
			return new_value
	
		# IncDec (++, --)
		"IncDec":
			var name = node.data["target"].data["name"]
			var op = node.data["op"]
			var current_value = get_var(scope, name)
			
			var new_value = null
			match op:
				"++": new_value = current_value + 1
				"--": new_value = current_value - 1
			
			set_var(scope, name, new_value)
		
		"Function":
			functions[node.data["name"]] = node
		
		"Call":
			return eval_call(node, scope)
		
		"If":
			var cond = eval_expr(node.data["condition"], scope)
			
			if typeof(cond) != TYPE_BOOL:
				LangError.error(
					"Type Error",
					"if ожидает bool",
					node,
					source_code
				)
			
			if cond:
				var res = exec_block(node.data["body"], scope)
				
				if res is ReturnValue:
					return res
				
				if res is BreakValue:
					return res
					
				if res is ContinueValue:
					return res
				
				if res is JumpValue:
					return res
			
			elif node.data.has("else") and node.data["else"] != null:
				
				var else_part = node.data["else"]
				
				# else if
				if else_part is ASTNode and else_part.type == "If":
					var res = exec(else_part, scope)
					
					if res is ReturnValue:
						return res
					if res is BreakValue:
						return res
					if res is ContinueValue:
						return res
					if res is JumpValue:
						return res
				
				# else
				else:
					var res = exec_block(else_part, scope)
					if res is ReturnValue:
						return res
					if res is BreakValue:
						return res
					if res is ContinueValue:
						return res
					if res is JumpValue:
						return res
		
		"Switch":
			var switch_value = eval_expr(node.data["expression"], scope)
			var cases = node.data["cases"]
			var default_case = node.data["default"]
			
			# 1. Собираем все блоки в порядке: case1, case2, ..., default
			var all_blocks = []
			for c in cases:
				all_blocks.append(c)
			if default_case != null:
				all_blocks.append(default_case)
			
			# 2. Ищем точку входа и выполняем с fall-through
			var start_executing = false
			
			for block in all_blocks:
				# Если ещё не начали выполнять — проверяем совпадение
				if not start_executing:
					if block.data["is_default"] or check_case_match(block, switch_value, scope):
						start_executing = true  # 🔥 Нашли точку входа!
					else:
						continue  # Пропускаем этот блок
				
				# Выполняем блок (потому что start_executing = true)
				for stmt in block.data["body"]:
					var res = exec(stmt, scope)
					
					# Обработка сигналов
					if res is ReturnValue:
						return res
					if res is BreakValue:
						return null  # 🔥 Выход из switch
					if res is JumpValue:
						return res
					if res is ContinueValue:
						LangError.error("Runtime Error", "continue в switch недопустим", node, source_code)
				
				# После выполнения блока — продолжаем к следующему (fall-through)
				# (ничего не делаем, цикл for сам перейдёт к следующему блоку)
			
			return null
		
		"Return":
			var value = eval_expr(node.data["value"], scope)
			return ReturnValue.new(value)
		
		"Break":
			return BreakValue.new()
		
		"Continue":
			return ContinueValue.new()
		
		# 🔥 FOR LOOP
		"ForLoop":
		# Создаём НОВЫЙ скоуп для цикла
			var loop_scope = {"__parent__": scope}
			
			# 1. Инициализация (один раз, в локальном скоупе)
			if node.data["init"] != null:
				exec(node.data["init"], loop_scope)
			
			# 2. Цикл
			while true:
				# Проверка условия (в локальном скоупе)
				if node.data["condition"] != null:
					var cond = eval_expr(node.data["condition"], loop_scope)
					if typeof(cond) != TYPE_BOOL:
						LangError.error("Type Error", "for ожидает булевое условие", node, source_code)
					if not cond:
						break
				
				# Выполнение тела (в локальном скоупе)
				var res = exec_block(node.data["body"], loop_scope)
				
				# ПРОВЕРКА СИГНАЛОВ
				if res is ReturnValue:
					return res
				
				if res is BreakValue:
					break
				
				if res is ContinueValue:
					# При continue выполняем update и переходим к следующей итерации
					if node.data["update"] != null:
						exec(node.data["update"], loop_scope)
					continue
				
				# 3. Обновление (в локальном скоупе)
				if node.data["update"] != null:
					exec(node.data["update"], loop_scope)
		
		
		"While":
			var whl = true
			while whl:
				var cond = eval_expr(node.data["condition"], scope)
				if typeof(cond) != TYPE_BOOL:
					LangError.error("Type Error", "while ожидает булевое выражение", node, source_code)
				if not cond:
					whl=false
					break
				var res = exec_block(node.data["body"], scope)
				if res is BreakValue:
					break
				if res is ReturnValue:
					return res
				if res is ContinueValue:
					continue  # Переход к следующей итерации
		
		
		"RepeatLoop":
			# 1. Вычисляем количество повторений
			var count_val = eval_expr(node.data["count"], scope)
			
			# Проверка типа
			if typeof(count_val) != TYPE_FLOAT:
				LangError.error("Type Error", "repeat ожидает число", node, source_code)
				return
			
			var iterations = int(count_val)
			
			# Защита от отрицательных значений
			if iterations < 0:
				LangError.error("Runtime Error", "repeat: отрицательное количество итераций", node, source_code)
				return
			
			# 2. Создаём локальный скоуп для цикла (как в for)
			var loop_scope = {"__parent__": scope}
			
			# 3. Выполняем тело цикла
			for i in range(iterations):
				var res = exec_block(node.data["body"], loop_scope)
				
				# Обработка сигналов
				if res is ReturnValue:
					return res
				
				if res is BreakValue:
					break  # Выход из repeat
				
				if res is ContinueValue:
					continue  # Переход к следующей итерации
				
				if res is JumpValue:
					return res  # Прыжок выходит из repeat
		
		
		"EnumDecl":
			var enum_name = node.data["name"]
			var values = node.data["values"]
			# Сохраняем enum как словарь {NAME: value}
			enums[enum_name] = values
		
		"Point":
			# Метки не выполняют ничего, они просто маркеры
			return null

		"Jump":
			var label = node.data["label"]
			return JumpValue.new(label)  # Сигнал для прыжка
		
		"ClassDecl":
			var _class_name = node.data["name"]
			
			# Сохраняем класс в словаре (не в глобальном AST!)
			classes[_class_name] = {
				"name": _class_name,
				"extends": node.data.get("extends"),
				"fields": node.data.get("fields", []),
				"methods": node.data.get("methods", []),
				"constructor": node.data.get("constructor"),
				"destructor": node.data.get("destructor")
			}
			# Не возвращаем узел — класс зарегистрирован, но не выполняется как код
			return null
		
		_:
			# выражение
			return eval_expr(node, scope)


# =========================
# BLOCK
# =========================
func exec_block(nodes: Array, parent_scope: Dictionary):
	#var local = parent_scope.duplicate()
	var local = {
		"__parent__": parent_scope
	}
	
	for n in nodes:
		var res = exec(n, local)
		
		if res is ReturnValue:
			return res
		
		if res is BreakValue:
			return res
			
		if res is ContinueValue:
			return res
		
		if res is JumpValue:
			return res  # Передаём сигнал прыжка выше
	
	return null


# =========================
# ВЫРАЖЕНИЯ
# =========================
func eval_expr(node: ASTNode, scope: Dictionary):
	if node == null:
		return null
	match node.type:
		
		"Number":
			var num_str = node.data["value"]
			# Проверяем есть ли десятичная точка или экспонента
			if "." in num_str or "e" in num_str.to_lower():
				return float(num_str)  # Возвращаем как float
			else:
				return float(num_str)  # Храним как float, но помечаем типом "int"
		
		"String":
			return node.data["value"]
		
		"Bool":
			return node.data["value"] == "true"
		
		"Identifier":
			return get_var(scope, node.data["name"])
		
		"Binary":
			return eval_binary(node, scope)
		
		"Unary":
			return eval_unary(node, scope)
		
		"Assign":
			var name = node.data["left"].data["name"]
			var value = eval_expr(node.data["right"], scope)
			set_var(scope, name, value)
			return value
		
		"Call":
			return eval_call(node, scope)
		
		# ЛИТЕРАЛ МАССИВА: [1, 2, 3]
		"ArrayLiteral":
			var arr = []
			for elem in node.data["elements"]:
				arr.append(eval_expr(elem, scope))
			return arr
		
		# ДОСТУП ПО ИНДЕКСУ: arr[0]
		"ArrayAccess":
			var array = eval_expr(node.data["array"], scope)
			var index = eval_expr(node.data["index"], scope)
			
			# Проверка: это массив?
			if typeof(array) != TYPE_ARRAY:
				LangError.error("Runtime Error", "Ожидается массив", node, source_code)
				return null
			
			# Проверка: индекс — число?
			if typeof(index) != TYPE_FLOAT:
				LangError.error("Runtime Error", "Индекс должен быть числом", node, source_code)
				return null
			
			var idx = int(index)
			
			# Отрицательные индексы (опционально)
			if idx < 0:
				idx = array.size() + idx
			
			# Границы массива
			if idx < 0 or idx >= array.size():
				LangError.error("Runtime Error", "Индекс вне границ: " + str(idx), node, source_code)
				return null
			
			return array[idx]
		
		"NewInstance":
			var _class_name = node.data["class_name"]
			var args = []
			for a in node.data["args"]:
				args.append(eval_expr(a, scope))
			
			# Создаём экземпляр класса
			var instance = create_instance(_class_name, args, scope)
			return instance
		
		"FieldAccess":
			var obj = eval_expr(node.data["object"], scope)
			var field = node.data["field"]
			
			# Проверяем что это экземпляр класса
			if typeof(obj) == TYPE_DICTIONARY and obj.get("__is_instance__", false):
				if obj["__fields__"].has(field):
					return obj["__fields__"][field]["value"]
				else:
					LangError.error(
						"Runtime Error",
						"Поле не найдено: " + field,
						node,
						source_code
					)
					return null
			else:
				LangError.error(
					"Runtime Error",
					"Доступ к полю по не-объекту",
					node,
					source_code
				)
				return null

		"MethodCall":
			var obj = eval_expr(node.data["object"], scope)
			var method = node.data["method"]
			var args = []
			for a in node.data["args"]:
				args.append(eval_expr(a, scope))
			
			# Проверяем что это экземпляр класса
			if typeof(obj) == TYPE_DICTIONARY and obj.get("__is_instance__", false):
				var _class_name = obj["__class__"]
				var class_def = classes.get(_class_name)
				
				if class_def == null:
					LangError.error(
						"Runtime Error",
						"Класс не найден: " + _class_name,
						node,
						source_code
					)
					return null
				
				# Ищем метод
				var method_def = null
				for m in class_def.get("methods", []):
					if m["name"] == method:
						method_def = m
						break
				
				if method_def == null:
					LangError.error(
						"Runtime Error",
						"Метод не найден: " + method,
						node,
						source_code
					)
					return null
				
				# Создаём скоуп с this
				var local = {"__parent__": scope, "this": obj}
				
				# Передаём аргументы
				for i in range(min(method_def["params"].size(), args.size())):
					local[method_def["params"][i]] = {
						"type": method_def["param_types"][i] if i < method_def["param_types"].size() else null,
						"value": args[i]
					}
				
				# Выполняем метод
				var res = exec_block(method_def["body"], local)
				
				if res is ReturnValue:
					return res.value
				return null
			else:
				LangError.error(
					"Runtime Error",
					"Вызов метода по не-объекту",
					node,
					source_code
				)
				return null
		
		# УНИВЕРСАЛЬНЫЙ ДОСТУП: enum.value или obj.field
		"MemberAccess":
			var member = node.data["member"]
			
			# 1. ПРОВЕРКА: это enum? (object — это Identifier с именем enum)
			if node.data["object"].type == "Identifier":
				var ident_name = node.data["object"].data["name"]
				if enums.has(ident_name):
					# Это enum доступ: Mode.Pause
					if enums[ident_name].has(member):
						return enums[ident_name][member]
					else:
						LangError.error(
							"Runtime Error",
							"Значение enum не найдено: " + ident_name + "." + member,
							node,
							source_code
						)
						return null
			
			# 2. Если не enum — вычисляем object как обычное выражение
			var obj = eval_expr(node.data["object"], scope)
			
			# 3. ПРОВЕРКА: это экземпляр класса?
			if typeof(obj) == TYPE_DICTIONARY and obj.get("__is_instance__", false):
				if obj["__fields__"].has(member):
					return obj["__fields__"][member]["value"]
				else:
					LangError.error(
						"Runtime Error",
						"Поле не найдено: " + member,
						node,
						source_code
					)
					return null
			
			# 4. Не найдено
			LangError.error(
				"Runtime Error",
				"Неверный доступ к члену: " + member,
				node,
				source_code
			)
			return null


		# УНИВЕРСАЛЬНЫЙ ВЫЗОВ: arr.method() или obj.method() или enum.method()
		"MemberCall":
			var member = node.data["member"]
			var args = []
			for a in node.data["args"]:
				args.append(eval_expr(a, scope))
			
			# Вычисляем объект (может быть массив, enum или класс)
			var obj = eval_expr(node.data["object"], scope)
			
			# =========================
			# 1. МАССИВЫ: Встроенные методы
			# =========================
			if typeof(obj) == TYPE_ARRAY:
				match member:
					"size":
						return float(obj.size())
					
					"add":
						if args.size() < 1:
							LangError.error("Runtime Error", member + "() требует 1 аргумент", node, source_code)
							return null
						obj.append(args[0])
						return null
					
					"remove":
						if args.size() < 1:
							LangError.error("Runtime Error", member + "() требует индекс", node, source_code)
							return null
						var idx = int(args[0])
						# Поддержка отрицательных индексов
						if idx < 0: idx = obj.size() + idx
						if idx >= 0 and idx < obj.size():
							obj.remove_at(idx)
						return null
					
					"pop_back":
						if obj.size() > 0:
							return obj.pop_back()
						return null
					
					"has":
						if args.size() < 1: return false
						return obj.has(args[0])
					
					"find":
						if args.size() < 1: return -1.0
						var idx = obj.find(args[0])
						return int(idx)
					
					"clear":
						obj.clear()
						return null
					
					"copy":
						return obj.duplicate()
					
					_:
						LangError.error(
							"Runtime Error",
							"Метод массива не найден: " + member,
							node,
							source_code
						)
						return null
			
			# =========================
			# 2. ENUM: Методы запрещены
			# =========================
			if node.data["object"].type == "Identifier":
				var ident_name = node.data["object"].data["name"]
				if enums.has(ident_name):
					LangError.error(
						"Runtime Error",
						"Нельзя вызвать метод у enum",
						node,
						source_code
					)
					return null
			
			# =========================
			# 3. КЛАССЫ:
			# =========================
			# сюда можно вставить методы для вызова методов классов
			if typeof(obj) == TYPE_DICTIONARY and obj.get("__is_instance__", false):
				var _class_name = obj["__class__"]
				var class_def = classes.get(_class_name)
				
				if class_def == null:
					LangError.error("Runtime Error", "Класс не найден: " + _class_name, node, source_code)
					return null
				
				var method_def = null
				for m in class_def.get("methods", []):
					if m["name"] == member:
						method_def = m
						break
				
				if method_def == null:
					LangError.error("Runtime Error", "Метод не найден: " + member, node, source_code)
					return null
				
				var local = {"__parent__": scope, "this": obj}
				for i in range(min(method_def["params"].size(), args.size())):
					local[method_def["params"][i]] = {
						"type": method_def["param_types"][i] if i < method_def["param_types"].size() else null,
						"value": args[i]
					}
				
				var res = exec_block(method_def["body"], local)
				
				if res is ReturnValue:
					return res.value
				return null
			else:
				LangError.error(
					"Runtime Error",
					"Вызов метода по не-объекту и не-массиву",
					node,
					source_code
				)
				return null
		
	return null


# =========================
# БИНАРНЫЕ ОПЕРАЦИИ
# =========================
func eval_binary(node: ASTNode, scope: Dictionary):
	var left = eval_expr(node.data["left"], scope)
	var op = node.data["op"]
	
	match op:
		# =========================
		# ЛОГИЧЕСКИЕ (ленивые)
		# =========================
		"&&", "and":
			if typeof(left) != TYPE_BOOL:
				LangError.error("Type Error", "&& требует bool", node, source_code)
				return false
			if not left: 
				return false  # Правую часть НЕ вычисляем
			var right = eval_expr(node.data["right"], scope)  # 🔥 Только здесь!
			return left and right

		"||", "or":
			if typeof(left) != TYPE_BOOL:
				LangError.error("Type Error", "|| требует bool", node, source_code)
				return false
			if left: 
				return true  # Правую часть НЕ вычисляем
			var right = eval_expr(node.data["right"], scope)  # 🔥 Только здесь!
			return left or right
		
		# =========================
		# СРАВНЕНИЯ
		# =========================
		"==":
			var right = eval_expr(node.data["right"], scope)
			return left == right
		"!=":
			var right = eval_expr(node.data["right"], scope)
			return left != right
		">=":
			var right = eval_expr(node.data["right"], scope)
			return left >= right
		"<=":
			var right = eval_expr(node.data["right"], scope)
			return left <= right
		">":
			var right = eval_expr(node.data["right"], scope)
			return left > right
		"<":
			var right = eval_expr(node.data["right"], scope)
			return left < right
		
		# =========================
		# АРИФМЕТИКА
		# =========================
		"+":
			var right = eval_expr(node.data["right"], scope)
			if typeof(left) == TYPE_STRING or typeof(right) == TYPE_STRING:
				if typeof(left) != TYPE_STRING or typeof(right) != TYPE_STRING:
					LangError.error("Type Error", "Нельзя смешивать string и не-string", node, source_code)
					return null
				return left + right
			
			if typeof(left) != TYPE_FLOAT or typeof(right) != TYPE_FLOAT:
				push_error("Type error: cannot add " + str(left) + " and " + str(right))
				return null
			return left + right
		
		"-":
			var right = eval_expr(node.data["right"], scope)
			if typeof(left) != TYPE_FLOAT or typeof(right) != TYPE_FLOAT:
				push_error("Type error: invalid '-'")
				return null
			return left - right
		
		"*":
			var right = eval_expr(node.data["right"], scope)
			return left * right
		
		"/":
			var right = eval_expr(node.data["right"], scope)
			if typeof(right) == TYPE_FLOAT and right == 0:
				LangError.error("Runtime Error", "Деление на ноль в операции", node, source_code)
				return 0
			return left / right
		"%":
			var right = eval_expr(node.data["right"], scope)
			if typeof(right) == TYPE_FLOAT and right == 0:
				LangError.error("Runtime Error", "Деление на ноль в операции %", node, source_code)
				return 0
			return fmod(left, right)  # Используем fmod() для float!
	
	push_error("Unknown operator: " + op)
	return null


# =========================
# ВЫЗОВ ФУНКЦИИ
# =========================
func eval_call(node: ASTNode, scope: Dictionary):
	var name: String = node.data.get("name", "")
	if name == "":
		LangError.error("Runtime Error", "Call node без имени", node, source_code)
		return null

	var args = []
	
	for a in node.data["args"]:
		args.append(eval_expr(a, scope))
	
	# --- Тип значения ---
	if name == "type":
		if args.size() < 1:
			LangError.error("Runtime Error", "type() требует 1 аргумент", node, source_code)
			return null
		return type_to_string(args[0])
	
	# --- Преобразование типов ---
	if name == "str":
		return str(args[0]) if args.size() > 0 else ""
	
	# Преобразование к bool (truthy/falsy)
	if name == "to_bool":
		if args.size() < 1:
			LangError.error("Runtime Error", "to_bool() требует 1 аргумент", node, source_code)
			return false
		
		var val = args[0]
		
		# Правила конвертации:
		if val == null:
			return false
		if typeof(val) == TYPE_FLOAT:
			return val != 0.0  # 0.0 > false, остальное > true
		if typeof(val) == TYPE_STRING:
			return val != ""  # "" > false, остальное > true
		if typeof(val) == TYPE_BOOL:
			return val  # уже bool
		if typeof(val) == TYPE_ARRAY:
			return val.size() > 0  # пустой массив > false
		if typeof(val) == TYPE_DICTIONARY:
			return val.size() > 0  # пустой словарь > false
		
		return true  # Всё остальное > true
	
	# --- Диапазон (для циклов, пока не реализовано правильно) ---
	if name == "range":
		var result = []
		if args.size() == 1:
			for i in range(int(args[0])):
				result.append(float(i))
		elif args.size() == 2:
			for i in range(int(args[0]), int(args[1])):
				result.append(float(i))
		elif args.size() == 3:
			for i in range(int(args[0]), int(args[1]), int(args[2])):
				result.append(float(i))
		return result
	
	if native_functions.has(name):
		var callback = native_functions[name] as Callable
		return callback.callv(args)  # Вызываем GDScript функцию
	
	# встроенный print
	if name == "print":
		if args.size() < 2:
			print(args)
			return null
		else:
			push_error("Неверное количество аргументов в функции '"+name+"'")
	
	# пользовательская функция
	if not functions.has(name):
		push_error("Function not found: " + name)
		return null
	
	var _func = functions[name]
	
	# создаем новый scope
	var local = {"__parent__": scope}
	
	var params = _func.data["params"]
	var param_types = _func.data.get("param_types", [])  # 🔥 Получаем типы параметров
	
	# ПРОВЕРКА: соответствие количества аргументов
	if args.size() != params.size():
		LangError.error(
			"Type Error",
			"Неверное количество аргументов: ожидалось " + str(params.size()) + ", получено " + str(args.size()),
			node,
			source_code
		)
		return null
	
	for i in range(min(params.size(), args.size())):
		var param_name = params[i]
		var arg_value = args[i]
		
		# ПРОВЕРКА ТИПА АРГУМЕНТА (если тип указан)
		var param_type = null
		if param_types.size() > i:
			param_type = param_types[i]
		
		if param_type != null and param_type != "var":
			if not check_type(param_type, arg_value):
				LangError.error(
					"Type Error",
					"Аргумент " + str(i + 1) + ": нельзя передать " + type_to_string(arg_value) + " в параметр типа " + param_type,
					node,
					source_code
				)
				return null
		
		local[param_name] = {
			"type": param_type,
			"value": arg_value
		}
	
	var res = exec_block(_func.data["body"], local)

	if res is ReturnValue:
		var return_type = _func.data.get("return_type")
		var return_value = res.value
		
		# ПРОВЕРКА 1: void функция не должна возвращать значение
		if return_type == "void":
			if return_value != null:
				LangError.error(
					"Type Error",
					"void функция не может возвращать значение",
					node,
					source_code
				)
				return null
			return null  # void функция ничего не возвращает
			
		# ПРОВЕРКА 2: var функция принимает любой тип возврата (как auto)
		elif return_type == "var":
			return return_value  # Возвращаем как есть, без проверки типа
		
		# ПРОВЕРКА 3: не-void функция должна возвращать правильный тип
		elif return_type != null:
			if not check_type(return_type, return_value):
				LangError.error(
					"Type Error",
					"Нельзя вернуть " + type_to_string(return_value) + " из функции с типом " + return_type,
					node,
					source_code
				)
				return null
		
		# Возвращаем значение
		return return_value

	# ПРОВЕРКА 4: не-void функция должна что-то вернуть!
	elif _func.data.get("return_type") != null and _func.data.get("return_type") != "void":
		LangError.error(
			"Type Error",
			"Функция с типом " + _func.data.get("return_type") + " должна возвращать значение",
			node,
			source_code
		)
		return null

	return null


func eval_unary(node: ASTNode, scope: Dictionary):
	var value = eval_expr(node.data["value"], scope)
	var op = node.data["op"]
	
	match op:
		"!":
			if typeof(value) != TYPE_BOOL:
				LangError.error(
					"Type Error",
					"! работает только с bool",
					node,
					source_code
				)
			return !value
		
		"-":
			if typeof(value) != TYPE_FLOAT:
				LangError.error(
					"Type Error",
					"- работает только с int",
					node,
					source_code
				)
			return -value
	
	return null


# =========================
# ПЕРЕМЕННЫЕ
# =========================
func get_var(scope: Dictionary, name: String):
	# Сначала проверяем константы (глобальные)
	if constants.has(name):
		return constants[name]["value"]
	
	# Проверка this (для методов класса)
	if name == "this" and scope.has("this"):
		return scope["this"]
	
	var cur = scope
	while cur != null:
		if cur.has(name):
			var v = cur[name]
			if typeof(v) == TYPE_DICTIONARY:
				# Проверка: это экземпляр класса?
				if v.get("__is_instance__", false):
					return v  # Возвращаем экземпляр как есть!
				# Обычная обёртка переменной {type: ..., value: ...}
				return v["value"]
			else:
				return v   # старый формат
		cur = cur.get("__parent__", null)
	
	LangError.error(
		"Runtime Error",
		"Переменная не найдена: " + name,
		null,
		source_code
	)
	return null


func set_var(scope: Dictionary, name: String, value):
	# ПРОВЕРКА: нельзя менять константу!
	if constants.has(name):
		LangError.error(
			"Runtime Error",
			"Нельзя изменить константу: " + name,
			null,
			source_code
		)
		return
		
	var cur = scope
	while cur != null:
		if cur.has(name):
			cur[name]["value"] = value
			return
		cur = cur.get("__parent__", null)

# =========================
# УДАЛЕНИЕ ПЕРЕМЕННОЙ
# =========================
func delete_var(scope: Dictionary, name: String, node: ASTNode) -> bool:
	var cur = scope
	
	# Ищем в цепочке скоупов
	while cur != null:
		if cur.has(name):
			cur.erase(name)  # Удаляем переменную
			return true
		cur = cur.get("__parent__", null)
	
	# Переменная не найдена
	LangError.error(
		"Runtime Error",
		"Переменная не найдена для удаления: " + name,
		node,
		source_code
	)
	return false


# =========================
# RETURN КОНТЕЙНЕР
# =========================
class ReturnValue:
	var value
	
	func _init(v):
		value = v

class BreakValue:
	pass

class ContinueValue:
	pass

class JumpValue:
	var label
	func _init(l): label = l

class FallThroughValue:
	# Сигнал: продолжить выполнение следующего кейса (нет break)
	pass


# =========================
# HELPER: Проверка совпадения case
# =========================
func check_case_match(case_node: ASTNode, switch_value: Variant, scope: Dictionary) -> bool:
	for val_expr in case_node.data["values"]:
		var case_value = eval_expr(val_expr, scope)
		if case_value == switch_value:
			return true
	return false


func type_to_string(value) -> String:
	if value == null:
		return "null"
	
	match typeof(value):
		TYPE_INT:
			return "int"
		
		TYPE_FLOAT:
			# ПРОВЕРКА: это целое число или дробное?
			if value == floor(value):
				return "int"  # 15.0, 3.0 - "int"
			else:
				return "float" # 3.14, 2.5 - "float"
		TYPE_STRING:
			return "string"
		TYPE_BOOL:
			return "bool"
		TYPE_ARRAY:
			return "array"
		TYPE_DICTIONARY:
			if value.get("__is_instance__", false):
				return value.get("__class__", "object")  #Имя класса
			return "dictionary"
		_:
			return "unknown"


func check_type(expected: String, value) -> bool:
	# 1. null тип — принимает всё (для var без типа)
	if expected == null or expected == "":
		return true
	
	# 2. null значение — допустимо для любого типа (кроме void)
	if value == null:
		return expected != "void"
	
	# 3. ВСТРОЕННЫЕ ТИПЫ — ПРОВЕРЯЕМ ПЕРВЫМИ! (приоритет над классами)
	match expected:
		"int":
			if typeof(value) == TYPE_INT:
				return true
			if typeof(value) == TYPE_FLOAT:
				return value == floor(value)  # 5.0 — OK, 5.5 — нет
			return false
		"float":
			return typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT
		"string":
			return typeof(value) == TYPE_STRING
		"bool":
			return typeof(value) == TYPE_BOOL
		"void":
			return value == null
		"var":
			return true  # Любой тип допустим!
		"array":
			return typeof(value) == TYPE_ARRAY
	
	# 4. Enum
	if enums.has(expected):
		if typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT:
			for enum_val in enums[expected].values():
				if enum_val == value:
					return true
		return false
	
	#  5. Классы (в конце, чтобы не перебивать встроенные типы)
	if classes.has(expected):
		# null уже проверен выше
		if typeof(value) == TYPE_DICTIONARY and value.get("__is_instance__", false):
			return value.get("__class__") == expected
		# НЕ класс — ошибка!
		return false
	
	# 6. Неизвестный тип — ошибка
	LangError.error(
		"Runtime Error",
		"Неизвестный тип: " + expected,
		null,
		source_code
	)
	return false


func get_var_full(scope: Dictionary, name: String):
	var cur = scope
	
	while cur != null:
		if cur.has(name):
			return cur[name]  # возвращаем ВСЮ структуру {type, value}
		
		cur = cur.get("__parent__", null)
	
	LangError.error(
		"Runtime Error",
		"Переменная не найдена: " + name,
		null,
		source_code
	)
	return null


# =========================
# КЛАССЫ: Создание экземпляра
# =========================
func create_instance(_class_name: String, args: Array, scope: Dictionary) -> Dictionary:
	# Проверяем что класс существует
	if not classes.has(_class_name):
		LangError.error(
			"Runtime Error",
			"Класс не найден: " + _class_name,
			null,
			source_code
		)
		return {}
	
	var class_def = classes[_class_name]
	
	# Создаём экземпляр
	var instance = {
		"__class__": _class_name,
		"__is_instance__": true,
		"__fields__": {}
	}
	
	# Инициализируем поля
	for field in class_def.get("fields", []):
		var value = field.get("value")
		if value != null:
			value = eval_expr(value, scope)
		else:
			value = get_default_value(field.get("type"), null)
		
		instance["__fields__"][field["name"]] = {
			"type": field.get("type"),
			"value": value
		}
	
	# Вызываем конструктор
	var constructor = class_def.get("constructor")
	if constructor != null:
		# Проверка аргументов
		if args.size() != constructor["params"].size():
			LangError.error(
				"Type Error",
				"Конструктор ожидает " + str(constructor["params"].size()) + " аргументов, получено " + str(args.size()),
				null,
				source_code
			)
			return instance
		
		# Создаём локальный скоуп для конструктора
		var local = {"__parent__": scope, "this": instance}
		
		for i in range(args.size()):
			local[constructor["params"][i]] = {
				"type": constructor["param_types"][i] if i < constructor["param_types"].size() else null,
				"value": args[i]
			}
		
		# Выполняем тело конструктора
		exec_block(constructor["body"], local)
	return instance


# =========================
# HELPER: Дефолтные значения
# =========================
func get_default_value(var_type: String, node: ASTNode):
	match var_type:
		"int":
			return 0.0
		"float":
			return 0.0
		"bool":
			return false
		"string":
			return ""
		"var":
			return 0.0  # Безопасный дефолт для var без типа
		_:
			if enums.has(var_type):
				return 0.0  # Дефолт для enum — первое значение (0)
			
			# Проверка на классы
			if classes.has(var_type):
				return null  # Классы без значения = null
				
			# Неизвестный тип — возвращаем null, check_type обработает
			LangError.error(
				"Type Error",
				"Неизвестный тип для объявления без значения: " + var_type,
				node,
				source_code
			)
			return null


# =========================
# GODOT ИНТЕГРАЦИЯ: Вызов функций и доступ к переменным
# =========================
func existsFunc(func_name: String):
	return functions.has(func_name)

# ВЫЗВАТЬ ФУНКЦИЮ ПО ИМЕНИ (из Godot)
func callFunc(func_name: String, args: Array):
	# Проверка: функция существует?
	if not functions.has(func_name):
		push_error("Функция не найдена: " + func_name)
		return null
	
	var _func = functions[func_name]
	
	# Создаём локальный скоуп с доступом к глобальным
	var local = {"__parent__": globals}
	
	# Передаём аргументы
	var params = _func.data["params"]
	for i in range(min(params.size(), args.size())):
		local[params[i]] = {
			"type": null,  # Типы параметров можно добавить позже
			"value": args[i]
		}
	# Выполняем тело функции
	var res = exec_block(_func.data["body"], local)
	# Обработка возврата
	if res is ReturnValue:
		return res.value
	return null


# ПОЛУЧИТЬ ЗНАЧЕНИЕ ГЛОБАЛЬНОЙ ПЕРЕМЕННОЙ (из Godot)
func getGlobalVar(name: String):
	# Сначала проверяем константы
	if constants.has(name):
		return constants[name]["value"]
	
	# Затем глобальные переменные
	if globals.has(name):
		var v = globals[name]
		if typeof(v) == TYPE_DICTIONARY and v.has("value"):
			return v["value"]
		return v
	
	# Не найдено
	push_error("Глобальная переменная не найдена: " + name)
	return null


# УСТАНОВИТЬ ЗНАЧЕНИЕ ГЛОБАЛЬНОЙ ПЕРЕМЕННОЙ (из Godot)
func setGlobalVar(name: String, value):
	# Проверка: нельзя менять константу
	if constants.has(name):
		LangError.error(
			"Runtime Error",
			"Нельзя изменить константу: " + name,
			null,
			source_code
		)
		return false
	
	# Ищем переменную в глобальном скоупе
	if globals.has(name):
		globals[name]["value"] = value
		return true
	
	# Не найдено — создаём новую (опционально)
	# globals[name] = {"type": null, "value": value}
	# return true
	push_error("Глобальная переменная не найдена: " + name)
	return false

# =========================
# РЕГИСТРАЦИЯ NATIVE ФУНКЦИЙ (GDScript)
# =========================

# ЗАРЕГИСТРИРОВАТЬ ФУНКЦИЮ ИЗ GDSCRIPT
func registerNativeFunc(name: String, callback: Callable):
	native_functions[name] = callback


# УДАЛИТЬ ФУНКЦИЮ
func unregisterNativeFunc(name: String):
	if native_functions.has(name):
		native_functions.erase(name)



# =========================
# ОТЛАДКА: Получение всей информации
# =========================

# ПОЛУЧИТЬ ВСЕ ПЕРЕМЕННЫЕ
func getDebugVariables() -> Array:
	var result = []
	
	# Глобальные переменные
	for name in globals:
		var data = globals[name]
		result.append({
			"name": name,
			"type": data.get("type", "unknown"),
			"value": data.get("value", null),
			"is_const": false,
			"scope": "global",
			"array_type": data.get("array_type", null),
			"array_size": data.get("value", []).size() if typeof(data.get("value")) == TYPE_ARRAY else null
		})
	
	# Константы
	for name in constants:
		var data = constants[name]
		result.append({
			"name": name,
			"type": data.get("type", "unknown"),
			"value": data.get("value", null),
			"is_const": true,
			"scope": "constant",
			"array_type": data.get("array_type", null),
			"array_size": data.get("value", []).size() if typeof(data.get("value")) == TYPE_ARRAY else null
		})
	
	return result


# ПОЛУЧИТЬ ВСЕ ФУНКЦИИ
func getDebugFunctions() -> Array:
	var result = []
	
	# Пользовательские функции
	for name in functions:
		var _func = functions[name]
		var params = []
		var param_types = _func.data.get("param_types", [])
		var param_names = _func.data.get("params", [])
		
		for i in range(param_names.size()):
			params.append({
				"name": param_names[i],
				"type": param_types[i] if i < param_types.size() else "var"
			})
		
		result.append({
			"name": name,
			"return_type": _func.data.get("return_type", "var"),
			"params": params,
			"param_count": param_names.size(),
			"is_native": false,
			"line": _func.line
		})
	
	# Native функции (GDScript)
	for name in native_functions:
		result.append({
			"name": name,
			"return_type": "var",
			"params": [],
			"param_count": 0,
			"is_native": true,
			"line": null
		})
	
	return result


# ПОЛУЧИТЬ ВСЕ ENUMS
func getDebugEnums() -> Array:
	var result = []
	
	for name in enums:
		result.append({
			"name": name,
			"values": enums[name]
		})
	
	return result


# ПОЛУЧИТЬ СТАТИСТИКУ
func getDebugStats() -> Dictionary:
	return {
		"variables_count": globals.size(),
		"constants_count": constants.size(),
		"functions_count": functions.size(),
		"native_functions_count": native_functions.size(),
		"enums_count": enums.size(),
		"arrays_count": _countArrays(globals),
	}


# ПОЛУЧИТЬ КОНКРЕТНУЮ ПЕРЕМЕННУЮ
func getDebugVariable(name: String) -> Dictionary:
	if globals.has(name):
		var data = globals[name]
		return {
			"name": name,
			"type": data.get("type", "unknown"),
			"value": data.get("value", null),
			"is_const": false,
			"scope": "global",
			"array_type": data.get("array_type", null),
			"array_size": data.get("value", []).size() if typeof(data.get("value")) == TYPE_ARRAY else null
		}
	
	if constants.has(name):
		var data = constants[name]
		return {
			"name": name,
			"type": data.get("type", "unknown"),
			"value": data.get("value", null),
			"is_const": true,
			"scope": "constant",
			"array_type": data.get("array_type", null),
			"array_size": data.get("value", []).size() if typeof(data.get("value")) == TYPE_ARRAY else null
		}
	
	return {"error": "Variable not found: " + name}


# ПОЛУЧИТЬ КОНКРЕТНУЮ ФУНКЦИЮ
func getDebugFunction(name: String) -> Dictionary:
	if functions.has(name):
		var _func = functions[name]
		return {
			"name": name,
			"return_type": _func.data.get("return_type", "var"),
			"params": _func.data.get("params", []),
			"param_types": _func.data.get("param_types", []),
			"is_native": false,
			"line": _func.line
		}
	
	if native_functions.has(name):
		return {
			"name": name,
			"return_type": "var",
			"params": [],
			"param_types": [],
			"is_native": true,
			"line": null
		}
	
	return {"error": "Function not found: " + name}


# =========================
# ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
# =========================
func _countArrays(scope: Dictionary) -> int:
	var count = 0
	for name in scope:
		var data = scope[name]
		if typeof(data) == TYPE_DICTIONARY and typeof(data.get("value")) == TYPE_ARRAY:
			count += 1
	return count
