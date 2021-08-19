using Tissue
import Tissue as T
import Base.Threads

const MAX_GEN = 3

accumulator = Threads.Atomic{Int}(0)

mutable struct GeneratorCalculator <: CalculatorBase 
    last::Int
    GeneratorCalculator() = new(1)
end

function T.process(c::GeneratorCalculator)
    if c.last > MAX_GEN
        return nothing
    end

    ret_val = c.last
    c.last += 1

    return ret_val
end

struct AddConstantCalculator <: CalculatorBase
    constant::Int
end

function T.process(c::AddConstantCalculator, num_in::Int; graph::Graph)::Int
    return num_in + c.constant
end

struct SubtractConstantCalculator <: CalculatorBase
    constant::Int
end

function T.process(c::SubtractConstantCalculator, num_in::Int)::Int
    return num_in - c.constant
end

struct MultiplyCalculator <: CalculatorBase end

function T.process(c::MultiplyCalculator, first_num::Int, second_num::Int)::Int
    return first_num * second_num
end

mutable struct PrinterCalculator <: CalculatorBase end

function T.process(c::PrinterCalculator, num_to_print)
    accumulator[] += num_to_print

    nothing
end

@graph NumberGraph begin
    # 1. Declare calculators.
    @calculator generator = GeneratorCalculator()
    @calculator add1 = AddConstantCalculator(1)
    @calculator sub2 = SubtractConstantCalculator(2)
    @calculator mult = MultiplyCalculator()
    @calculator printer = PrinterCalculator()

    # 2. Declare the streams which connect the calculators together
    @bindstreams add1 num_in = generator
    @bindstreams sub2 num_in = generator
    @bindstreams mult (first_num = add1) (second_num = sub2)
    @bindstreams printer num_to_print=mult
end

graph = NumberGraph()

###############################
# Before the graph is started
###############################
@test typeof(T.get_calculator(T.get_generator_calculator_wrapper(graph))) ==
      GeneratorCalculator

@test length(T.get_calculator_wrappers(graph)) == 5

expected_values = Dict(
    GeneratorCalculator => Dict(
        :len_input_ch => 0,
        :len_output_ch => 2,
        :is_sink => false,
        :has_graph_kw => false,
    ),
    AddConstantCalculator => Dict(
        :len_input_ch => 1,
        :len_output_ch => 1,
        :is_sink => false,
        :has_graph_kw => true,
    ),
    SubtractConstantCalculator => Dict(
        :len_input_ch => 1,
        :len_output_ch => 1,
        :is_sink => false,
        :has_graph_kw => false,
    ),
    MultiplyCalculator => Dict(
        :len_input_ch => 2,
        :len_output_ch => 1,
        :is_sink => false,
        :has_graph_kw => false,
    ),
    PrinterCalculator => Dict(
        :len_input_ch => 1,
        :len_output_ch => 0,
        :is_sink => true,
        :has_graph_kw => false,
    ),
)

for cw in T.get_calculator_wrappers(graph)
    vals_for_calc = expected_values[typeof(T.get_calculator(cw))]

    @test length(T.get_input_channels(cw)) == vals_for_calc[:len_input_ch]
    @test length(T.get_output_channels(cw)) == vals_for_calc[:len_output_ch]
    @test T.is_sink(cw) == vals_for_calc[:is_sink]
    @test T.process_has_graph_kw(cw) == vals_for_calc[:has_graph_kw]
end

###############################
# After the graph is started
###############################

@test T.is_done(graph) == false
@test T.get_num_sinks_not_init(graph) == 1
@test length(T.get_cw_tasks(graph)) == 0

T.start(graph)

# The GeneratorCalculator does not run in a cw_task
@test length(T.get_cw_tasks(graph)) == 4

T.wait_until_done(graph)

@test length(T.get_cw_tasks(graph)) == 0
@test T.is_done(graph) == true

@test accumulator[] == 2