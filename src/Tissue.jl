module Tissue

import Base.Threads: @spawn, @threads, threadid
using MLStyle

export Graph, CalculatorBase, get_data, register_callback, start, stop, wait_until_done
export @graph, @calculator, @defstreams, @defoutputstream, @definputstream,
       @generatorcalculator


"""
The parent type of all calculators.
"""
abstract type CalculatorBase end

function process(calc::CalculatorBase)
    throw("Called unimplemented process(). This shouldn't happen.")
end

function close(calc::CalculatorBase)
    # nothing
end

include("graph.jl")
include("core.jl")
include("macros.jl")

end # module Tissue
