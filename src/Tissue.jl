module Tissue

import Base.Threads: @spawn, @threads, threadid
using MLStyle

export Graph, start, stop, wait_until_done
export @graph, @calculator, @bindstreams


function process()
    throw("Called unimplemented process(). This shouldn't happen.")
end

function close(calc)
    # nothing
end

include("graph.jl")
include("core.jl")
include("macros.jl")

end # module Tissue
