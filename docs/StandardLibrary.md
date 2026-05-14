# Optimised Programming Language Standard Library Reference

OPL provides a set of built-in functions for core system tasks. Many of these map directly to optimized C library calls.

## 🖥 I/O Functions

### `println(...)`
Prints one or more values to the standard output, followed by a newline.
- **Arguments**: Any number of `int`, `float`, `string`, or `bool` values.
- **Implementation**: Uses `printf` with automatic format detection.

### `input()`
Reads a string from the standard input.
- **Returns**: `string` (buffer allocated on the stack/heap).
- **Implementation**: Uses `scanf`.

## 🧠 Memory Management

### `malloc(size int)`
Allocates `size` bytes of memory on the heap.
- **Arguments**: `size` (int).
- **Returns**: A pointer to the allocated memory.

## 📊 Utility Functions

### `len(obj)`
Returns the length of the given object.
- **Strings**: Returns number of bytes (using `strlen`).
- **Arrays**: Returns the number of elements.

### `exit(code int)`
Terminates the program immediately with the provided exit code.

## 🎨 Graphics (Experimental)

### `draw_pixel(x int, y int, color int)`
Draws a pixel at the specified coordinates.
- **Note**: In the current ASM backend, this prints a debug message to the console. Native graphics backend is in development.
