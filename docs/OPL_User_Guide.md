---
title: "OPL — Optimised Programming Language"
subtitle: "Official User Guide & Reference Manual"
author: "OPL Development Team"
date: "2026"
titlepage: true
titlepage-color: "0D0D1A"
titlepage-text-color: "00E5FF"
titlepage-rule-color: "8B5CF6"
toc: true
toc-own-page: true
numbersections: true
colorlinks: true
linkcolor: "Blue"
urlcolor: "Blue"
monofont: "Courier New"
fontsize: 11pt
geometry: "margin=1in"
header-includes:
  - \usepackage{fancyhdr}
  - \pagestyle{fancy}
  - \fancyhead[L]{OPL — Optimised Programming Language}
  - \fancyhead[R]{User Guide}
  - \fancyfoot[C]{\thepage}
---

# Introduction

**OPL** (Optimised Programming Language) is a high-performance, systems-oriented programming language designed for maximum hardware efficiency. OPL compiles directly to native assembly (ARM64 and x86_64), giving developers fine-grained control over the machine while offering a clean, modern syntax.

OPL is designed for:

- **Systems programming** — operating systems, drivers, embedded systems.
- **High-performance computing** — data processing, simulations, scientific code.
- **GPU computing** — native Metal (macOS) and CUDA-ready GPU kernel dispatch.
- **Concurrent applications** — native OS thread management with zero overhead.

> **Note:** OPL is currently in active bootstrapping. The compiler is self-hosting (written in OPL), with the initial bootstrap written in V. Expect rapid evolution.

---

# Installation

## Prerequisites

Before installing OPL, ensure you have the following:

| Dependency | Minimum Version | Purpose |
|---|---|---|
| **V compiler** | 0.4+ | Builds the OPL compiler itself |
| **Clang** | 13+ | Links assembled object files |
| **Git** | Any | OPM package management |
| **macOS** | 12+ (Monterey) | ARM64 target |
| **Linux** | Any modern | x86_64 target |

## Building from Source

```bash
# 1. Clone the repository
git clone https://github.com/PythagourusTheyrom/optimised-programming-language-OPL
cd optimised-programming-language-OPL

# 2. Build the compiler with V
v .

# 3. Verify the build
./OPL
# Expected output:
# OPL Compiler (Built in V)
# Usage: opl <command> [file]
```

The resulting `OPL` binary is your compiler. You can move it to a directory on your `$PATH`:

```bash
mv OPL /usr/local/bin/opl
```

---

# The OPL Compiler CLI

The OPL compiler is invoked from the command line.

## Commands Overview

```
opl <command> [arguments] [flags]
```

| Command | Description |
|---|---|
| `build <file.opl>` | Compiles an OPL source file to a native executable |
| `init` | Initialises an OPL module in the current directory |
| `get <github-repo>` | Downloads a package via OPM |

## Building a File

```bash
opl build main.opl
```

This produces a native executable called `main`.

## Compiler Flags

| Flag | Description |
|---|---|
| `--backend=asm` | Use the native ASM backend (default) |
| `--backend=c` | Use the C transpiler backend |
| `--target=arm64-macos` | Target Apple Silicon macOS |
| `--target=x86_64-linux` | Target 64-bit Linux |
| `--target=x86_64-windows` | Target 64-bit Windows |

**Examples:**

```bash
# Default build (auto-detects OS and architecture)
opl build main.opl

# Explicitly target ARM64 macOS
opl build main.opl --target=arm64-macos

# Use the C backend (useful for debugging)
opl build main.opl --backend=c
```

## OPM: Package Manager

```bash
# Initialise a new module
./opl init

# Download a package from GitHub
./opl get myusername/mypackage
# Packages are installed to ./opl_modules/
```

---

# Language Fundamentals

## Hello, World!

```opl
fn main() {
    println("Hello, OPL!");
}
```

Save this as `hello.opl`, then:

```bash
opl build hello.opl
./hello
# Output: Hello, OPL!
```

## Comments

OPL uses C-style single-line comments:

```opl
// This is a comment
let x = 10  // Inline comment
```

> **Note:** Multi-line `/* */` block comments are not yet supported.

## Variables

Variables are declared using the `let` keyword. OPL uses **strong type inference** — the type is determined from the assigned value.

```opl
let count = 0           // int  (integer)
let price = 19.99       // float (64-bit double)
let name = "Alice"      // string
let active = true       // bool
```

**Reassignment** uses the `=` operator (no `let`):

```opl
let score = 0
score = score + 10
println(score)  // 10

```

## Types

| OPL Type | Description | Example |
|---|---|---|
| `int` | 64-bit signed integer | `let x = 42` |
| `float` | 64-bit double | `let pi = 3.14` |
| `string` | Null-terminated string | `let s = "hello"` |
| `bool` | Boolean value | `let ok = true` |
| `*Type` | Pointer to Type | `let p = *Node` |

---

# Data Structures: Structs

Structs define custom compound data types.

## Declaring a Struct

```opl
struct Point {
    x int,
    y int
}
```

Field declarations use `name type` pairs, separated by commas.

## Instantiating a Struct

```opl
let origin = Point { x: 0, y: 0 }
let target = Point { x: 100, y: 200 }
```

## Accessing Fields

```opl
println(origin.x)    // 0
println(target.y)    // 200

// Write to a field
origin.x = 50
println(origin.x)    // 50
```

## Structs with Pointers

Structs can contain pointers for building linked data structures:

```opl
struct Node {
    value int,
    next  *Node
}
```

---

# Functions

## Defining Functions

```opl
fn add(a int, b int) {
    return a + b;
}

fn greet(name string) {
    println("Hello,", name);
}
```

## Calling Functions

```opl
let result = add(3, 4)
println(result)     // 7

greet("OPL")        // Hello, OPL
```

## Method Receivers

OPL supports methods on structs using V-style receivers:

```opl
struct Circle {
    radius float
}

fn (c Circle) area() {
    return 3.14159 * c.radius * c.radius;
}

fn (c Circle) describe() {
    println("Circle with radius:", c.radius);
}
```

**Calling methods:**

```opl
let circle = Circle { radius: 5.0 }
circle.describe()       // Circle with radius: 5.0
let a = circle.area()
println(a)
```

## Pointer Receivers

For methods that need to mutate the struct:

```opl
fn (c *Circle) scale(factor float) {
    c.radius = c.radius * factor;
}
```

---

# Control Flow

## If / Else

```opl
let score = 85

if score >= 90 {
    println("Grade: A")
} else if score >= 80 {
    println("Grade: B")
} else {
    println("Grade: C or below")
}
```

## While Loops

```opl
let i = 0
while i < 5 {
    println(i)
    i = i + 1
}
// Prints: 0 1 2 3 4
```

## For Loops

OPL uses a `from...to` syntax for range-based iteration:

```opl
for i from 0 to 5 {
    println(i)
}
// Prints: 0 1 2 3 4 5 (inclusive)
```

**Real-world example — summing a range:**

```opl
let sum = 0
for i from 1 to 100 {
    sum = sum + i
}
println(sum)  // 5050
```

## Comparison Operators

| Operator | Meaning |
|---|---|
| `==` | Equal |
| `!=` | Not equal |
| `<` | Less than |
| `>` | Greater than |
| `<=` | Less than or equal |
| `>=` | Greater than or equal |

## Logical Operators (Prefix)

| Operator | Meaning | Example |
|---|---|---|
| `!` | Logical NOT | `!active` |
| `-` | Arithmetic negation | `-x` |

---

# Arrays

## Creating Arrays

```opl
let numbers = [1, 2, 3, 4, 5]
let names   = ["Alice", "Bob", "Charlie"]
```

## Accessing Elements

```opl
let first = numbers[0]   // 1
let last  = numbers[4]   // 5
println(first)
```

## Modifying Elements

```opl
numbers[2] = 99
println(numbers[2])  // 99
```

## Getting the Length

```opl
let count = len(numbers)
println(count)  // 5
```

## Arrays of Structs

```opl
struct Token {
    kind int,
    lit  string
}

let t1 = Token { kind: 1, lit: "hello" }
let t2 = Token { kind: 2, lit: "world" }
let tokens = [t1, t2]

println(tokens[0].lit)  // hello
```

---

# Standard Library

## I/O Functions

### `println(...)`

Prints values to standard output followed by a newline.

```opl
println("Hello")           // Hello
println(42)                // 42
println("Value:", 3.14)    // Value: 3.14
```

### `input()`

Reads a line of text from standard input. Returns a `string`.

```opl
fn main() {
    println("Enter your name:")
    let name = input()
    println("Welcome,", name)
}
```

> **Warning:** The `input()` buffer is currently fixed at 64 bytes. Do not enter strings longer than 63 characters.

## Memory Management

### `malloc(size int)`

Allocates `size` bytes on the heap. Returns a pointer.

```opl
let buffer = malloc(256)
if buffer != 0 {
    println("Memory allocated successfully")
}
```

### Memory Safety Note

OPL currently has **no garbage collector** and no `free()` equivalent. Heap allocations will persist for the program's lifetime. Manual memory management is the developer's responsibility.

## Utility Functions

### `len(obj)`

Returns the length of an array (as element count) or a string (as byte count).

```opl
let arr = [10, 20, 30]
println(len(arr))   // 3

let msg = "hello"
println(len(msg))   // 5
```

### `exit(code int)`

Terminates the program immediately with the given exit code.

```opl
if error_occurred {
    println("Fatal error!")
    exit(1)
}
```

## Graphics (Experimental)

### `draw_pixel(x int, y int, color int)`

Intended to draw a pixel at `(x, y)` with the specified colour. Currently outputs a debug trace to the console.

```opl
draw_pixel(100, 200, 0xFF0000)
// Output: [DRAW 100, 200, 16711680]
```

---

# Concurrency

## Spawning Threads

Use `spawn` to run a function in a new native OS thread:

```opl
fn worker(id int) {
    println("Worker", id, "started")
    // ... do work ...
    println("Worker", id, "done")
}

fn main() {
    spawn worker(1)
    spawn worker(2)
    spawn worker(3)
    println("All workers launched")
}
```

Each `spawn` call creates a real OS thread using `pthread_create` on macOS/Linux.

## Thread Safety

OPL does not enforce memory safety rules for shared state. When multiple threads access the same data, use operating system primitives for synchronisation. This can be done through C interoperability (calling `pthread_mutex_lock`, etc.).

---

# GPU Programming

## The `gpu` Keyword

Prefix a function with `gpu` to define it as a GPU kernel:

```opl
gpu fn compute() {
    let x = 0
    // Kernel logic here
}
```

## Dispatching a GPU Kernel

Simply call the function as normal. OPL will dispatch it to the GPU:

```opl
fn main() {
    compute()  // Dispatched to GPU via Metal (macOS)
}
```

## How It Works

1. OPL transpiles the `gpu fn` body to a Metal shader string (macOS).
2. The shader is embedded in the binary's data section.
3. At runtime, `_opl_dispatch_metal` is called to compile and execute the shader.

> **Limitation:** GPU kernels currently support only a limited subset of OPL:
> - Integer/float arithmetic
> - Variable declarations (`let`)
> - Return statements
>
> Loops, conditionals, and string operations inside GPU kernels are not yet supported.

---

# Complete Example Programs

## Example 1: Fibonacci Sequence

```opl
fn fib(n int) {
    if n <= 1 {
        return n;
    }
    return fib(n - 1) + fib(n - 2);
}

fn main() {
    for i from 0 to 10 {
        println(fib(i));
    }
}
```

## Example 2: Struct-Based Counter

```opl
struct Counter {
    value int,
    step  int
}

fn (c Counter) increment() {
    c.value = c.value + c.step;
}

fn (c Counter) get() {
    return c.value;
}

fn main() {
    let cnt = Counter { value: 0, step: 5 }
    for i from 0 to 4 {
        cnt.increment()
        println("Count:", cnt.get())
    }
}
```

## Example 3: Multithreaded Workers

```opl
fn heavy_task(task_id int) {
    let result = 0
    for i from 0 to 1000 {
        result = result + i
    }
    println("Task", task_id, "result:", result)
}

fn main() {
    spawn heavy_task(1)
    spawn heavy_task(2)
    spawn heavy_task(3)
    println("Main thread continues...")
}
```

## Example 4: Reading User Input

```opl
fn main() {
    println("Enter a number:")
    let raw = input()
    println("You entered:", raw)
}
```

---

# OPM: Package Manager

## Initialising a Module

In your project directory, run:

```bash
opl init
```

This creates an `opl.mod` file:

```
module main
```

## Adding a Dependency

```bash
opl get username/repository
```

The package is cloned to `./opl_modules/username/repository`.

> **Security Note:** The `opl get` command currently passes arguments directly to `git clone` via the shell. Only install packages from trusted sources.

---

# Compiler Architecture (Reference)

Understanding the compiler pipeline is useful for debugging and extending OPL.

## Pipeline Overview

```
Source (.opl)
    |
    v
[Lexer]  ──>  Token Stream
    |
    v
[Parser]  ──>  AST (Abstract Syntax Tree)
    |
    v
[Code Generator]
    ├── ARM64 macOS backend  ──>  .s (ASM)  ──>  clang  ──>  executable
    ├── x86_64 Linux backend ──>  .s (ASM)  ──>  clang  ──>  executable
    └── C backend            ──>  .c        ──>  gcc    ──>  executable
```

## Key Source Files

| File | Role |
|---|---|
| `opl.v` | Compiler entry point, CLI, and driver |
| `lexer/lexer.v` | Tokeniser — reads source and emits tokens |
| `lexer/token.v` | Token kind enumeration |
| `parser/parser.v` | Recursive descent parser — builds the AST |
| `ast/ast.v` | AST node type definitions |
| `codegen/backend_arm64_mac.v` | ARM64 macOS code generator |

## AST Node Types

| Node | Category | Description |
|---|---|---|
| `IntegerLit` | Expression | Integer literal (e.g., `42`) |
| `FloatLit` | Expression | Float literal (e.g., `3.14`) |
| `StringLit` | Expression | String literal |
| `BoolLit` | Expression | Boolean (`true`/`false`) |
| `Ident` | Expression | Variable or function name |
| `InfixExpr` | Expression | Binary operation (e.g., `a + b`) |
| `PrefixExpr` | Expression | Unary operation (e.g., `!x`) |
| `CallExpr` | Expression | Function call |
| `MethodCall` | Expression | Method call (e.g., `obj.method()`) |
| `PropertyAccess` | Expression | Field access (e.g., `obj.field`) |
| `ArrayLiteral` | Expression | Array literal `[1, 2, 3]` |
| `IndexExpr` | Expression | Array subscript `arr[i]` |
| `StructLiteral` | Expression | Struct instantiation |
| `LetStmt` | Statement | Variable declaration |
| `ReturnStmt` | Statement | Function return |
| `IfStmt` | Statement | If/else conditional |
| `WhileStmt` | Statement | While loop |
| `ForStmt` | Statement | For range loop |
| `SpawnStmt` | Statement | Thread spawn |

---

# Known Limitations & Current Status

OPL is under active development. The following are known limitations to be aware of:

| Severity | Issue |
|---|---|
| **Critical** | `printf` arguments must be in registers (x1–x7), not the stack |
| **Critical** | Struct property reads are partially unimplemented in some backends |
| **High** | No `break` or `continue` in loops |
| **High** | No garbage collector — heap allocations are permanent |
| **High** | Input buffer is limited to 64 bytes |
| **Medium** | No multi-line block comments |
| **Medium** | No namespaces — name collisions possible with system symbols |
| **Medium** | Pointer arithmetic syntax is limited |
| **Low** | No scientific notation in numeric literals (`1e10` unsupported) |
| **Low** | For-loops have no step parameter |

For the full list of 100+ tracked issues, see the `bugs.br` file in the project root.

---

# Quick Reference Card

## Variable Declaration
```opl
let name = value
```

## Function
```opl
fn name(param type, ...) {
    return value;
}
```

## Method
```opl
fn (receiver ReceiverType) method_name(param type) {
    // body
}
```

## Struct
```opl
struct Name {
    field type,
    field type
}
```

## Control Flow
```opl
if condition { }
if condition { } else { }
while condition { }
for var from start to end { }
```

## Concurrency
```opl
spawn function_name(args)
```

## GPU Kernel
```opl
gpu fn kernel_name() {
    // kernel body
}
kernel_name()  // Dispatch
```

## Built-in Functions
```opl
println(values...)
input()        -> string
malloc(size)   -> ptr
len(arr/str)   -> int
exit(code)
draw_pixel(x, y, color)
```

---

*OPL User Guide — Version 1.0 — Optimised Programming Language Development Team*
