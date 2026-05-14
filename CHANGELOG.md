# Changelog

All notable changes to OPL are documented here.

---

## [0.1.0] — 2026-05-14 — *First Stable Self-Hosting Release*

### ✅ Compiler — ARM64/macOS Backend

- **ARM64 ABI Compliance**: Full Apple Silicon stack frame (`stp x29, x30, [sp, #-256]!` / `mov x29, sp`) matching the macOS calling convention.
- **Struct Field Namespacing**: Field offsets are now keyed as `StructName_fieldName` (e.g. `Engine_status`), eliminating cross-struct offset collisions.
- **Correct Property Assignment**: Fixed the Pratt parser infix loop (`cur_tok` vs `peek_tok`) so that `=` is correctly emitted as an assignment node in the AST and generates a `str` instruction in the assembly.
- **Printf Register Safety**: Arguments to `printf` are now pushed to the stack before the format string is loaded into `x0`, preventing register clobbering.
- **Function Epilogue Consistency**: All return paths (normal + early `return`) use the same `mov sp, x29 / ldp x29, x30, [sp], #256` sequence.
- **Float Support**: Floating-point literals use the `d0` register path (`fadd`, `fsub`, `fmul`, `fdiv`, `fcmp`).
- **Heap Allocation**: `malloc` callable from OPL via the ARM64 ABI.
- **Inclusive For-Loops**: `for i from 0 to N` iterates N+1 times as specified.

### ✅ Parser

- **Struct Field Parser Fix**: Fields no longer absorb their own type annotations as phantom fields — `power int` now produces one field (`power`), not two (`power`, `int`).
- **Pratt Parser Loop**: Fixed the precedence check to use `cur_tok` instead of `peek_tok`, restoring correct operator precedence for `=`, `==`, `<`, `>`, etc.
- **Type Inference Expansion**: `LetStmt` now correctly propagates `string` type for variables initialized from method calls and property accesses.

### ✅ Validation

- `test_all.opl` passes fully with exit code 0:
  - Struct initialization and property read
  - Method dispatch and property write (`e.status = "RUNNING"`)
  - Inclusive for-loops (0 to 5)
  - Float comparisons
  - Heap allocation (`malloc`)
