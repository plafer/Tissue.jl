function resolve_process_method(
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

    return quote
        mutable struct $GraphName <: Graph
            named_output_channels::Dict{Symbol,Any}
            source_calculator::CalculatorWrapper
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
                $calcs_var = Dict{Symbol,Any}()
                $named_output_channels_var = Dict{Symbol,Any}()
                calculator_wrappers = []
                $gen_calc_var = nothing

                $(esc(init_block))

                calculator_wrappers = []
                num_sinks_not_init = 0
                for pair in $calcs_var
                    calc_sym, (input_channels_dict, output_channels, calc) = pair

                    input_channels, has_graph_kw =
                        resolve_process_method(typeof(calc), input_channels_dict)

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

                    if isempty(input_channels_dict)
                        if $gen_calc_var !== nothing
                            @error("More than 1 source calculators are defined. You must define one and only one.")
                        end
                        $gen_calc_var = cw
                    end

                end

                if $gen_calc_var === nothing
                    @error("No source calculator defined. You must specify one and only one.")
                end

                lk = Base.ReentrantLock()
                new(
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

"""
    @graph GraphName begin ... end

TODO
"""
macro graph(graph_name, init_block)
    return _graph(graph_name, init_block)
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

"""
    @calculator calculator_handle = CalculatorType(arg1, arg2)

TODO
"""
macro calculator(assign_expr)
    return _calculator(assign_expr)
end

function _capture_bindings(bindings)
    @match bindings begin
        [Expr(:(=), stream, var)] => ((stream, var),)
        [Expr(:(=), stream, var), rest...] => ((stream, var), _capture_bindings(rest)...)
    end
end

"""
    @bindstreams calculator_handle (stream1 = calc1) (stream2 = calc2) ...

TODO
"""
macro bindstreams(input_calculator, binding_exprs...)
    bindings = _capture_bindings([b for b in binding_exprs])

    calcs_var = esc(:calcs)

    #@bindstreams renderer in_frame=source
    # renderer: input channel `in_frame` get populated
    # source: output channel gets populated
    # calcs[calc_sym]: (input_channels, output_channels, calc)
    return quote
        for (in_stream, output_calculator) in $bindings
            channel = Channel(32)
            # Add to output channel
            push!($calcs_var[output_calculator][2], channel)

            # Add to input channel
            $calcs_var[$(QuoteNode(input_calculator))][1][in_stream] = channel
        end
    end
end