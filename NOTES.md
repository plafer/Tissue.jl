# To implement
+ Check the return type of `process()` and confirm that types match
    with calculators that are plugged into the output stream.
    + Use `Core.Compiler.return_type(function, args_tuple)
        + Gives what the compiler thinks will return given 
    + See https://discourse.julialang.org/t/can-i-get-the-declared-return-type-of-a-method/43575/19

+ When we CTRL+C, catch it and exit without showing the crap julia shows us
    + Handle that InterruptException, and exit gracefully
+ Make sure the implementation is free of data races.
    + Any data that is written by a thread and read by others should be protected
    by lock or atomic operation.

# Known issues
+ There is currently no way to dynamically change the parameters of the calculator in a graph (e.g. pass as command line argument)
    + `@graph` is defined in "global scope", so the whole struct is defined by the time the first line of code executes.
    + Solution 1: Introduce `@parameter p1` which adds an argument `p1` to the constructor
    + Solution 2: `@graph TestGraph(p1, p2) begin ... end`
        + Defines the form of the constructor
        + What if I want multiple constructors? Possibly make use of "outside constructors"
+ Some code needs to be run in the main thread (e.g. all UI operations in QT).
    + we need a mechanism to specify whether callbacks need to be run in UI thread
    or not.
+ Add closed loop control in determining the sleep period for polling the source
    calculator.
    + Technically, we could be polling too fast and filling up the `Channel` buffers.
+ Flow limiter: the initial bootstrap takes into account the compilation time.
+ Bootstrap: the initial flow estimate is very much an underestimate, and the graph takes a few seconds to get to its limiting fps.
+ BUG: If a packet is dropped on the first run of a graph, the graph just hangs.
    + Take into consideration when redesigning the bootstrap
+ Tasks spawned within calculators are not waited for when graph is stopped
+ BUG: A user cannot use the symbol `calcs` within the `@graph` definition
    + Use gensym-like names instead
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
    maybe send a message so that the source rate is reevaluated.
+ Flow limiter: source calculator execution time should be subtracted from fps
+ Some nice error messages and reference number (e.g. E1032), similar to what Rust does
+ Debug mechanism for when your graph just hangs
    + Perhaps a trace of which `process()` gets called and what not so you can see right away which part is hanging.
+ A subgraph construct, which allows a user to define a subgraph that can be used as one calculator in graphs.

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
    + The source function should also be able to release its resources
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

# Source Calculator
+ The user *must* provide *one* "source" calculator.
# Shutting down from `stop()`
+ The `stop()` function turns sets `graph.done = false`
+ The source task sees `done`, so sends a DONE packet through the graph. Exits.
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
2. source task
    + Reads packet from source calculator
        + Handles errors
    + Writes packet to graph
    + Hangs until it's time to read again
        + `period` if bootstrapped
        + after packet reaches all outputs if bootstrapping
3. Flow limiter period evaluation
    + determine and set the new source period