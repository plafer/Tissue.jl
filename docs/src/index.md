# Tissue.jl
The core idea behind Tissue.jl is to simplify the processing of data streams while maximizing performance with parallelization. The processing pipeline is modeled as a directed acyclic graph, where each node runs in its own [task](https://docs.julialang.org/en/v1/manual/asynchronous-programming/). Nodes, which we call *calculators*, send each other *packets* over *streams*, the directed edges of the graph. If each node is a biological cell, then a graph would be a tissue, wouldn't it?

## Installation
Download and install [Julia 1.x](https://julialang.org/) if you haven't already. To install Tissue.jl, launch julia and type the following.
```shell
julia> ]
(@v1.x) pkg> add Tissue
```
Julia's [package manager](https://pkgdocs.julialang.org/v1/) will install Tissue.jl in the active environment.
## Overview
Here's what programming in Tissue.jl looks like.

1. Write your calculators
    + This is where all the computation happens. One and only one of these calculators, identified by the fact that it takes no input, is the *source*.
2. Define the graph topology
    + Using our graph definition [Domain Specific Language](https://en.wikipedia.org/wiki/Domain-specific_language) (DSL), define how the data flows from one calculator to the next.
3. Run the graph
    + Start the graph and let it do its thing. Tissue.jl will run all the calculators in parallel and pull data from the source calculator as fast as your graph can handle it.

When you write a calculator, you can specify the different set of streams it can accept, with a behavior corresponding to each set. Hence, calculators are reusable across different graph topologies. It's also easy to define new sets of streams a calculator can accept, lending on the power of multiple dispatch. It's therefore easy to adapt other people's calculators to fit nicely in your graph. Working in Tissue.jl also lends itself to working in teams. Different people work on different calculators, and you stitch the calculators together in one or more graphs at the end.

A core feature of Tissue.jl is the flow limiter. Every graph has one and only one source, which generates the next datum in the data stream to be processed. The flow limiter is the component that determines the rate at which data should be pulled out of the source so as to pull data out of the source as fast as the graph can process it. The flow limiter keeps internal statistics about how long it takes for each calculator to process the data packets. Thus, for example, if your CPUs get too hot and throttled, the flow limiter will detect that change and adjust the rate at which data is pulled out of the source so as not to overflow the graph with packets.
