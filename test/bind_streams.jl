# Tests that Tissue.jl selects the correct `process()` based on what streams were bound with @bindstreams

using Tissue
import Tissue as T

mutable struct TheCalculator <: CalculatorBase 
    done::Bool
    TheCalculator() = new(false)
end

the_value = -1

function T.process(c::TheCalculator)
    if c.done
        return nothing
    end

    c.done = true

    return 42
end

function T.process(c::TheCalculator, one)
    global the_value
    the_value = 1
end

T.process(c::TheCalculator, two, three) = begin
    global the_value
    the_value = 23
end

@graph Graph1 begin
     @calculator generator = TheCalculator()
     @calculator calc = TheCalculator()

     @bindstreams calc (one = generator)
end

graph1 = Graph1()
start(graph1)
wait_until_done(graph1)

@test the_value == 1

@graph Graph2 begin
     @calculator generator = TheCalculator()
     @calculator calc = TheCalculator()

     @bindstreams calc (two = generator) (three = generator)
end

graph2 = Graph2()
start(graph2)
wait_until_done(graph2)

@test the_value == 23