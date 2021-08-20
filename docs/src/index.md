# Tissue.jl
The core idea behind Tissue.jl is to simplify the processing of data streams while maximizing performance with parallelization. The processing pipeline is modeled as a directed acyclic graph, where each node runs in its own [task](https://docs.julialang.org/en/v1/manual/asynchronous-programming/). Nodes, which we call *calculators*, send each other *packets* over *streams*, the directed edges of the graph. If each node is a biological cell, then a graph would be a tissue, wouldn't it?

## Installation
Download [Julia 1.x](https://julialang.org/) if you haven't already. To install Tissue.jl, launch julia and type the following.
```julia
julia> ]
(@v1.x) pkg> add Tissue
```
Julia's [package manager](https://pkgdocs.julialang.org/v1/) will install Tissue.jl in the active environment.
## Overview
Here's what programming in Tissue.jl looks like.

1. Write your calculators
    + This is where all the computation happens. One and only one of these calculators, identified by the fact that it takes no input, is the so-called *source*.
2. Define the graph topology
    + Using our graph definition [Domain Specific Language](https://en.wikipedia.org/wiki/Domain-specific_language) (DSL), define how the data flows from one calculator to the next.
3. Run the graph
    + Start the graph and let it do its thing. Tissue.jl will run all the calculators in parallel and pull data from the source calculator as fast as your graph can handle it.

Calculators are inherently reusable: they can be plugged in different graph topologies. TODO: They are defined in a way that can accept a different set of streams

TODO: Talk about how this makes code (calculator) reuse easy across graphs, and also lends itself to working in teams (every person writes a calculator, and you plug them together at the end)