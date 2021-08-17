# Tissue.jl
In Tissue.jl, computations to be done on an input stream are described by a directed-acyclic graph. Write how each node, called calculators, processes inputs into outputs, link these nodes together in a graph, and Tissue.jl takes care of running the whole thing, running each node in its own task. If each node is a biological cell, then a graph would be a tissue, wouldn't it?

# Acknowledgements
Tissue.jl is heavily inspired by [MediaPipe](https://arxiv.org/abs/1906.08172).