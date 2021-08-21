module Tissue

import Base.Threads: @spawn, @threads, threadid
using MLStyle

export Graph, start, stop, wait_until_done
export @graph, @calculator, @bindstreams

"""
    process(calculator, ...; graph::Graph)

Process the input streams into an output.

The first argument must be the associated calculator. Any other argument defines an input stream to the calculator. An input stream will be named with the exact same name as the corresponding argument. Optionally, if you need a reference to the `graph` object in the `process()` method, you can add it as a keyword argument named `graph` and Tissue.jl will supply a reference to the active graph object.

It is important to remember that each calculator runs in its own task. Therefore, best practices about concurrency must be applied. Notably, the stream arguments of `process()` could possibly be accessed by multiple threads simultaneously. Therefore, it is highly recommended to make a [`deepcopy`](https://docs.julialang.org/en/v1/base/base/#Base.deepcopy) of an argument before mutating it. This will also make your calculator more reusable across graphs.

Multiple `process()` methods can be defined per calculator, allowing the calculator to be used in different graph topologies.


# Arguments
`calculator`: the associated calculator
...: the input streams

# Examples
```julia
using Base: deepcopy

function process(calc::MyCalculator, in_stream; graph)
    if some_condition
        stop(graph)
    end

    in_stream_copy = deepcopy(in_stream)

    mutate(in_stream_copy)

    return in_stream_copy
end
```
"""
function process(calculator)
    throw("Called unimplemented process(). This shouldn't happen.")
end

"""
    close(calculator)

Perform cleanup for the calculator. Optional.

You can define a method for your calculator type to perform any necessary cleanup. Called by [`wait_until_done(graph)`](@ref) on each calculator to perform cleanup.

# Examples
```julia
struct GoofyCalculator 
    resource
    function GoofyCalculator() 
        resource = acquire_resource()
        new(resource)
    end
end

function process(c::GoofyCalculator, some_stream)
    use_resource(c.resource)
end

function close(c::GoofyCalculator)
    release_resource(c.resource)
end
```
"""
function close(calculator)
    # nothing
end

include("graph.jl")
include("core.jl")
include("macros.jl")

end # module Tissue
