# Tissue.jl
In Tissue.jl, computations to be done on an input stream are described by a directed-acyclic graph. Write how each node, called calculators, processes inputs into outputs, link these nodes together in a graph, and Tissue.jl takes care of running the whole thing, running each node in its own task. If each node is a biological cell, then a graph would be a tissue, wouldn't it?

## Design
The core idea behind Tissue.jl is to simplify the processing of data streams while maximizing performance with parallelization. The processing pipeline is modeled as a directed acyclic graph, where each node runs in its own task. Nodes, which we call *calculators*, send each other *packets* over *streams*. Callbacks are registered with the graph to get processed inputs out.

## Key concepts
+ Calculator: a stateful node in the graph which processes inputs to form outputs
    + Generator: a special calculator which generates the data stream (e.g. video stream) that will be processed by the graph.
+ Stream: the edges in the graph. 
    + Output stream: 

## Example
We will build a graph with the following topology.

![Example graph](img/example_graph.jpg)

The corresponding code to build that graph would be:
```julia
struct GeneratorCalculator <: CalculatorBase end

function process(c::GeneratorCalculator)
    return 42
end

struct AddConstantCalculator <: CalculatorBase
    constant::Int
end

function process(c::AddConstantCalculator, num_in::Int)::Int
    return num_in + c.constant
end

struct MultiplyCalculator <: CalculatorBase end

function process(c::MultiplyCalculator, first_num::Int, second_num::Int)::Int
    return first_num * second_num
end

struct PrinterCalculator <: CalculatorBase end

function process(c::PrinterCalculator, num_to_print)
    println(num_to_print)
end

@graph NumberGraph begin
    # 1. Declare calculators.
    @calculator generator = GeneratorCalculator()
    @calculator add0 = AddConstantCalculator(0)
    @calculator add42 = AddConstantCalculator(42)
    @calculator mult = MultiplyCalculator()
    @calculator printer = PrinterCalculator()

    # 2. Declare the streams which connect the calculators together
    @bindstreams add0 num_in=generator
    @bindstreams add42 num_in = generator
    @bindstreams mult first_num=add0 second_num=add42
    @bindstreams printer num_to_print=mult
end
```