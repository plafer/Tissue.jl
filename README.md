# To implement
+ Separate `Tissue.jl` into multiple files, and export symbols.
+ Check the return type of `process()` and confirm that types match
    with calculators that are plugged into the output stream.
    + Use `Core.Compiler.return_type(function, args_tuple)
        + Gives what the compiler thinks will return given 
    + See https://discourse.julialang.org/t/can-i-get-the-declared-return-type-of-a-method/43575/19

+ Deal with issue: we currently check the output type of `process()` to make sure it's correct.
    + Maybe we can let julia tell us somehow without crashing at runtime.
+ When we CTRL+C, catch it and exit without showing the crap julia shows us
    + Handle that exception, and exit gracefully
+ Make sure the implementation is free of data races.
    + Any data that is written by a thread and read by others should be protected
    by lock or atomic operation.

# Known issues
+ Be clear as to whether `open()`, `process()`, `close()` live in `Base` or `Tissue`.
+ Some code needs to be run in the main thread (e.g. all UI operations in QT).
    + we need a mechanism to specify whether callbacks need to be run in UI thread
    or not.
+ If no callbacks are registered for a graph output stream, don't write to that channel
+ in `wait_until_done()`, also wait for all callback tasks to be done.
+ Add closed loop control in determining the sleep period for polling the generator
    calculator.
    + Technically, we could be polling too fast and filling up the `Channel` buffers.
+ Flow limiter: the initial bootstrap takes into account the compilation time.
+ The current setup requires an output stream for a graph to be defined.
    + What if I want to consume the output all within calculators (e.g. display it and that's it)?
    + We could patch it up simply by putting a sink to any output stream which has no callback registered.
    + Or maybe we'd want to do all the work within graphs, and have no output streams?
# Performance improvements
+ Don't use structs that have fields with abstract types, see [this](https://docs.julialang.org/en/v1/manual/performance-tips/#Avoid-fields-with-abstract-type)
    + e.g. Frame
    + Solution: use `struct Frame{T <: AbstractType}` instead

# Feature request
+ Precompile all `process()` methods that will be used?
    + Caused some question marks for me on the first run of `process()`
        of a bigger `process()` implementation (face detection).
+ Reproducibility of a graph
    + Very useful for debugging, as [Guy Steele says](https://www.infoq.com/presentations/Thinking-Parallel-Programming/)
        + See ~31:00
    + Mediapipe has it too.
+ Produce error report on internal error
    + Exceptions thrown on other threads don't make the main thread crash.
        You need to `wait()` the task.
    + We should wait on all the tasks and when one of them returns exception,
        produce an error report that can be filed (well simply stack trace maybe).
+ Flow limiter: Have a `desired_rate` parameter, which we don't surpass.
+ Flow limiter: if a `process()` ran way slower all of a sudden for a couple of shots,
    maybe send a message so that the generator rate is reevaluated.
+ Some nice error messages and reference number (e.g. E1032), similar to what Rust does
+ Generator calculator and @definputstream is ugly. The generator calculator is not
    a calculator, because we don't want to collect run time stats on it, so we need
    a separate code path
    + Find a better abstraction.

# Fundamental issues to de-risk
+ Multi-threading can [break finalizers](https://docs.julialang.org/en/v1/manual/multi-threading/#Safe-use-of-Finalizers)
    + libraries that we'll use, e.g. OpenCV wrapper or CUDA.jl, will probably use
    finalizers.
    + Can we not use threads then? Or some other lock wizardry of some sort?
    + UPDATE: in State of Julia 2021, they say finalizers will be ran in a dedicated
    thread. 
        + Feature is coming.

# Crazy ideas or are they
+ Build a GUI that lets you generate the scaffolding for a given graph structure
+ Build a tracer that lets you visualize packets traveling through the graph, and a timeline similar to MediaPipe

# Decisions
+ About the immutability of packets
    + We will *encourage* users to never mutate data that comes from streams.
        + We will see how well that works, and if we need to do anything about it.
# Flow Limiter and read/writing to graph
+ Keep a moving average of time it took to run each `process()`. The max of all
    these times is the time at which you want to send your packets!
    (proof/argument to be documented)
+ Each `CalculatorWrapper` has a `exec_time` field (atomic)
    + Update using exponential filter `exec_time = 0.9 * exec_time + 0.1 * new_time`
    + At frequency X, a task computes the max of all times. Sets this as polling freq.

## Registering read callbacks & running them
+ Each output stream can have many callbacks registered
+ Provide a `run_forever()` function which blocks main thread
+ callbacks run in parallel, in any thread.
+ What if I want to stop the whole thing 
    + Should I be able to stop the graph from a `process()`?
        + Maybe...
    + The generator function should also be able to release its resources
        + e.g. the opencv videocapture.
    + Note: Exiting main thread will stop everything. Probably want to exit
        gracefully though
    + Idea: Send special packet?
        + in `run_calculators`, if I get a STOP packet, I propagate, and exit.
        + in `register_callback`, if I get a STOP packet, I exit.
        + BUT, stop can be called from any thread. So really it needs to indicate
            to the writing thread that it should send a STOP packet instead
            of calling the generating function.
        + in `run_forever`,
            + loops over all  `start_calculator` tasks, calling `wait()` on all of them.

# Generator Calculator
+ The user *must* provide *one* "generator" calculator.
# Shutting down from `stop()`
+ The `stop()` function turns sets `graph.done = false`
+ The generator task sees `done`, so sends a DONE packet through the graph. Exits.
+ `run_calculator` receives the DONE packet from `fetch_input_streams`.
    1. calls `close(calc)` on its calculator
    2. exits 
+ Each registered callback task
    1. if DONE packet, exit.
+ `run_forever`
    + waits on all tasks
        + pre-req: in `start_calculators`, add each task to a list

# On error in some `process()`...
+ `run_calculator` calls stop() returns normally.
    + a STOP packet will eventually come back.
    + simply print error for now.

# On error in an output stream callback...
+ just let the whole thing crash for now.

# Flow limiter boostrapping
Send the first packet in. After it arrived at all output streams, run the first flow limiter period evaluation pass.

1. In `start()`, don't start the flow limiter period evaluation right away. Instead, start the task that will watch all output streams, and once bootstrapped, start the current flow limiter task.
2. `register_callback()` can add a Channel to task in 1 (or inform in some way that this outputstream has a cb registered)

`register_callback` increments a counter. decrement on packet in channel. When counter reaches back to 0, wake up the task.
+ task gets an 

## Tasks
1. bootstrap task
    + waits on `cond` until all packets have arrived at output streams
    + evaluate period
    + Launch flow limiter evaluation period task
2. generator task
    + Reads packet from generator calculator
        + Handles errors
    + Writes packet to graph
    + Hangs until it's time to read again
        + `period` if bootstrapped
        + after packet reaches all outputs if bootstrapping
3. Flow limiter period evaluation
    + determine and set the new generator period