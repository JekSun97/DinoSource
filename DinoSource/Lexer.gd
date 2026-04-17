class_name DSLexer

var _code_tmp: String = ""
var comm_one = "//"
var comm_block_begin = "/*"
var comm_block_end = "*/"
var end_line_str = ";"
var USE_INDENT = false

enum TokenType {
	KEYWORD, #int, bool, return, if.
	IDENT, # ?
	NUMBER,
	STRING,
	BOOL,
	OPERATOR, # +,-,*...
	LPAREN, RPAREN,# ( )
	LBRACE, RBRACE, # { }
	LBRACKET, RBRACKET, # [ ]
	COMMA, # ,
	SEMICOLON,# ;
	INDENT,
	DEDENT
}

const KEYWORDS = [
	"var", "int","float", "string","bool","const", "func", "void", "enum",
	"return", "if", "else", "true", "false",
	"while","for","repeat", "break","continue",
	"JMP","POINT",
	"switch", "case", "default",
	"class", "new",
	"and","or",
	"delete"
]

func _ready() -> void:
	pass
	
func LexerRun(_code:String)->Array:
	_code_tmp = ""
	var all_tokens = []
	var _len = 0
	var nmb_string = 0
	var comm = false
	var comm_block = false
	var indent_stack = [0]
	while _len < _code.length():
		if comm==false and comm_block==false:
			_code_tmp=_code_tmp+_code[_len]
			if _code_tmp.length()>=comm_one.length():
				if _code[_len]==comm_one[comm_one.length()-1]:
					if _code_tmp.ends_with(comm_one):
						comm = true
						_code_tmp = _code_tmp.substr(0, _code_tmp.length() - comm_one.length())
			if _code_tmp.length()>=comm_block_begin.length():
				if _code[_len]==comm_block_begin[comm_block_begin.length()-1]:
					if _code_tmp.ends_with(comm_block_begin):
						comm_block = true
						_code_tmp = _code_tmp.substr(0, _code_tmp.length() - comm_block_begin.length())
		if _code[_len] == end_line_str: # ;
			var cleaned = _code_tmp.strip_edges()
			if cleaned != "":
				var tokens = TokenizeLine(cleaned, nmb_string)
				for t in tokens:
					all_tokens.append(t)
			_code_tmp=""
		if _code[_len] == "\n": # Next Line
			nmb_string+=1
			var raw_line = _code_tmp
			var cleaned = raw_line.strip_edges()
			if USE_INDENT and cleaned != "":
				var indent = 0
				# считаем табы/пробелы в начале
				for c in raw_line:
					if c == "\t":
						indent += 1
					elif c == " ":
						indent += 1
					else:
						break
				var prev_indent = indent_stack[-1]

				if indent > prev_indent:
					indent_stack.append(indent)
					all_tokens.append(make_token(TokenType.INDENT, "INDENT", nmb_string))

				elif indent < prev_indent:
					while indent < indent_stack[-1]:
						indent_stack.pop_back()
						all_tokens.append(make_token(TokenType.DEDENT, "DEDENT", nmb_string))
			if cleaned != "":
				var tokens = TokenizeLine(cleaned,nmb_string)
				for t in tokens:
					all_tokens.append(t)
			_code_tmp=""
			if comm==true: comm=false
		if comm_block:
			if _code[_len]==comm_block_end[comm_block_end.length()-1]:
				var end_comm_1 = _code.right(-_len+comm_block_end.length()-1)
				var end_comm_2 = end_comm_1.erase(comm_block_end.length(),end_comm_1.length()-comm_block_end.length())
				if end_comm_2==comm_block_end:
					comm_block=false
		_len+=1
	if USE_INDENT:
		while indent_stack.size() > 1:
			indent_stack.pop_back()
			all_tokens.append(make_token(TokenType.DEDENT, "DEDENT", nmb_string))
	return all_tokens
	
func make_token(type: DSLexer.TokenType, value: String, line: int) -> Token:
	return Token.new(type, value, line)
	
	
func TokenizeLine(line: String, line_number: int) -> Array:
	var tokens = []
	var cur = ""
	
	var i = 0
	while i < line.length():
		var ch = line[i]
		
		# --- space ---
		if ch in [" ", "\t"]:
			if cur != "":
				tokens.append(make_word_token(cur, line_number))
				cur = ""
		
		# --- brackets and special characters ---
		elif ch == "(":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.LPAREN, "(", line_number))
		
		elif ch == ")":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.RPAREN, ")", line_number))
		
		elif ch == "[":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.LBRACKET, "[", line_number))

		elif ch == "]":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.RBRACKET, "]", line_number))
		
		elif ch == "{":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.LBRACE, "{", line_number))
		
		elif ch == "}":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.RBRACE, "}", line_number))
		
		elif ch == ";":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.SEMICOLON, ";", line_number))
		
		elif ch == ",":
			flush_word(cur, tokens, line_number)
			cur = ""
			tokens.append(make_token(TokenType.COMMA, ",", line_number))
		
		# --- operators ---
		elif ch in ["=", "+", "-", "*", "/", "%", "<", ">", "!", "&", "|", ".", ":", "~"]:
			# СПЕЦИАЛЬНАЯ ОБРАБОТКА ДЛЯ ТОЧКИ (десятичная дробь или оператор?)
			if ch == ".":
				# Если точка — часть числа (13.45), добавляем её к текущему слову
				if cur != "" and cur.is_valid_float():
					# Проверяем: следующий символ — цифра?
					if i + 1 < line.length() and line[i+1] in ["0","1","2","3","4","5","6","7","8","9"]:
						cur += ch  # Добавляем точку к числу
						i += 1
						continue  # Продолжаем собирать число!
				
				# Если точка — не часть числа, обрабатываем как оператор
				flush_word(cur, tokens, line_number)
				cur = ""
				tokens.append(make_token(TokenType.OPERATOR, ch, line_number))
			
			# Остальные операторы (без специальной обработки)
			else:
				flush_word(cur, tokens, line_number)
				cur = ""
				var next = ""
				if i + 1 < line.length():
					next = line[i+1]
					
					# двойные операторы
					if ch == "+" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "+=", line_number))
						i += 1
					elif ch == "-" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "-=", line_number))
						i += 1

					elif ch == "*" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "*=", line_number))
						i += 1
					elif ch == "/" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "/=", line_number))
						i += 1
					elif ch == "%" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "%=", line_number))
						i += 1

					elif ch == "+" and next == "+":
						tokens.append(make_token(TokenType.OPERATOR, "++", line_number))
						i += 1
					elif ch == "-" and next == "-":
						tokens.append(make_token(TokenType.OPERATOR, "--", line_number))
						i += 1
					elif ch == "&" and next == "&":
						tokens.append(make_token(TokenType.OPERATOR, "&&", line_number))
						i += 1
					elif ch == "|" and next == "|":
						tokens.append(make_token(TokenType.OPERATOR, "||", line_number))
						i += 1
					elif ch == "=" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "==", line_number))
						i += 1
					elif ch == ">" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, ">=", line_number))
						i += 1
					elif ch == "<" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "<=", line_number))
						i += 1
					elif ch == "!" and next == "=":
						tokens.append(make_token(TokenType.OPERATOR, "!=", line_number))
						i += 1
					else:
						tokens.append(make_token(TokenType.OPERATOR, ch, line_number))
		
		# --- строки ---
		elif ch == '"' or ch == "'":
			flush_word(cur, tokens, line_number)
			cur = ""
			
			var quote = ch
			var str_val = ""
			i += 1  # Пропускаем открывающую кавычку
			
			while i < line.length() and line[i] != quote:
				# Поддержка экранирования: \" \n \t
				if line[i] == '\\' and i + 1 < line.length():
					i += 1
					match line[i]:
						'n': str_val += "\n"
						't': str_val += "\t"
						'r': str_val += "\r"
						'\\': str_val += "\\"
						'"': str_val += '"'
						"'": str_val += "'"
						_: str_val += line[i]
				else:
					str_val += line[i]
				i += 1
			
			# ПРОВЕРКА: нашли ли закрывающую кавычку?
			if i >= line.length() or line[i] != quote:
				LangError.error(
					"Parser Error",
					"Unclosed line: expected " + quote + " at the end",
					null,
					line  # Можно передать исходный код для лучшего сообщения
				)
				# Возвращаем пустой токен или пропускаем
				tokens.append(make_token(TokenType.STRING, str_val, line_number))
				continue
			
			i += 1  # Пропускаем закрывающую кавычку
			tokens.append(make_token(TokenType.STRING, str_val, line_number))
			continue
		
		else:
			cur += ch
		i += 1
	
	if cur != "":
		tokens.append(make_word_token(cur, line_number))
	return tokens
	


func flush_word(word: String, tokens: Array, line: int) -> void:
	if word != "":
		tokens.append(make_word_token(word, line))


func make_word_token(word: String, line: int) -> Token:
	if word == "true" or word == "false":
		return make_token(TokenType.BOOL, word, line)
	if word in KEYWORDS:
		return make_token(TokenType.KEYWORD, word, line)
	if word.is_valid_float():
		return make_token(TokenType.NUMBER, word, line)
	return make_token(TokenType.IDENT, word, line)
