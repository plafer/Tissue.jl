using Tissue
import Tissue as T

packets_received_receiver = Vector{Int}()
packets_received_barrier = Vector{Int}()
mutable struct GeneratorCalculator 
    last::Int
    max_gen::Int
    GeneratorCalculator() = new(1, 5)
end

function T.process(c::GeneratorCalculator)
    if c.last > c.max_gen
        return nothing
    end

    ret_val = c.last
    c.last += 1

    return ret_val
end

mutable struct InterleaverCalculator
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

struct ReceiverCalculator end

function T.process(calc::ReceiverCalculator, in_num::Int)
    push!(packets_received_receiver, in_num)
end

struct BarrierCalculator end

function T.process(calc::BarrierCalculator, in1::Int, in2::Int)
    push!(packets_received_barrier, in1 + in2)
end

struct PassthroughCalculator end

function T.process(calc::PassthroughCalculator, in_num::Int)
    in_num
end

@graph DroppingGraph begin
    @calculator generator = GeneratorCalculator()
    @calculator interleaver = InterleaverCalculator(2)
    @calculator receiver = ReceiverCalculator()

    @bindstreams interleaver in_num=generator
    @bindstreams receiver in_num=interleaver
end

graph = DroppingGraph()

T.start(graph)
T.wait_until_done(graph)

@test packets_received_receiver == [1, 3, 5]

# TODO: Test first packet is dropped. Currently a known bug.

"This graph tests whether Tissue.jl will properly throw away packets at the barrier, given that interleaver drops every other packet, which passthrough forwards them all."
@graph SynchronizationGraph begin
    @calculator generator = GeneratorCalculator()
    @calculator passthrough = PassthroughCalculator()
    @calculator interleaver = InterleaverCalculator(2)
    @calculator barrier = BarrierCalculator()
    
    @bindstreams passthrough in_num=generator
    @bindstreams interleaver in_num=generator
    @bindstreams barrier in1=passthrough in2=interleaver
end

graph = SynchronizationGraph()

T.start(graph)
T.wait_until_done(graph)

@test packets_received_barrier == [2, 6, 10]