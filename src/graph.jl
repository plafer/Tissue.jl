"""
The parent type of all graphs.
"""
abstract type Graph end

function get_generator_calculator_wrapper(graph::Graph)::CalculatorWrapper
    # FIXME: Change name to wrapper
    graph.generator_calculator
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

function get_sinks_lock(graph::Graph)
    graph.sinks_lock
end

function is_last_sink_not_init(graph::Graph)
    is_last = nothing
    lk = get_sinks_lock(graph)

    lock(lk)
    # TODO: Use getter
    graph.num_sinks_not_init -= 1
    if graph.num_sinks_not_init == 0
        is_last = true 
    else
        is_last = false
    end
    unlock(lk)

    return is_last
end

function get_num_sinks_not_init(graph::Graph)
    lk = get_sinks_lock(graph)
    lock(lk)
    ret = graph.num_sinks_not_init
    unlock(lk)

    ret
end

function get_flow_limiter_bootstrap_lock(graph::Graph)
    graph.bootstrap_lock
end

function get_flow_limiter_bootstrap_cond(graph::Graph)
    graph.bootstrap_cond
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
    MIN_SLEEPABLE_TIME = 0.001
    graph.gen_period[] = max(MIN_SLEEPABLE_TIME, period)
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
end
