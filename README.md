# To implement
+ Check the return type of `process()` and confirm that types match
    with calculators that are plugged into the output stream.
    + Use `Core.Compiler.return_type(function, args_tuple)
        + Gives what the compiler thinks will return given 
    + See https://discourse.julialang.org/t/can-i-get-the-declared-return-type-of-a-method/43575/19

+ Tissue.resolve_process()
    + for each Method, look at the argnames symbols. For a process() to be resolved,
    there needs to be a one-to-one correspondence between the `streams` symbols, and
    the `argnames` symbols.
    Q: Does the `resolve_process()` create the Channels? If so, then they need to be
    added in the `output_channels` list of the "connected" calculators.
+ graph macros
    + Look into MacroTools.jl
+ Deal with issue: we currently check the output type of `process()` to make sure it's correct.
    + Maybe we can let julia tell us somehow without crashing at runtime.
+ When we CTRL+C, catch it and exit without showing the crap julia shows us
    + Handle that exception, and exit gracefully
+ Graph shutdown function
    + Similar to MediaPipe's `graph.CloseInputStream()`.
    + Think about how this interacts with `poll()`: e.g. `poll()` could return nothing
    when graph is shutdown and nothing is being processed anymore.
+ write() should throw exception if graph was not started
+ Should we remove init() and start()? Or at least offer a `init_and_start()`.
+ Some nice error messages and reference number (e.g. E1032), similar to what Rust does

# Known issues
+ Be clear as to whether `open()`, `process()`, `close()` live in `Base` or `Tissue`.
+ Some code needs to be run in the main thread (e.g. all UI operations in QT).
    + we need a mechanism to specify whether callbacks need to be run in UI thread
    or not.
+ If no callbacks are registered for a graph output stream, don't write to that channel

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
+ Each `CalculatorWrapper` has a `exec_time` field.
    + Update using exponential filter `exec_time = 0.9 * exec_time + 0.1 * new_time`

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