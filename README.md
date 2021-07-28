# To implement
+ Think about mutation: How do we avoid race conditions? Ideas:
    1. For arrays, use [ReadOnlyArrays](https://github.com/bkamins/ReadOnlyArrays.jl)
        + What about any other types, including user types?
    2. wrap all outputs in a "copy on write" wrapper.
        + How to do that for all objects?
        + Actually, for their custom types, it won't work.
    3. Make copies all the time...
        + We certainly don't want to do that
    4. Use `Cassette.jl` to check for changes in mutable objects
        + Note: `ismutable()` can tell you if an object is mutable
    5. Simply document that it's the programmer's responsibility to copy or
    use locks on mutable `process()` arguments.
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
+ Deal with issue: we currently check the output type of `process()` to make sure it's correct.
    + Maybe we can let julia tell us somehow without crashing at runtime.
+ When we CTRL+C, catch it and exit without showing the crap julia shows us
+ Graph shutdown function
    + Similar to MediaPipe's `graph.CloseInputStream()`.
    + Think about how this interacts with `poll()`: e.g. `poll()` could return nothing
    when graph is shutdown and nothing is being processed anymore.
+ write() should throw exception if graph was not started
+ Should we remove init() and start()? Or at least offer a `init_and_start()`.
+ Some nice error messages and reference number (e.g. E1032), similar to what Rust does

# Feature request
+ Specify if you want calculators to run with async (1 thread), or spawn (multiple threads)
    + Can be useful to debug calculators. Debugger only runs in main thread I think.

# Fundamental issues to de-risk
+ Multi-threading can [break finalizers](https://docs.julialang.org/en/v1/manual/multi-threading/#Safe-use-of-Finalizers)
    + libraries that we'll use, e.g. OpenCV wrapper or CUDA.jl, will probably use
    finalizers.
    + Can we not use threads then? Or some other lock wizardry of some sort?

# Crazy ideas or are they
+ Build a GUI that lets you generate the scaffolding for a given graph structure
+ Build a tracer that lets you visualize packets traveling through the graph, and a timeline similar to MediaPipe