# Tissue.jl
In Tissue.jl, computations to be done on an input stream are described by a directed-acyclic graph. Write how each node, called calculators, processes inputs into outputs, link these nodes together in a graph, and Tissue.jl takes care of running the whole thing, running each node in its own task. If each node is a biological cell, then a graph would be a tissue, wouldn't it?

## Brainstorm
+ Use of multiple dispatch
    + Automatic resolving of `process()`
        + Clean way to adapt a calculator to different graph topologies
+ Parallel execution of calculators
+ DSL for specifying graphs
+ flow limiter
+ Automatic Synchronization
    + You always know the frame that you're processing
    + Framework waits for all inputs to have arrived
        + potentially: talk about throwing out old ones

# History
Tissue.jl is heavily inspired by [MediaPipe](https://arxiv.org/abs/1906.08172).