# GPU Programming in OPL

One of OPL's most powerful features is its native integration with GPU hardware.

## ⚡️ The `gpu` Keyword
By prefixing a function with `gpu`, you tell the OPL compiler to transpile that function into a GPU kernel (Metal on macOS, CUDA on other platforms).

```opl
gpu fn compute_gradient(data [int]) {
    let id = get_global_id()
    data[id] = data[id] * 2
}
```

## 🚀 Dispatching Kernels
When you call a `gpu fn`, the OPL runtime automatically:
1.  Compiles the kernel to the native GPU shading language.
2.  Allocates memory on the GPU.
3.  Dispatches the kernel for parallel execution.

```opl
let values = [1, 2, 3, 4]
compute_gradient(values) // Runs on GPU
```

## 🔍 Under the Hood
On macOS, OPL generates Metal shaders inline. You can see the generated shaders in the assembly output (`.s` file) under the `_shader` labels.

> [!IMPORTANT]
> Currently, GPU functions are limited to a subset of OPL syntax that is compatible with shader execution environments (e.g., no string manipulation or complex recursion inside `gpu` blocks).
