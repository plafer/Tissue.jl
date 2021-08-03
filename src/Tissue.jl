module Tissue

import Base.Threads: @spawn, @threads, threadid

"""
Period at which we should reevaluate the generator period (seconds)
"""
const GENERATOR_PERIOD_REEVAL_PERIOD = 1
const GENERATOR_PERIOD_REEVAL_ALPHA = 0.9

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

function get_calculator_wrappers(graph::Graph)
    graph.calculator_wrappers
end

function get_cw_tasks(graph::Graph)
    graph.cw_tasks
end

function set_cw_tasks(graph::Graph, cw_tasks::Vector{Task})
    graph.cw_tasks = cw_tasks 
end

function get_next_timestamp(graph::Graph)
    graph.next_timestamp
end

function set_next_timestamp(graph::Graph, next_ts)
    graph.next_timestamp = next_ts
end

"""
Gracefully stops the graph. `wait_until_done()` should be called to block the main
thread until the graph is stopped.
"""
function stop(graph::Graph)
    graph.done[] = true
end

function is_done(graph::Graph)
    graph.done[]
end

"""
Gets the period (in the sense of inverse frequency) at which the generator
calculator should be called to generate new graph input stream packets.
"""
function get_generator_period(graph::Graph)::Float64
    graph.gen_period[]
end

function set_generator_period(graph::Graph, period::Float64)
    graph.gen_period[] = period
end

function wait_until_done(graph::Graph)
    # Wait on all tasks
    for calculator_wrapper_task in get_cw_tasks(graph)
        wait(calculator_wrapper_task)
    end

    set_cw_tasks(graph, Vector{Task}())

    # cleanup
    for calculator in map(get_calculator, get_calculator_wrappers(graph))
        close(calculator)
    end

    close(get_generator_calculator(graph))
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

    """
    Statistic about the (exponentially smoothed) execution time of the calculator's
    `process()`.
    """
    exec_time::Threads.Atomic{Float64}

    CalculatorWrapper(calc, input_channels, output_channels) =
        new(calc, input_channels, output_channels, Threads.Atomic{Float64}(-1.0))
end

get_calculator(cw::CalculatorWrapper) = cw.calculator
get_output_channels(cw::CalculatorWrapper)::Vector{Channel} = cw.output_channels

get_exec_time(cw::CalculatorWrapper) = cw.exec_time[]

function add_new_exec_time(cw::CalculatorWrapper, new_time::Float64)
    current_time = get_exec_time(cw)
    if current_time > 0.0
        cw.exec_time[] =
            GENERATOR_PERIOD_REEVAL_ALPHA * current_time +
            (1 - GENERATOR_PERIOD_REEVAL_ALPHA) * new_time
    else
        cw.exec_time[] = new_time
    end
end

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
                stats = @timed process(get_calculator(cw), map(get_data, in_packets)...)
                add_new_exec_time(cw, stats.time)
                out_value = stats.value
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

function start(graph::Graph)
    # Start calculators
    for calculator_wrapper in get_calculator_wrappers(graph)
        t = @spawn begin
            run_calculator(graph, calculator_wrapper)
        end

        push!(get_cw_tasks(graph), t)
    end

    # Start generator function
    @spawn begin
        while !is_done(graph)
            # TODO: Refactor (code dup with `run_calculator`)
            packet_data = nothing
            try
                packet_data = process(get_generator_calculator(graph))
            catch e
                println("Error caught in generator's process():\n$(e)")
                stop(graph)
                break
            end

            if packet_data !== nothing
                write(graph, packet_data)
                period = max(0.001, get_generator_period(graph))
                sleep(period)
            else
                stop(graph)
                break
            end
        end

        write_done(graph)
    end

    # Start flow limiter period evaluation
    @spawn begin
        while !is_done(graph)
            exec_times = map(get_exec_time, get_calculator_wrappers(graph))
            if all(time -> time > 0.0, exec_times)
                new_gen_period = max(exec_times...)
                set_generator_period(graph, new_gen_period)

            end

            sleep(GENERATOR_PERIOD_REEVAL_PERIOD)
        end
    end
end

"""
Return and increments timestamp.
"""
function inc_next_timestamp(graph::Graph)
    next_ts = get_next_timestamp(graph)
    set_next_timestamp(graph, next_ts + 1)

    next_ts
end

"""
Writes a value to the graph's input stream.
"""
function write(graph::Graph, data::Any)
    # TODO: If graph is not started, throw exception
    timestamp = inc_next_timestamp(graph)
    packet_frame = Frame(data, timestamp)
    packet = Packet(data, packet_frame)
    put!(get_input_channel(graph), packet)
end

"""
Writes a DONE packet to the graph's input stream.
"""
function write_done(graph::Graph)
    timestamp = inc_next_timestamp(graph)
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
