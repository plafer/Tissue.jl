# Getting Started
+ With a guiding example, introduce all the key concepts
    + graph, calculators, streams
    + source calculator
    + flow limiter
    + sink

We will build a graph with the following topology.

![Example graph](img/example_graph.jpg)

The corresponding code to build that graph would be:
```julia
struct SourceCalculator end

function process(c::SourceCalculator)
    return 42
end

struct AddConstantCalculator
    constant::Int
end

function process(c::AddConstantCalculator, num_in::Int)::Int
    return num_in + c.constant
end

struct MultiplyCalculator end

function process(c::MultiplyCalculator, first_num::Int, second_num::Int)::Int
    return first_num * second_num
end

struct PrinterCalculator end

function process(c::PrinterCalculator, num_to_print)
    println(num_to_print)
end

@graph NumberGraph begin
    # 1. Declare calculators.
    @calculator source = SourceCalculator()
    @calculator add0 = AddConstantCalculator(0)
    @calculator add42 = AddConstantCalculator(42)
    @calculator mult = MultiplyCalculator()
    @calculator printer = PrinterCalculator()

    # 2. Declare the streams which connect the calculators together
    @bindstreams add0 (num_in = source)
    @bindstreams add42 (num_in = source)
    @bindstreams mult (first_num=add0) (second_num=add42)
    @bindstreams printer (num_to_print = mult)
end
```
