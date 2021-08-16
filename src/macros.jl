function resolve_process(
    calculator_datatype::DataType,
    input_streams,
)::Tuple{Vector{Channel},Bool}
    argnames_and_has_graph = begin
        CALCULATOR_TYPE_IDX = 2
        # TODO: use filter(collect(methods(process)))
        process_methods = filter(methods(process).ms) do m
            if length(m.sig.parameters) >= CALCULATOR_TYPE_IDX
                return m.sig.parameters[CALCULATOR_TYPE_IDX] == calculator_datatype
            end

            return false
        end

        map(process_methods) do m
            argnames = ccall(:jl_uncompress_argnames, Vector{Symbol}, (Any,), m.slot_syms)

            # The first argname is Symbol("#self#"). We skip it.
            # The second argname is the calculator. We skip it.
            # :graph is a special keyword argument. 
            argnames_of_interest = argnames[3:m.nargs]
            kw_args = argnames[m.nargs:end]
            (
                argnames_of_interest,
                :graph in kw_args,
            )
        end
    end # process_methods_argnames

    input_stream_names::Base.KeySet = keys(input_streams)

    for (method_argnames, wants_graph) in argnames_and_has_graph
        if input_stream_names == Set(method_argnames)
            # we found our `process()` method!
            input_channels = [input_streams[argname] for argname in method_argnames]
            return (input_channels, wants_graph)
        end
    end

    throw(
        "Could not resolve process() for type $calculator_datatype and input streams $input_streams",
    )
end

function _graph(graph_name, init_block)
    GraphName = esc(graph_name)

    calcs_var = esc(:calcs)
    named_output_channels_var = esc(:named_output_channels)
    gen_calc_var = esc(:gen_calc)
    input_channels_var = esc(:input_channels)

    return quote
        mutable struct $GraphName <: Graph
            input_channels::Vector{Channel}
            named_output_channels::Dict{Symbol,Any}
            generator_calculator::CalculatorBase
            calculator_wrappers::Vector{CalculatorWrapper}
            cw_tasks::Vector{Task}
            next_timestamp::Int64
            done::Threads.Atomic{Bool}
            gen_period::Threads.Atomic{Float64}
            sinks_lock::Base.ReentrantLock
            num_sinks_not_init::Int64
            bootstrap_lock::Base.ReentrantLock
            bootstrap_cond::Threads.Condition

            function $GraphName()
                # calcs[:cc1] = (Dict(), [])
                # first (dict): in channels :in => channel
                # second (vector): out channels [channel1, channel2]
                $input_channels_var = Vector{Channel}()
                $calcs_var = Dict{Symbol,Any}()
                $named_output_channels_var = Dict{Symbol,Any}()
                calculator_wrappers = []
                $gen_calc_var = nothing

                $(esc(init_block))

                if $gen_calc_var === nothing
                    @error(
                        "You need to specify a generator calculator. See @generatorcalculator."
                    )
                end

                if isempty($input_channels_var)
                    @error(
                        "You need to specify at least one input channel. See @definputstream."
                    )
                end

                calculator_wrappers = []
                num_sinks_not_init = 0
                for pair in $calcs_var
                    calc_sym, (input_channels_dict, output_channels, calc) = pair

                    input_channels, has_graph_kw =
                        resolve_process(typeof(calc), input_channels_dict)

                    if input_channels === nothing
                        @error("Couldn't find process()")
                    end

                    is_sink_calculator = false
                    if isempty(output_channels)
                        is_sink_calculator = true
                        num_sinks_not_init += 1
                    end

                    cw = CalculatorWrapper(
                        calc,
                        input_channels,
                        output_channels,
                        is_sink_calculator,
                        has_graph_kw,
                    )
                    push!(calculator_wrappers, cw)
                end


                lk = Base.ReentrantLock()
                new(
                    $input_channels_var,
                    $named_output_channels_var,
                    $gen_calc_var,
                    calculator_wrappers,
                    [],
                    0,
                    Threads.Atomic{Bool}(false),
                    Threads.Atomic{Float64}(0.0),
                    Base.ReentrantLock(),
                    num_sinks_not_init,
                    lk,
                    Threads.Condition(lk),
                )
            end
        end
    end
end

macro graph(graph_name, init_block)
    return _graph(graph_name, init_block)
end

function _generatorcalculator(assign_expr)
    ctor = @match assign_expr begin
        :($var = $ctor) => ctor
    end

    return esc(quote
        gen_calc = $ctor
    end)
end
macro generatorcalculator(assign_expr)
    return _generatorcalculator(assign_expr)
end

function _calculator(assign_expr)
    calc = @match assign_expr begin
        :($calc = $rest) => calc
        _ => @error("Error!")
    end

    calcs_var = esc(:calcs)
    return quote
        $(esc(assign_expr))
        $calcs_var[$(QuoteNode(calc))] = (Dict(), [], $(esc(calc)))
    end
end

macro calculator(assign_expr)
    return _calculator(assign_expr)
end

function _definputstream(ex)
    calc, stream = _capture_calculator_stream(ex)

    calcs_var = esc(:calcs)
    input_channels_var = esc(:input_channels)

    return quote
        ch = Channel(32)
        push!($input_channels_var, ch)
        $calcs_var[$(QuoteNode(calc))][1][$(QuoteNode(stream))] = ch
    end
end

macro definputstream(ex)
    return _definputstream(ex)
end

function _defoutputstream(stream_name, calc)
    calcs_var = esc(:calcs)
    named_output_channels_var = esc(:named_output_channels)

    return quote
        ch = Channel(32)
        push!($calcs_var[$(QuoteNode(calc))][2], ch)
        $named_output_channels_var[$(esc(stream_name))] = ch
    end
end

macro defoutputstream(stream_name, user_calc_var)
    return _defoutputstream(stream_name, user_calc_var)
end


"""
Captures the pattern `calc->stream` into a tuple (calc, stream)
"""
function _capture_calculator_stream(ex)
    # FIXME: What if we need the LineNodes somewhere?
    @match Base.remove_linenums!(ex) begin
        Expr(:->, calc, Expr(:block, stream)) => (calc, stream)
    end
end

# Captures the pattern `c1 => c2->in` into a tuple `(c1, (c2, in))`.
function _capture_big_arrow(ex)
    @match ex begin
        Expr(:call, :(=>), outcalc, stream_arrow_ex) =>
            (outcalc, _capture_calculator_stream(stream_arrow_ex))
    end
end

# [c3->in, c4->in, ...] => ((c3,in), (c4, in), ...)
function _match_elements(ex)
    @match ex begin
        [] => ()
        [first, rest...] => (_capture_calculator_stream(first), _match_elements(rest)...)
    end
end

function _defstreams(ex)
    # e.g. For input: c1 => c2->in_stream, c3->other_in_stream
    # streams == (:c1, (:c2, :in_stream), (:c3, :other_in_stream))
    streams = @match ex begin
        Expr(:tuple, big_arrow_ex, other_streams...) =>
            (_capture_big_arrow(big_arrow_ex)..., _match_elements(other_streams)...)
        ex => _capture_big_arrow(ex)
    end

    source_calc = QuoteNode(streams[1])
    calcs_var = esc(:calcs)

    return quote
        for (calc, in_stream) in $streams[2:end]
            channel = Channel(32)
            # Add to output channel
            push!($calcs_var[$source_calc][2], channel)

            # Add to input channel
            $calcs_var[calc][1][in_stream] = channel
        end
    end
end

macro defstreams(ex)
    return _defstreams(ex)
end