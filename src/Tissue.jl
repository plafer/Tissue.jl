module Tissue

import Base.Threads: @spawn, @threads, threadid

"""
The parent type of all calculators.
"""
abstract type CalculatorBase end

function open(calc::CalculatorBase)
    # nothing
end

function process(calc::CalculatorBase)
    throw("Called base process(). This shouldn't happen.")
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

function get_generator_calculator(graph::Graph)::CalculatorBase
    graph.generator_calculator
end

function get_output_channel(graph::Graph, channel_name::Symbol)::Channel
    graph.named_output_channels[channel_name]
end

function stop(graph::Graph)
    graph.done[] = true
end

function is_done(graph::Graph)
    graph.done[]
end

function wait_until_done(graph::Graph)
    # Wait on all tasks
    for calculator_wrapper_task = graph.cw_tasks
        wait(calculator_wrapper_task)
    end

    graph.cw_tasks = Vector{Task}()

    # cleanup
    for calculator = map(get_calculator, graph.calculator_wrappers)
        close(calculator)
    end

    close(graph.generator_calculator)
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
    """
    Whether this is a DONE packet or not
    """
    done::Bool

    # FIXME: ugly
    Packet(frame::Frame) = new(nothing, frame, true)
    Packet(data, frame::Frame) = new(data, frame, false)
end

get_frame_timestamp(p::Packet) = p.frame.timestamp
get_frame(p::Packet) = p.frame
get_data(p::Packet) = p.data
is_done_packet(p::Packet) = p.done

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
    packets = map(take!, cw.input_channels)

    # Drop old packets
    newest_timestamp = max(map(get_frame_timestamp, packets)...)
    for (idx, packet) in enumerate(packets)
        while get_frame_timestamp(packet) < newest_timestamp
            packet = take!(cw.input_channels[idx])
        end

        packets[idx] = packet
    end

    return packets
end


"""
Monitors input streams, calls on the calculator to process the data, and forwards
the return value in the output channel.
"""
function run_calculator(graph::Graph, cw::CalculatorWrapper)
    # TODO: Refactor to make more readable

    done = false
    while !done
        in_packets::Vector{Packet} = fetch_input_streams(cw)

        if all(is_done_packet, in_packets)
            # Note: calculators will be `close()`d in the main thread
            done_packet = in_packets[1]
            for out_channel in get_output_channels(cw)
                put!(out_channel, done_packet)
            end

            done = true
        else
            out_value = nothing
            try
                out_value = process(get_calculator(cw), map(get_data, in_packets)...)
            catch e
                println("Error caught in process():\n$(e)")
                stop(graph)
                done = true
            end

            if !done && out_value !== nothing
                frame = get_frame(in_packets[1])
                out_packet = Packet(out_value, frame)

                for out_channel in get_output_channels(cw)
                    put!(out_channel, out_packet)
                end
            end
        end
    end
end

# TODO: Finish implementing
# This function will be used by the macros
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

function start_calculators(graph::Graph)
    for calculator_wrapper in graph.calculator_wrappers
        t = @spawn begin
            run_calculator(graph, calculator_wrapper)
        end

        push!(graph.cw_tasks, t)
    end

    @spawn begin
        while !is_done(graph)
            # TODO: Refactor (code dup with `run_calculator`)
            packet_data = nothing
            try
                packet_data = process(graph.generator_calculator)
            catch e
                println("Error caught in generator's process():\n$(e)")
                stop(graph)
                break
            end

            if packet_data !== nothing
                write(graph, packet_data)
                # TODO: Sleep based on open + closed loop control
                sleep(1.0 / 30.0)
            else
                stop(graph)
                break
            end
        end
        
        write_done(graph)
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
function write(graph::Graph, data::Any)
    # TODO: If graph is not started, throw exception
    timestamp = next_timestamp(graph)
    packet_frame = Frame(data, timestamp)
    packet = Packet(data, packet_frame)
    put!(get_input_channel(graph), packet)
end

"""
Writes a DONE packet to the graph's input stream.
"""
function write_done(graph::Graph)
    timestamp = next_timestamp(graph)
    packet_frame = Frame(nothing, timestamp)
    done_packet = Packet(packet_frame)
    put!(get_input_channel(graph), done_packet)
end

"""
Register a callback to a graph output stream.

graph: the graph
channel_name: the name of the output stream
callback: function which takes 2 arguments: state, and Packet
state: an object that will be passed back to your callback
"""
function register_callback(callback, graph::Graph, channel_name::Symbol, state)
    @spawn begin
        output_channel = get_output_channel(graph, channel_name)
        while true
            packet = take!(output_channel)
            if is_done_packet(packet)
                break
            end

            callback(state, packet)
        end
    end
end

end # module Tissue
