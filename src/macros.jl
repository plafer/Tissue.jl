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
    @graph <GraphName> begin ... end

Define a graph with a topology as specified in the `begin ... end` block.

This defines a `struct <GraphName>` with a constructor that takes no arguments. In the `begin ... end` block, use [`@calculator`](@ref) to define a calculator and [`@bindstreams`](@ref) to bind the input streams of a calculator to the output streams of other calculators. All [`@calculator`](@ref) declarations must come before any [`@bindstreams`](@ref) declaration.

# Examples

```julia
using Tissue

struct SourceCalculator end
Tissue.process(c::SourceCalculator) = 42

struct WorkerCalculator end
function Tissue.process(c::WorkerCalculator, num)
    out = do_work(in_num)
    println(out)
end

@graph NumberGraph begin
    # 1. Declare calculators.
    @calculator source  = SourceCalculator()
    @calculator worker  = WorkerCalculator()

    # 2. Declare the streams which connects the source to the worker
    @bindstreams worker (num = source)
end

graph = NumberGraph()
```

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
    @calculator calculator_handle = MyCalculator(arg1, arg2)

Create a calculator node in a graph.

Marks the `calculator_handle` variable as a new calculator constructed by `MyCalculator(arg1, arg2)`, a user-defined struct. `calculator_handle` can then be used in a [`@bindstreams`](@ref) declaration to bind its input streams to the output streams of other calculators in the graph.

There must be one and only one *source* calculator in a graph. The *source* calculator of a graph is the only calculator which has no input streams. It is called the *source* calculator because it generates the data that will be processed by the rest of the graph.

Must be used in the `begin ... end` block of [`@graph`](@ref), before all [`@bindstreams`](@ref).

# Examples
```julia
using Tissue

mutable struct MySourceCalculator
    last::Int64
    MySourceCalculator() = new(0)
end

function Tissue.process(c::MySourceCalculator)
    c.last += 1

    c.last
end

struct SinkCalculator end
function Tissue.process(c::SinkCalculator, number_stream)
    println(num)
end

@graph PrinterGraph begin
    @calculator source = MySourceCalculator()
    @calculator sink = SinkCalculator()

    @bindstreams sink (number_stream = source)
end
```
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

Bind the streams of `calculator_handle` to the output stream of other calculators in the graph.

Multiple [`Tissue.process(calc)`](@ref) can be implemented for the same calculator type. `@bindstreams` selects the [`Tissue.process(calc)`](@ref) method to be used for calculator `calculator_handle` in this graph based on which named input streams are bound, and binds the output stream of the specified calculators to these input streams.

`calculator_handle`, `calc1` and `calc2` are variables that were assigned to inside a [`@calculator`](@ref) declaration. `stream1` and `stream2` are named streams that were defined in a `process(c::CalculatorType, stream1, stream2)` method definition.

Must be used in the `begin ... end` block of [`@graph`](@ref), after all [`@calculator`](@ref) declarations.

# Examples
```julia
using Tissue

struct SourceCalculator end
Tissue.process(c::SourceCalculator) = 42

struct MyCalculator end

# This method will be selected by the `@bindstreams` declaration
function Tissue.process(c::MyCalculator, stream1::Number)
    println(stream1)
    stream1
end

# This method will not be selected
function Tissue.process(c::MyCalculator, stream1::Number, stream2::Number)
    sum = stream1 + stream2
    println(sum)
    sum
end

# This method will not be selected
function Tissue.process(c::MyCalculator, stream1::Number, stream2::Number, stream3::Number)
    sum = stream1 + stream2 + stream3
    println(sum)
    sum
end

@graph MyGraph begin
    @calculator source = SourceCalculator()
    @calculator mycalc = MyCalculator()

    @bindstreams mycalc (stream1 = source)
end
```
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