class_name DSParser

var tokens:Array = []
var pos:int = 0
var source_code = ""

func _init(_tokens: Array):
	tokens = _tokens


func current() -> Token:
	if pos < tokens.size():
		return tokens[pos]
	return null

func next() -> Token:
	pos += 1
	return current()

func _match(type, value=null) -> bool:
	var t = current()
	if t == null:
		return false
	if t.type != type:
		return false
	if value != null and t.value != value:
		return false
	pos += 1
	return true


func expect(type, value=null) -> Token:
	var t = current()
	
	if t == null:
		LangError.error(
			"Parser Error",
			"Expected " + str(type) + ", but the end of the file has been reached",
			ASTNode.new("Error", {}, 0),
            ""
		)
		# Возвращаем фейковый токен чтобы не крашиться
		return Token.new(DSLexer.TokenType.IDENT, "ERROR", 0)
	
	#  Проверка типа
	if t.type != type:
		LangError.error(
			"Parser Error",
			"Expected " + str(type) + ", received " + str(t.type),
			ASTNode.new("Error", {}, t.line),
            ""
		)
		return Token.new(DSLexer.TokenType.IDENT, "ERROR", t.line)
	
	#  Проверка значения (если указано)
	if value != null and t.value != value:
		LangError.error(
			"Parser Error",
			"Expected " + str(value) + ", received " + str(t.value),
			ASTNode.new("Error", {}, t.line),
            ""
		)
		return Token.new(DSLexer.TokenType.IDENT, "ERROR", t.line)
	
	pos += 1
	return t

# =========================
# ГЛАВНЫЙ ПАРСЕР
# =========================
func parse() -> Array:
	var nodes = []
	
	while current() != null:
		var before = pos
		var node = parse_statement()
		
		if pos == before:
			push_error("The parser is stuck: " + str(current()))
			next()
			continue
		
		if node != null:
			nodes.append(node)
	
	return nodes


# =========================
# STATEMENTS
# =========================
func parse_statement() -> ASTNode:
	var t = current()
	if t == null:
		return null
	
	if t.type == DSLexer.TokenType.KEYWORD:
		# --- func стиль ---
		if t.value == "func":
			return parse_func()

		# --- void func ---
		if t.value == "void":
			if lookahead_is("func"):
				return parse_func()
			elif is_function_declaration():
				return parse_func_typed()
			else:
				return parse_var_decl()

		# --- int/string ---
		if t.value in ["int","float", "string", "bool"]:
			if is_function_declaration():
				return parse_func_typed()
			else:
				return parse_var_decl()
		
		if t.value == "var":
			# Заглядываем вперёд: это функция или переменная?
			# var name( - функция
			# var name = - переменная
			# var name; - переменная без значения
			if pos + 1 < tokens.size() and tokens[pos + 1].type == DSLexer.TokenType.IDENT:
				if pos + 2 < tokens.size() and tokens[pos + 2].type == DSLexer.TokenType.LPAREN:
					# Это функция: var func(int x) { ... }
					return  parse_func_typed()
			# Это переменная: var x = 5; или var x;
			return parse_var_decl() # var работает как dynamic-тип
		
		if t.value == "const":
			return parse_const()
		
		if t.value == "switch":
			return parse_switch()
		
		if t.value == "if":
			return parse_if()
		
		if t.value == "return":
			return parse_return()
		
		if t.value == "while":
			return parse_while()
		
		if t.value == "for":
			return parse_for()
		
		if t.value == "repeat":
			return parse_repeat()

		if t.value == "break":
			return parse_break()
		
		if t.value == "continue":
			return parse_continue()
			
		if t.value == "enum":
			return parse_enum()
		
		if t.value == "class":
			return parse_class()
			
		if t.value == "delete":
			return parse_delete()
		
		if t.value == "JMP":
			return parse_jump()

		if t.value == "POINT":
			return parse_point()
	
	if t.type == DSLexer.TokenType.IDENT:
		# ПРОВЕРКА 1: Это функция с возвратом enum/класса? (en fn() { })
		if is_function_declaration():
			return parse_func_typed()
		
		# ПРОВЕРКА 2: Это переменная типа enum/класса? (en x = ... или en x;)
		if pos + 1 < tokens.size():
			var next_token = tokens[pos + 1]
			if next_token.type == DSLexer.TokenType.IDENT:
				# Дополнительно: проверяем что это НЕ вызов функции (en x();)
				if pos + 2 >= tokens.size() or tokens[pos + 2].type != DSLexer.TokenType.LPAREN:
					# Это объявление переменной с enum/класс типом: Mode _mod = ...
					return parse_var_decl()
		
		# ПРОВЕРКА 3: Это вызов функции? (myFunc();)
		if pos + 1 < tokens.size() and tokens[pos + 1].type == DSLexer.TokenType.LPAREN:
			return parse_expression()
	
	#  Обычное выражение (вызов функции, присваивание, и т.д.)
	var expr = parse_expression()

	#  Проверка на ; в конце statement
	if current() == null or current().type != DSLexer.TokenType.SEMICOLON:
		LangError.error(
			"Parser Error",
			"Пропущен символ ';' в конце statement",
			ASTNode.new("Error", {}, current().line if current() else 0),
	        ""
		)
		# Восстановление: пропускаем до ; или конца
		while current() != null and current().type != DSLexer.TokenType.SEMICOLON:
			next()

	_match(DSLexer.TokenType.SEMICOLON)
	return expr


# =========================
# VAR DECL
# =========================
func parse_var_decl() -> ASTNode:
	var t = current()
	
	#  Читаем тип: KEYWORD или IDENT (для enum)
	var type_token:Token = null
	if current().type == DSLexer.TokenType.KEYWORD:
		type_token = expect(DSLexer.TokenType.KEYWORD)
	elif current().type == DSLexer.TokenType.IDENT:
		# Проверяем, не имя ли это enum (будет проверено позже в интерпретаторе)
		type_token = expect(DSLexer.TokenType.IDENT)
	else:
		LangError.error("Parser Error", "Ожидался тип", ASTNode.new("Error", {}, current().line), source_code)
	
	var name = expect(DSLexer.TokenType.IDENT)
	
	#  ПРОВЕРКА: есть ли присваивание?
	var value:ASTNode = null
	if current() != null and current().value == "=":
		next()
		value = parse_expression()
	
	if not _match(DSLexer.TokenType.SEMICOLON):
		LangError.error("Parser Error", "Пропущен символ ';'", ASTNode.new("Error", {}, current().line), source_code)
	
	var var_type: String = ""
	if type_token != null:
		var_type = type_token.value

	return ASTNode.new("VarDecl", {
		"name": name.value,
		"value": value,
		"var_type": var_type
	}, t.line)


# =========================
# CONST DECL
# =========================
func parse_const() -> ASTNode:
	var t = current()
	expect(DSLexer.TokenType.KEYWORD, "const")
	
	#  Читаем тип: KEYWORD (int, string, bool) или IDENT (для enum)
	var type_token:Token = null
	if current().type == DSLexer.TokenType.KEYWORD:
		type_token = expect(DSLexer.TokenType.KEYWORD)
	elif current().type == DSLexer.TokenType.IDENT:
		type_token = expect(DSLexer.TokenType.IDENT)  # Имя enum
	else:
		LangError.error("Parser Error", "Ожидался тип", ASTNode.new("Error", {}, current().line), source_code)
	
	# Ожидаем имя константы
	var name = expect(DSLexer.TokenType.IDENT)
	
	if current() == null or current().value != "=":
		LangError.error(
			"Parser Error",
			"Константа должна иметь значение: const " + name.value + " = ...",
			ASTNode.new("Error", {}, current().line),
			source_code
		)
	
	# Ожидаем знак присваивания
	expect(DSLexer.TokenType.OPERATOR, "=")
	
	# Парсим значение
	var value = parse_expression()
	
	# Ожидаем точку с запятой
	if not _match(DSLexer.TokenType.SEMICOLON):
		LangError.error(
			"Parser Error",
			"Пропущен символ ';'",
			ASTNode.new("Error", {}, current().line),
			source_code
		)
	
	return ASTNode.new("ConstDecl", {
		"name": name.value,
		"value": value,
		"const_type": type_token.value
	}, t.line)


# =========================
# RETURN
# =========================
func parse_return() -> ASTNode:
	var t:Token = current()
	
	expect(DSLexer.TokenType.KEYWORD, "return")
	
	var value:ASTNode = parse_expression()
	
	var end = current()
	if not _match(DSLexer.TokenType.SEMICOLON):
		LangError.error(
			"Parser Error",
			"Пропущен символ ';'",
			ASTNode.new("Error", {}, current().line),
			source_code
		)
	
	return ASTNode.new("Return", {
		"value": value
	}, t.line)


# =========================
# FUNC
# =========================
func parse_func() -> ASTNode:
	var t:Token = current()
	var return_type = null
	
	# если есть void или var перед func
	if current().value in ["void", "var"]:
		return_type = current().value
		next()
	
	expect(DSLexer.TokenType.KEYWORD, "func")
	
	var name = expect(DSLexer.TokenType.IDENT)
	
	expect(DSLexer.TokenType.LPAREN)
	
	var params = []
	var param_types = []
	
	while current() != null and not _match(DSLexer.TokenType.RPAREN):
		var param_type = null
		
		#  Читаем тип параметра (если есть)
		if current().type == DSLexer.TokenType.KEYWORD and current().value in ["int","float", "string", "bool", "void", "var"]:
			param_type = current().value
			next()
		elif current().type == DSLexer.TokenType.IDENT:
			# Возможно это enum тип
			param_type = current().value
			next()
		
		var param_name = expect(DSLexer.TokenType.IDENT)
		params.append(param_name.value)
		param_types.append(param_type)  #  Сохраняем тип
		
		_match(DSLexer.TokenType.COMMA)
	
	var body = parse_block()
	
	return ASTNode.new("Function", {
		"name": name.value,
		"return_type": return_type,
		"params": params,
		"param_types": param_types,
		"body": body
	}, t.line)


func parse_func_typed() -> ASTNode:
	var t:Token = current()
	
	#  Читаем return_type: KEYWORD (int, string, bool, void, var) или IDENT (enum)
	var return_type = null
	if current().type == DSLexer.TokenType.KEYWORD and current().value in ["int","float", "string", "bool", "void", "var"]:
		return_type = current().value
		next()
	elif current().type == DSLexer.TokenType.IDENT:
		# Возможно это enum тип или var
		return_type = current().value
		next()
	else:
		LangError.error(
			"Parser Error",
			"Ожидался тип функции",
			ASTNode.new("Error", {}, current().line),
			source_code
		)
	
	var name = expect(DSLexer.TokenType.IDENT)
	
	expect(DSLexer.TokenType.LPAREN)
	
	var params = []
	var param_types = []
	
	while current() != null and not _match(DSLexer.TokenType.RPAREN):
		var param_type = null
		
		#  Читаем тип параметра (если есть)
		if current().type == DSLexer.TokenType.KEYWORD and current().value in ["int", "string", "bool", "void", "var"]:
			param_type = current().value
			next()
		elif current().type == DSLexer.TokenType.IDENT:
			# Возможно это enum тип
			param_type = current().value
			next()
		
		var param_name = expect(DSLexer.TokenType.IDENT)
		params.append(param_name.value)
		param_types.append(param_type)  #  Сохраняем тип
		
		_match(DSLexer.TokenType.COMMA)
	
	var body = parse_block()
	
	return ASTNode.new("Function", {
		"name": name.value,
		"return_type": return_type,
		"params": params,
		"param_types": param_types,
		"body": body
	}, t.line)

# =========================
# IF
# =========================
func parse_if() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "if")
	expect(DSLexer.TokenType.LPAREN)
	
	var condition = parse_expression()
	
	expect(DSLexer.TokenType.RPAREN)
	
	var body = parse_block()
	
	var else_body = null
	
	#  проверяем else
	if current() != null and current().value == "else":
		next()
		
		# else if
		if current() != null and current().value == "if":
			else_body = parse_if() # рекурсия
		
		# обычный else
		else:
			else_body = parse_block()
	
	return ASTNode.new("If", {
		"condition": condition,
		"body": body,
		"else": else_body
	}, t.line)

# =========================
# BLOCK
# =========================
func parse_block() -> Array:
	var nodes = []
	
	if _match(DSLexer.TokenType.LBRACE):
		
		while current() != null and not _match(DSLexer.TokenType.RBRACE):
			
			var before = pos
			var stmt = parse_statement()
			
			if pos == before:
				push_error("Block завис: " + str(current()))
				next()
				continue
			
			if stmt != null:
				nodes.append(stmt)
		
		return nodes
	
	push_error("Ожидался блок")
	return []


# =========================
# EXPRESSIONS
# =========================
func parse_expression() -> ASTNode:
	return parse_assignment()
	
	
func parse_assignment() -> ASTNode:
	var t:Token = current()
	var left = parse_or()
	
	if current() != null and current().type == DSLexer.TokenType.OPERATOR:
		var op = current().value
		
		#  Проверяем составные операторы
		if op in ["+=", "-=", "*=", "/=", "%="]:
			next()
			var right = parse_assignment()
			
			return ASTNode.new("CompoundAssign", {
				"left": left,
				"op": op,
				"right": right
			}, t.line)
		
		#  Проверяем ++ и --
		elif op in ["++", "--"]:
			next()
			
			return ASTNode.new("IncDec", {
				"target": left,
				"op": op
			}, t.line)
		
		# Обычное присваивание
		elif op == "=":
			next()
			var right = parse_assignment()
			
			return ASTNode.new("Assign", {
				"left": left,
				"right": right
			}, t.line)
	return left


# =========================
# PRIMARY
# =========================
func parse_primary() -> ASTNode:
	var t:Token = current()
	if t == null:
		return null
	
	if t.type == DSLexer.TokenType.LPAREN:
		next() # пропускаем '('
		var expr = parse_expression()
		expect(DSLexer.TokenType.RPAREN)
		return expr
	
	if t.type == DSLexer.TokenType.NUMBER:
		next()
		return ASTNode.new("Number", {"value": t.value},t.line)
	
	if t.type == DSLexer.TokenType.STRING:
		next()
		return ASTNode.new("String", {"value": t.value},t.line)
	
	if t.type == DSLexer.TokenType.BOOL:
		next()
		return ASTNode.new("Bool", {"value": t.value},t.line)
	
	#  ЛИТЕРАЛ МАССИВА: [1, 2, 3]
	if t.type == DSLexer.TokenType.LBRACKET:
		next()  # "съедаем" открывающую скобку [ !
		
		var elements = []
		
		#  Защита: пустой массив []
		if current() != null and current().type == DSLexer.TokenType.RBRACKET:
			next()  # Съедаем ]
			return ASTNode.new("ArrayLiteral", {"elements": []}, t.line)
		
		#  Безопасный цикл
		while current() != null and current().type != DSLexer.TokenType.RBRACKET:
			var before_pos = pos  # Запоминаем позицию
			
			var elem = parse_expression()
			
			#  Защита от зависания: если парсер не сдвинулся — выходим!
			if pos == before_pos:
				push_error("Массив: не удалось распарсить элемент, токен: " + str(current()))
				break
			
			if elem != null:
				elements.append(elem)
			
			# Запятая опциональна
			if current() != null and current().type == DSLexer.TokenType.COMMA:
				next()
		
		#  Обязательно съедаем закрывающую скобку
		if current() != null and current().type == DSLexer.TokenType.RBRACKET:
			next()
		else:
			LangError.error("Parser Error", "Ожидалась ] в конце массива", ASTNode.new("Error", {}, t.line), source_code)
		
		return ASTNode.new("ArrayLiteral", {
			"elements": elements
		}, t.line)
	
	
	if t.type == DSLexer.TokenType.IDENT:
		next()
		
		# Начинаем с простого Identifier
		var result = ASTNode.new("Identifier", {"name": t.value}, t.line)
		
		#  Обрабатываем цепочки: arr[1][0] или obj.prop[index]
		while true:
			#  Доступ к массиву: [index]
			if current() != null and current().type == DSLexer.TokenType.LBRACKET:
				next()  # Пропускаем [
				var index = parse_expression()
				expect(DSLexer.TokenType.RBRACKET)
				
				# Оборачиваем текущий результат в ArrayAccess
				result = ASTNode.new("ArrayAccess", {
					"array": result,  # < Может быть Identifier или другой ArrayAccess!
					"index": index
				}, t.line)
				continue  # Проверяем, нет ли ещё [...]
			
			#  Доступ к полю/методу/enum: .prop
			if current() != null and current().value == ".":
				next()
				var member = expect(DSLexer.TokenType.IDENT)
				
				#  Проверяем если это вызов метода: obj.method()
				if current() != null and current().type == DSLexer.TokenType.LPAREN:
					next()
					var args = []
					while current() != null and not _match(DSLexer.TokenType.RPAREN):
						args.append(parse_expression())
						_match(DSLexer.TokenType.COMMA)
					
					#  Универсальный узел для вызова метода
					result = ASTNode.new("MemberCall", {
						"object": result,
						"member": member.value,
						"args": args
					}, t.line)
				else:
					#  Универсальный узел для доступа к полю/enum
					result = ASTNode.new("MemberAccess", {
						"object": result,  # ← Identifier (Status, player, и т.д.)
						"member": member.value
					}, t.line)
				
				continue
			
			#  НЕТ БОЛЬШЕ ПОСТФИКСНЫХ ОПЕРАТОРОВ — ВЫХОДИМ!
			break
		
		#  Вызов функции: только если это простой идентификатор
		if result.type == "Identifier" and current() != null and current().type == DSLexer.TokenType.LPAREN:
			return parse_call(result.data["name"])
		
		return result
	
	if t.type == DSLexer.TokenType.KEYWORD and t.value == "new":
		next()  # Съедаем new
		
		var _class_name = expect(DSLexer.TokenType.IDENT)
		
		# Аргументы конструктора
		var args = []
		if current() != null and current().type == DSLexer.TokenType.LPAREN:
			next()
			while current() != null and not _match(DSLexer.TokenType.RPAREN):
				args.append(parse_expression())
				_match(DSLexer.TokenType.COMMA)
		
		return ASTNode.new("NewInstance", {
			"class_name": _class_name.value,
			"args": args
		}, t.line)
	
	return null


# =========================
# CALL
# =========================
func parse_call(name) -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.LPAREN)
	
	var args = []
	
	while current() != null and not _match(DSLexer.TokenType.RPAREN):
		args.append(parse_expression())
		_match(DSLexer.TokenType.COMMA)
	
	return ASTNode.new("Call", {
		"name": name,
		"args": args
	},
	t.line)



func parse_or():
	var left = parse_and()

	while current() != null and current().value in ["||", "or"]:
		var op = current().value
		next()

		var right = parse_and()

		left = ASTNode.new("Binary", {
			"left": left,
			"op": op,
			"right": right
		}, left.line)
	return left


func parse_and():
	var left = parse_equality()

	while current() != null and current().value in ["&&", "and"]:
		var op = current().value
		next()

		var right = parse_equality()

		left = ASTNode.new("Binary", {
			"left": left,
			"op": op,
			"right": right
		}, left.line)
	return left



func parse_equality():
	var left = parse_comparison()

	while current() != null and current().value in ["==", "!="]:
		var op = current().value
		next()

		var right = parse_comparison()

		left = ASTNode.new("Binary", {
			"left": left,
			"op": op,
			"right": right
		}, left.line)

	return left



func parse_comparison():
	var left = parse_term()

	while current() != null and current().value in [">", "<", ">=", "<="]:
		var op = current().value
		next()

		var right = parse_term()

		left = ASTNode.new("Binary", {
			"left": left,
			"op": op,
			"right": right
		}, left.line)

	return left



func parse_term():
	var left = parse_factor()

	while current() != null and current().value in ["+", "-"]:
		var op = current().value
		next()

		var right = parse_factor()

		left = ASTNode.new("Binary", {
			"left": left,
			"op": op,
			"right": right
		}, left.line)

	return left


func parse_factor():
	var left = parse_unary()

	while current() != null and current().value in ["*", "/", "%"]:
		var op = current().value
		next()

		var right = parse_unary()

		left = ASTNode.new("Binary", {
			"left": left,
			"op": op,
			"right": right
		}, left.line)

	return left



func parse_unary():
	if current() != null and current().type == DSLexer.TokenType.OPERATOR and current().value in ["!", "-"]:
		var op = current().value
		var t = current()
		next()
		
		var right = parse_unary()
		
		return ASTNode.new("Unary", {
			"op": op,
			"value": right
		}, t.line)
	
	return parse_primary()


func parse_while() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "while")
	expect(DSLexer.TokenType.LPAREN)
	
	var condition = parse_expression()
	
	expect(DSLexer.TokenType.RPAREN)
	
	var body = parse_block()
	
	return ASTNode.new("While", {
		"condition": condition,
		"body": body
	}, t.line)


# =========================
# REPEAT LOOP
# =========================
func parse_repeat() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "repeat")
	expect(DSLexer.TokenType.LPAREN)
	
	# Выражение: сколько раз повторить (может быть число или выражение)
	var count_expr = parse_expression()
	
	expect(DSLexer.TokenType.RPAREN)
	
	# Тело цикла — блок
	var body = parse_block()
	
	return ASTNode.new("RepeatLoop", {
		"count": count_expr,
		"body": body
	}, t.line)


# =========================
# FOR LOOP
# =========================
func parse_for() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "for")
	expect(DSLexer.TokenType.LPAREN)
	
	#  1. Инициализация (может быть VarDecl или выражение)
	var init:ASTNode = null
	if current() != null and current().type != DSLexer.TokenType.SEMICOLON:
		if current().type == DSLexer.TokenType.KEYWORD and current().value in ["int", "string", "bool", "var"]:
			init = parse_var_decl()  # int i = 0;
		else:
			init = parse_expression()  # i = 0;
			_match(DSLexer.TokenType.SEMICOLON)  # Потребляем ;
	else:
		_match(DSLexer.TokenType.SEMICOLON)  # Пустая инициализация
	
	#  2. Условие
	var condition:ASTNode = null
	if current() != null and current().type != DSLexer.TokenType.SEMICOLON:
		condition = parse_expression()
	expect(DSLexer.TokenType.SEMICOLON)  # Обязательно ;
	
	#  3. Обновление
	var update = null
	if current() != null and current().type != DSLexer.TokenType.RPAREN:
		update = parse_expression()
	expect(DSLexer.TokenType.RPAREN)
	
	#  4. Тело цикла
	var body = parse_block()
	
	return ASTNode.new("ForLoop", {
		"init": init,
		"condition": condition,
		"update": update,
		"body": body
	}, t.line)


func parse_break() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "break")
	
	if not _match(DSLexer.TokenType.SEMICOLON):
		LangError.error(
			"Parser Error",
			"Пропущен ';' после break",
			ASTNode.new("Error", {}, t.line),
			source_code
		)
	
	return ASTNode.new("Break", {}, t.line)


func parse_continue() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "continue")
	
	if not _match(DSLexer.TokenType.SEMICOLON):
		LangError.error(
			"Parser Error",
			"Пропущен ';' после continue",
			ASTNode.new("Error", {}, t.line),
			source_code
		)
	
	return ASTNode.new("Continue", {}, t.line)


# =========================
# ENUM
# =========================
func parse_enum() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "enum")
	
	var name = expect(DSLexer.TokenType.IDENT)
	expect(DSLexer.TokenType.LBRACE)
	
	var values = {}
	var next_value = 0
	
	while current() != null and not _match(DSLexer.TokenType.RBRACE):
		var entry_name = expect(DSLexer.TokenType.IDENT)
		
		#  Проверка на явное значение (NAME = 5)
		if current() != null and current().value == "=":
			next()
			var num_token = expect(DSLexer.TokenType.NUMBER)
			next_value = int(num_token.value)
		
		values[entry_name.value] = next_value
		next_value += 1
		
		_match(DSLexer.TokenType.COMMA)
		_match(DSLexer.TokenType.SEMICOLON)
	
	return ASTNode.new("EnumDecl", {
		"name": name.value,
		"values": values
	}, t.line)


# =========================
# DELETE
# =========================
func parse_delete() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "delete")
	
	# Ожидаем имя переменной
	var name_token = expect(DSLexer.TokenType.IDENT)
	
	# Опциональная точка с запятой
	_match(DSLexer.TokenType.SEMICOLON)
	
	return ASTNode.new("Delete", {
		"name": name_token.value
	}, t.line)


# =========================
# JUMP (JMP)
# =========================
func parse_jump() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "JMP")
	var label = expect(DSLexer.TokenType.IDENT)
	_match(DSLexer.TokenType.SEMICOLON)
	
	return ASTNode.new("Jump", {
		"label": label.value
	}, t.line)

# =========================
# POINT (Label)
# =========================
func parse_point() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "POINT")
	var label = expect(DSLexer.TokenType.IDENT)
	_match(DSLexer.TokenType.SEMICOLON)
	
	return ASTNode.new("Point", {
		"label": label.value
	}, t.line)


# =========================
# SWITCH / CASE
# =========================
func parse_switch() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "switch")
	expect(DSLexer.TokenType.LPAREN)
	
	# Выражение для сравнения
	var expression = parse_expression()
	
	expect(DSLexer.TokenType.RPAREN)
	expect(DSLexer.TokenType.LBRACE)
	
	var cases = []
	var default_case:ASTNode = null
	
	# Парсим case/default пока не закроем блок
	while current() != null and current().type != DSLexer.TokenType.RBRACE:
		if current().value == "case":
			cases.append(parse_case())
		elif current().value == "default":
			default_case = parse_default()
		else:
			push_error("Ожидался case или default")
			next()
	
	expect(DSLexer.TokenType.RBRACE)
	
	return ASTNode.new("Switch", {
		"expression": expression,
		"cases": cases,
		"default": default_case
	}, t.line)


func parse_case() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "case")
	
	#  Парсим значения через запятую: case 1, 2, 3:
	var values = []
	while true:
		var val = parse_expression()
		values.append(val)
		
		if current() != null and current().type == DSLexer.TokenType.COMMA:
			next()  # Пропускаем запятую, читаем следующее значение
		else:
			break
	
	expect(DSLexer.TokenType.OPERATOR, ":")  # Ожидаем двоеточие
	
	# Тело кейса: выполняем инструкции пока не встретим следующий case/default/}
	var body = []
	while current() != null:
		if current().value in ["case", "default"]:
			break
		if current().type == DSLexer.TokenType.RBRACE:
			break
		
		var before = pos
		var stmt = parse_statement()
		if pos == before:
			next()
			continue
		if stmt != null:
			body.append(stmt)
	
	return ASTNode.new("CaseBlock", {
		"values": values,
		"body": body,
		"is_default": false
	}, t.line)


func parse_default() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "default")
	expect(DSLexer.TokenType.OPERATOR, ":")
	
	var body = []
	while current() != null:
		if current().value == "case":
			break
		if current().type == DSLexer.TokenType.RBRACE:
			break
		
		var before = pos
		var stmt = parse_statement()
		if pos == before:
			next()
			continue
		if stmt != null:
			body.append(stmt)
	
	return ASTNode.new("CaseBlock", {
		"values": [],
		"body": body,
		"is_default": true
	}, t.line)


# =========================
# CLASS
# =========================
func parse_class() -> ASTNode:
	var t:Token = current()
	expect(DSLexer.TokenType.KEYWORD, "class")
	
	var name = expect(DSLexer.TokenType.IDENT)
	
	#  Наследование (опционально)
	var extends_class = null
	if current() != null and current().value == "extends":
		next()
		extends_class = expect(DSLexer.TokenType.IDENT).value
	
	expect(DSLexer.TokenType.LBRACE)
	
	var fields = []
	var methods = []
	var constructor = null
	var destructor = null
	
	#  Парсим содержимое класса
	while current() != null and current().type != DSLexer.TokenType.RBRACE:
		var before_pos = pos
		
		#  Поле или метод: type name ...
		if current().type == DSLexer.TokenType.KEYWORD:
			if current().value in ["int","float", "string", "bool", "var", "void"]:
				var type_token = current().value
				next()
				
				#  ПРОВЕРКА 1: ДЕСТРУКТОР (void ~ClassName) — ДО expect(IDENT)!
				if type_token == "void" and current() != null and current().value == "~":
					next()  # Съедаем ~
					var destructor_name = expect(DSLexer.TokenType.IDENT)
					
					#  Проверка: имя должно совпадать с классом
					if destructor_name.value != name.value:
						LangError.error(
							"Parser Error",
							"Деструктор должен иметь имя класса: ~" + name.value,
							ASTNode.new("Error", {}, destructor_name.line),
							""
						)
					
					#  Парсим () — деструктор без параметров
					expect(DSLexer.TokenType.LPAREN)
					if current() != null and current().type != DSLexer.TokenType.RPAREN:
						LangError.error(
							"Parser Error",
							"Деструктор не может иметь параметры",
							ASTNode.new("Error", {}, current().line),
							""
						)
						while current() != null and current().type != DSLexer.TokenType.RPAREN:
							next()
					expect(DSLexer.TokenType.RPAREN)
					
					var body = parse_block()
					
					#  Сохраняем деструктор
					destructor = {
						"params": [],
						"param_types": [],
						"body": body
					}
					continue  #  Переходим к следующему члену класса
				
				#  ПРОВЕРКА 2: Обычное поле/метод/конструктор — теперь безопасно!
				var field_name = expect(DSLexer.TokenType.IDENT)
				
				#  Конструктор: void ClassName()
				if type_token == "void" and field_name.value == name.value:
					expect(DSLexer.TokenType.LPAREN)
					var params = []
					var param_types = []
					while current() != null and not _match(DSLexer.TokenType.RPAREN):
						var ptype = null
						if current().type == DSLexer.TokenType.KEYWORD and current().value in ["int","float", "string", "bool", "var"]:
							ptype = current().value
							next()
						elif current().type == DSLexer.TokenType.IDENT:
							ptype = current().value
							next()
						var pname = expect(DSLexer.TokenType.IDENT)
						params.append(pname.value)
						param_types.append(ptype)
						_match(DSLexer.TokenType.COMMA)
					
					var body = parse_block()
					constructor = {
						"params": params,
						"param_types": param_types,
						"body": body
					}
					continue
				
				#  Метод: type name() { }
				if current() != null and current().type == DSLexer.TokenType.LPAREN:
					expect(DSLexer.TokenType.LPAREN)
					var params = []
					var param_types = []
					while current() != null and not _match(DSLexer.TokenType.RPAREN):
						var ptype = null
						if current().type == DSLexer.TokenType.KEYWORD and current().value in ["int","float", "string", "bool", "var"]:
							ptype = current().value
							next()
						elif current().type == DSLexer.TokenType.IDENT:
							ptype = current().value
							next()
						var pname = expect(DSLexer.TokenType.IDENT)
						params.append(pname.value)
						param_types.append(ptype)
						_match(DSLexer.TokenType.COMMA)
					
					var body = parse_block()
					methods.append({
						"name": field_name.value,
						"return_type": type_token,
						"params": params,
						"param_types": param_types,
						"body": body
					})
					continue
				
				#  Поле: type name; или type name = value;
				var value:ASTNode = null
				if current() != null and current().value == "=":
					next()
					value = parse_expression()
				_match(DSLexer.TokenType.SEMICOLON)
				
				fields.append({
					"name": field_name.value,
					"type": type_token,
					"value": value
				})
				continue
		
		#  Обработка IDENT как типа (для классов и enum)
		elif current().type == DSLexer.TokenType.IDENT:
			var type_token = current().value
			next()
			var field_name = expect(DSLexer.TokenType.IDENT)
			
			#  Метод: TypeName name() { }
			if current() != null and current().type == DSLexer.TokenType.LPAREN:
				expect(DSLexer.TokenType.LPAREN)
				var params = []
				var param_types = []
				while current() != null and not _match(DSLexer.TokenType.RPAREN):
					var ptype = null
					if current().type == DSLexer.TokenType.KEYWORD and current().value in ["int","float", "string", "bool", "var"]:
						ptype = current().value
						next()
					elif current().type == DSLexer.TokenType.IDENT:
						ptype = current().value
						next()
					var pname = expect(DSLexer.TokenType.IDENT)
					params.append(pname.value)
					param_types.append(ptype)
					_match(DSLexer.TokenType.COMMA)
				
				var body = parse_block()
				methods.append({
					"name": field_name.value,
					"return_type": type_token,
					"params": params,
					"param_types": param_types,
					"body": body
				})
				continue
			
			#  Поле: TypeName name; или TypeName name = value;
			var value:ASTNode = null
			if current() != null and current().value == "=":
				next()
				value = parse_expression()
			_match(DSLexer.TokenType.SEMICOLON)
			
			fields.append({
				"name": field_name.value,
				"type": type_token,
				"value": value
			})
			continue
		
		#  Пропускаем неизвестное (защита от зависания)
		if pos == before_pos:
			next()
	
	expect(DSLexer.TokenType.RBRACE)
	
	#  Возвращаем ОДИН узел класса
	return ASTNode.new("ClassDecl", {
		"name": name.value,
		"extends": extends_class,
		"fields": fields,
		"methods": methods,
		"constructor": constructor,
		"destructor": destructor
	}, t.line)



func is_function_declaration() -> bool:
	if pos + 2 >= tokens.size():
		return false
	
	var t1 = tokens[pos + 1]
	var t2 = tokens[pos + 2]
	
	return t1.type == DSLexer.TokenType.IDENT and \
		   t2.type == DSLexer.TokenType.LPAREN



func lookahead_is(value) -> bool:
	if pos + 1 >= tokens.size():
		return false
	return tokens[pos + 1].value == value
