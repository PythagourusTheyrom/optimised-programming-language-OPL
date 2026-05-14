# Concurrency in OPL

OPL makes multithreading simple and efficient by providing direct access to native OS threads.

## 🧵 The `spawn` Keyword
To run a function in a new thread, use the `spawn` keyword before a function call.

```opl
fn heavy_task(data string) {
    // Perform expensive operation
    println("Processed:", data)
}

fn main() {
    spawn heavy_task("Batch A")
    spawn heavy_task("Batch B")
    
    println("Tasks spawned!")
}
```

## 🛠 Native Threads
Unlike languages with green threads or coroutines, `spawn` in OPL creates a real OS thread (using `pthread_create` on macOS/Linux). This ensures that your tasks are truly parallelized across CPU cores.

## ⚠️ Safety and Synchronization
Currently, OPL does not enforce strict borrow checking or ownership rules for shared memory. Developers should use standard atomic operations or OS-provided mutexes (available through C interoperability) when accessing shared data.
