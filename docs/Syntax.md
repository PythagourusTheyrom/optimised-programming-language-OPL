# Optimised Programming Language Syntax Reference

OPL uses a clean, modern syntax influenced by V, C, and Rust.

## 📦 Variables
Variables are declared using the `let` keyword. OPL uses strong type inference.

```opl
let count = 0          // int
let price = 19.99      // float
let message = "Hello"  // string
let active = true      // bool
```

## 🏗 Data Structures
Structs define custom data types.

```opl
struct User {
    id int,
    username string,
    is_admin bool
}

// Initialization
let me = User { id: 1, username: "dev", is_admin: true }

// Field Access
println(me.username)
```

## ⚙️ Functions and Methods
Functions are defined with `fn`. Methods use V-style receivers.

```opl
// Standard Function
fn add(a int, b int) {
    return a + b
}

// Method
fn (u User) login() {
    println(u.username, "logged in")
}

me.login()
```

## 🔄 Control Flow

### If Statements
```opl
if x > 10 {
    println("Large")
} else {
    println("Small")
}
```

### While Loops
```opl
while count < 5 {
    println(count)
    count = count + 1
}
```

### For Loops
OPL uses a specific `from...to` syntax for loops.
```opl
for i from 0 to 10 {
    println(i) // Prints 0 through 10
}
```

## 🔗 Pointers
OPL supports C-style pointers for low-level memory manipulation.
```opl
struct Node {
    value int,
    next *Node
}
```
