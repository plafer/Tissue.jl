using Tissue
import Tissue as T

const NUM_ITERATIONS = 5
const TARGET_PERIOD = 0.5


mutable struct TimestampGeneratorCalculator 
    last::Int
    max_gen::Int
    TimestampGeneratorCalculator() = new(1, NUM_ITERATIONS)
end

function T.process(c::TimestampGeneratorCalculator)
    if c.last > c.max_gen
        return nothing
    end

    c.last += 1

    return time()
end

mutable struct PeriodCalculator 
    last_ts::Float64

    PeriodCalculator() = new(-1)
end

function T.process(calc::PeriodCalculator, new_ts::Float64)
    if calc.last_ts == -1
        calc.last_ts = new_ts
        return new_ts
    end

    global latest_period
    latest_period = new_ts - calc.last_ts

    calc.last_ts = new_ts

    new_ts
end

struct SleeperCalculator
    "Sleep time in seconds"
    sleep_time::Float64
end

function T.process(calc::SleeperCalculator, in_num)
    sleep(calc.sleep_time)

    in_num
end

@graph SleeperGraph begin
    @calculator generator = TimestampGeneratorCalculator()
    @calculator period = PeriodCalculator()
    @calculator sleeper = SleeperCalculator(TARGET_PERIOD)

    @bindstreams period (new_ts = generator)
    @bindstreams sleeper (in_num = generator)
end

graph = SleeperGraph()

T.start(graph)
T.wait_until_done(graph)

@test isapprox(latest_period, TARGET_PERIOD; rtol=0.1)