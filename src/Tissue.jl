module Tissue

import Base.Threads: @spawn, @threads

"""
The parent type of all calculators.
"""
abstract type CalculatorBase end

function open(calc::CalculatorBase)
    # nothing
end

function close(calc::CalculatorBase)
    # nothing
end

"""
The parent type of all graphs.
"""
abstract type Graph end

function get_input_channel(graph::Graph)::Channel
    graph.input_channel
end

function get_output_channel(graph::Graph, channel_name::Symbol)::Channel
    graph.named_output_channels[channel_name]
end

function process(calc::CalculatorBase)
    throw("Called base process(). This shouldn't happen. Please submit a bug report.")
end

struct Frame
    data::Any
    timestamp::Int64
end

struct Packet
    """
    The data contained in the packet
    """
    data::Any
    """
    The associated frame (that was initially written to the graph)
    """
    frame::Frame
end

get_frame_timestamp(p::Packet) = p.frame.timestamp
get_frame(p::Packet) = p.frame
get_data(p::Packet) = p.data

struct CalculatorWrapper
    calculator::CalculatorBase
    """
    All Channels which connect the wrapped calculator with the rest of the graph.

    Invariant: the order of the channels corresponds to the order of the arguments
    of the corresponding `process()`.
    """
    input_channels::Vector{Channel}

    """
    All channels corresponding to the one output stream (one channel per subscriber)
    """
    output_channels::Vector{Channel}
end

get_calculator(cw::CalculatorWrapper) = cw.calculator
get_output_channels(cw::CalculatorWrapper)::Vector{Channel} = cw.output_channels

"""
Blocks on all channels until data is available on all channels. 

Discards all old packets in the case where all channels don't refer to the same frame.
This could happen if an upstream calculator threw away a packet.

Contract
+ All returned packets refer to the same frame
"""
function fetch_input_streams(cw::CalculatorWrapper)::Vector{Packet}
    # Wait until data is ready on all channels
    for channel in cw.input_channels
        fetch(channel)
    end

    packets = map(take!, cw.input_channels)

    # Drop old packets
    newest_timestamp = max(map(get_frame_timestamp, packets)...)
    for (idx, packet) in enumerate(packets)
        while get_frame_timestamp(packet) < newest_timestamp
            packet = take!(cw.input_channels[idx])
        end

        @assert get_frame_timestamp(packet) == newest_timestamp
        packets[idx] = packet
    end

    return packets
end

"""
Monitors input streams, calls on the calculator to process the data, and forwards
the return value in the output channel.
"""
function run_calculator(cw::CalculatorWrapper)
    while true
        in_packets::Vector{Packet} = fetch_input_streams(cw)
        frame = get_frame(in_packets[1])

        out_value = nothing
        try
            out_value = process(get_calculator(cw), map(get_data, in_packets)...)
        catch e
            println("Error caught in process():")
            println(e)
            exit(1)
        end

        if out_value !== nothing
            out_packet = Packet(out_value, frame)

            for out_channel in get_output_channels(cw)
                put!(out_channel, out_packet)
            end
        end
    end
end

function resolve_process(
    calculator_datatype::DataType,
    streams::Vector{Symbol},
)::Vector{Channel}
    process_methods_argnames::Vector{Tuple{Method,Vector{Symbol}}} = begin
        CALCULATOR_TYPE_IDX = 2
        process_methods = filter(methods(process).ms) do m
            return get(m.sig.parameters, CALCULATOR_TYPE_IDX, false) == calculator_datatype
        end

        map(process_methods) do m
            argnames = ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), m.slot_syms)

            # The first argname is Symbol("#self#"). We skip it.
            return (m, argnames[2:m.nargs])
        end
    end # process_methods_argnames

    # TODO: Finish implementing
end

function init(graph::Graph)
    @threads for calc_wrapper in graph.calculator_wrappers
        open(calc_wrapper.calculator)
    end
end

function start_calculators(graph::Graph)
    for calculator_wrapper in graph.calculator_wrappers
        @spawn run_calculator(calculator_wrapper)
    end
end

"""
Return and increments timestamp.
"""
function next_timestamp(graph::Graph)
    next = graph.next_timestamp
    graph.next_timestamp += 1

    next
end

"""
Writes a value to the graph's input stream.
"""
function write(graph::Graph, data)
    # TODO: If graph is not started, throw exception
    timestamp = next_timestamp(graph)
    packet_frame = Frame(data, timestamp)
    packet = Packet(data, packet_frame)
    put!(get_input_channel(graph), packet)
end

"""
Reads a value from an output stream. Blocking.
"""
function poll(graph::Graph, channel_name::Symbol)
    take!(get_output_channel(graph, channel_name))
end

end # module Tissue
