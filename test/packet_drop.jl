using Tissue
import Tissue as T

packets_received = Vector{Int}()

mutable struct GenCalculator <: CalculatorBase 
    last::Int
    max_gen::Int
    GenCalculator() = new(1, 5)
end

function T.process(c::GenCalculator)
    if c.last > c.max_gen
        return nothing
    end

    ret_val = c.last
    c.last += 1

    return ret_val
end

mutable struct InterleaverCalculator <: CalculatorBase
    keep_freq::Int64
    count::Int64
    function InterleaverCalculator(keep_freq)
        new(keep_freq, 0)
    end
end

function T.process(calc::InterleaverCalculator, in_num::Int)
    keep_it = calc.count % calc.keep_freq == 0
    calc.count += 1

    if !keep_it
        return nothing
    end

    return in_num
end

struct ReceiverCalculator <: CalculatorBase end

function T.process(calc::ReceiverCalculator, in_num::Int)
    push!(packets_received, in_num)
end

@graph DroppingGraph begin
    @calculator generator = GenCalculator()
    @calculator interleaver = InterleaverCalculator(2)
    @calculator receiver = ReceiverCalculator()

    @bindstreams interleaver in_num=generator
    @bindstreams receiver in_num=interleaver
end

graph = DroppingGraph()

T.start(graph)
T.wait_until_done(graph)

@test packets_received == [1, 3, 5]

# TODO: Test first packet is dropped. Currently a known bug.