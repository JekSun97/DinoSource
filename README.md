# DinoSource

<p align="center">
   <img src="logo_outlined.svg" width="400" alt="DinoSource logo">
</p>

[![Godot Engine](https://img.shields.io/badge/Godot-4.x-%23478cbf?logo=godot-engine&logoColor=white)](https://godotengine.org)
[![Ko-Fi](https://img.shields.io/badge/Support-Ko--Fi-%23FF5E5B?logo=ko-fi&logoColor=white)](https://ko-fi.com/jeksun)

**DinoSource** - is a full-fledged, open-source, interpreted programming language developed for the **Godot Engine**.

This language is useful for supporting **modding in games**, implementation in gameplay where programming is required, the syntax is easily modified, which allows you to easily **create your own language syntax**, or copy other popular languages, program tools where the programming language is used as a design tool.

---

## 📋 Table of contents

- [✨ Features](#-features)
- [🚀 Quick start](#-quick-start)
- [📚 Code examples](#-code-examples)
- [🏗️ Архитектура](#️-архитектура)
- [🔌 Integration with Godot](#-integration-with-godot)
- [🤝 Participation in development](#-participation-in-development)
- [💖 Поддержать проект](#-поддержать-проект)
- [📜 Лицензия](#-лицензия)

---

## ✅ Features
 - Basic Types and Operators
 - Functions and Scope
 - Classes with Constructors/Destructors
 - Arrays and Index Access
 
### 🔤 Language

| Category | Support |
|-----------|-----------|
| **Comments** | `//` one-line, `/* */` multi-line |
| **Data types** | `int`, `float`, `bool`, `string`, `var` (dynamic), `void` |
| **Constants** | `const type NAME = value` |
| **Arrays** | One-dimensional `[1,2,3]` and multidimensional `[[1,2],[3,4]]` |
| **Operators** | `+ - * / %` (arithmetic), `&& \|\| !` (logics) |
| **Enum** | Named constants `enum Status { Idle, Running = 32, Jump = 4 }` |
| **Functions** | With return types, parameters, recursion |
| **Classes** | Fields, methods, constructors `ClassName()`, destructors `~ClassName()` |
| **Conditions** | `if/else`, `switch/case/default` |
| **Cycles** | `for`, `while`, `repeat(n)`, `jump/POINT` |
| **Control** | `return`, `break`, `continue`, `delete` |

### 🔧 Integration

- ✅ **GDScript → DinoSource**: Registering native functions and variables to call **GDScript** inside **DinoSource**
- ✅ **DinoSource → GDScript**: Calling functions and accessing **DinoSource** data within **GDScript**
- ✅ **Cross-platform**: Works everywhere Godot Engine works (Windows, Linux, macOS, Web, Mobile)

---

## 🚀 Quick start

### 1. Clone the repository
```bash
git clone https://github.com/JekSun97/DinoSource.git
cd DinoSource
```

### 2. Open in Godot
- Launch **Godot 4.x**
- Open the `IDE.tscn` scene

### 3. Write your first script
```DinoSource
// 🦖 Hello DinoSource!
print("Hello World!");

int x = 10;
float y = 3.14;
string msg = "DinoSource is working!";

print(msg + " x=" + str(x) + ", y=" + str(y));
```

### 4. Запусти! 🎮
- Click **Run** in the interface
- See the console output

---

## 📚 Code examples

### 🔁 Cycles and conditions
```DinoSource
for (int i = 0; i < 5; i++) {
    if (i % 2 == 0) {
        print("Even: " + str(i));
    } else {
        print("Odd: " + str(i));
    }
}
```

### 🏗️ Classes with a constructor and destructor
```DinoSource
class Player {
    string name;
    int health = 100;
    
    // Constructor
    void Player(string n) {
        this.name = n;
        print("Player " + this.name + " created!");
    }
    
    // Destructor
    void ~Player() {
        print("Player " + this.name + " deleted");
    }
    
    void takeDamage(int dmg) {
        this.health = this.health - dmg;
        if (this.health <= 0) {
            print(this.name + " died!");
        }
    }
}

// Usage
Player hero = new Player("Artyom");
hero.takeDamage(30);
delete hero;  // The destructor will be called!
```
 
### 📦 Arrays and functions
```DinoSource
var array = [10, 20, "Hi!", false];

string check(var _arr) {
	string _text = "\n";
    for (int i = 0; i < 4; i++) {
        _text = _text + "arr[" + str(i) + "] = " + str(_arr[i]) + "\n";
    }
    return _text;
}

print("arr: " + check(array));
```

---

## 🔌 Integration with Godot

### Registering a native function (GDScript → DinoSource)
```GDScript
func _ready():
    var interpreter = DSInterpreter.new()
    
    # Register the "godot_log" function to be called from DinoSource
    interpreter.registerNativeFunc("godot_log", _godot_log)

func _godot_log(args: Array):
    if args.size() > 0:
        print("[DinoSource] " + str(args[0]))
    return null
```

```DinoSource
// In the DinoSource code:
godot_log("Greetings from DinoSource!");  // Calls a GDScript function
```

### Calling the DinoSource script from GDScript
```GDScript
# Запуск кода
var ast = parser.parse(lexer.LexerRun("int nmb = 16; print('Hello'); int DinoFunc(int a, int b) {return a+b;}"))
interpreter.run(ast)

# Getting a variable
var nmb = interpreter.getGlobalVar("nmb")

# Function call
interpreter.callFunc("DinoFunc", [4, 1])
```

---

## 🤝 Participation in development

Any contributions are welcome! 🙌

### 🐛 Found a bug?
1. Check it out [Issues](https://github.com/JekSun97/DinoSource/issues)
2. If not, create a new one with:
   - 📋 Steps to reproduce
   - 💻 Godot version
   - 🧪 Minimal code example

> 💬 **Have an idea?** Open [Issue](https://github.com/JekSun97/DinoSource/issues) or [Discussion](https://github.com/JekSun97/DinoSource/discussions)!

---

## 💖 Support the project

Developing DinoSource is a hobby project, and your support is greatly appreciated! 🙏

[![Ko-Fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/jeksun)