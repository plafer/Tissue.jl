# Getting Started
+ With a guiding example, introduce all the key concepts
    + graph, calculators, streams
    + generator calculator
    + flow limiter
    + sink

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
    @bindstreams add0 (num_in = generator)
    @bindstreams add42 (num_in = generator)
    @bindstreams mult (first_num=add0) (second_num=add42)
    @bindstreams printer (num_to_print = mult)
end
```
