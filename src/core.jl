"""
Period at which we should reevaluate the source period (seconds)
"""
const SOURCE_PERIOD_REEVAL_PERIOD = 1
const SOURCE_PERIOD_REEVAL_ALPHA = 0.1

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
    calculator::Any
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

    "Whether the wrapped calculator is a sink calculator"
    is_sink::Bool

    "Whether the resolved process method has a `graph` keyword parameter"
    process_has_graph_kw::Bool

    """
    Statistic about the (exponentially smoothed) execution time of the calculator's
    `process()`.
    """
    exec_time::Threads.Atomic{Float64}

    CalculatorWrapper(calc, input_channels, output_channels, is_sink, has_graph_kw) = new(
        calc,
        input_channels,
        output_channels,
        is_sink,
        has_graph_kw,
        Threads.Atomic{Float64}(-1.0),
    )
end

get_calculator(cw::CalculatorWrapper) = cw.calculator
get_input_channels(cw::CalculatorWrapper)::Vector{Channel} = cw.input_channels
get_output_channels(cw::CalculatorWrapper)::Vector{Channel} = cw.output_channels
is_sink(cw::CalculatorWrapper) = cw.is_sink
process_has_graph_kw(cw::CalculatorWrapper) = cw.process_has_graph_kw
get_exec_time(cw::CalculatorWrapper) = cw.exec_time[]

function add_new_exec_time(cw::CalculatorWrapper, new_time::Float64)
    current_time = get_exec_time(cw)
    if current_time > 0.0
        cw.exec_time[] =
            SOURCE_PERIOD_REEVAL_ALPHA * current_time +
            (1 - SOURCE_PERIOD_REEVAL_ALPHA) * new_time
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
                stats = nothing
                if process_has_graph_kw(cw)
                    stats = @timed process(
                        get_calculator(cw),
                        map(get_data, in_packets)...,
                        graph = graph,
                    )
                else
                    stats = @timed process(get_calculator(cw), map(get_data, in_packets)...)
                end
                add_new_exec_time(cw, stats.time)
                out_value = stats.value
            catch e
                println("Error caught: $e :")
                display(stacktrace(catch_backtrace()))
                println()
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

        if is_sink(cw) && is_last_sink_not_init(graph)
            # Source period bootstrap just ended
            lk = get_flow_limiter_bootstrap_lock(graph)

            lock(lk)
            notify(get_flow_limiter_bootstrap_cond(graph))
            unlock(lk)
        end

    end
end

"""
Evaluates the flow limiter period (i.e. the amount of time to sleep in between fetching new packets from the source calculator)
"""
function evaluate_packet_period(graph)
    non_gen_cws = filter(
        cw -> cw != get_source_calculator_wrapper(graph),
        get_calculator_wrappers(graph),
    )

    exec_times = map(get_exec_time, non_gen_cws)
    if all(time -> time > 0.0, exec_times)
        new_gen_period = max(exec_times...)
        set_source_period(graph, new_gen_period)
    end
end

"""
Generates a packet using the source calculator and writes it to the graph.

Returns true if generate and write were successful, false if not, in which case the graph is stopped.

"""
function generate_packet_and_write(graph::Graph)::Bool
    packet_data = nothing
    try
        source_cw = get_source_calculator_wrapper(graph)
        packet_data = process(get_calculator(source_cw))
    catch e
        println("Error caught in source's process():\n$e")
    end

    if packet_data === nothing
        stop(graph)
        return false
    end

    write(graph, packet_data)
    return true
end

"""
    start(graph)

Start all the calculators and begin pulling data out of the source calculator.

All calculators run in their own [task](https://docs.julialang.org/en/v1/base/parallel/#Tasks). A call to `start(graph)` does not block; it returns after spawning all the tasks.
"""
function start(graph::Graph)
    # TODO: If already started, error

    # Start all non-source calculators
    for calculator_wrapper in get_calculator_wrappers(graph)
        if calculator_wrapper != get_source_calculator_wrapper(graph)
            t = @spawn run_calculator(graph, calculator_wrapper)
            push!(get_cw_tasks(graph), t)
        end
    end

    # Generate the first packet
    success = generate_packet_and_write(graph)
    if !success
        return
    end

    # Start bootstrap
    @spawn begin
        lk = get_flow_limiter_bootstrap_lock(graph)
        cond = get_flow_limiter_bootstrap_cond(graph)

        lock(lk)
        try
            while get_num_sinks_not_init(graph) > 0
                wait(cond)
            end
        finally
            unlock(lk)
        end

        evaluate_packet_period(graph)

        # Start source function
        @spawn begin
            while !is_done(graph)
                if generate_packet_and_write(graph)
                    sleep(get_source_period(graph))
                else
                    break
                end
            end

            write_done(graph)
        end

        # Start flow limiter period evaluation
        @spawn begin
            sleep(SOURCE_PERIOD_REEVAL_PERIOD)
            while !is_done(graph)
                evaluate_packet_period(graph)
                sleep(SOURCE_PERIOD_REEVAL_PERIOD)
            end
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
    timestamp = inc_next_timestamp(graph)
    packet_frame = Frame(data, timestamp)
    packet = Packet(data, packet_frame)

    for channel in get_output_channels(get_source_calculator_wrapper(graph))
        put!(channel, packet)
    end
end

"""
Writes a DONE packet to the graph's input stream.
"""
function write_done(graph::Graph)
    timestamp = inc_next_timestamp(graph)
    packet_frame = Frame(nothing, timestamp)
    done_packet = Packet(packet_frame)

    for channel in get_output_channels(get_source_calculator_wrapper(graph))
        put!(channel, done_packet)
    end
end
