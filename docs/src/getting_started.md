# Getting Started

## A simple example

We will build a graph with the following topology.

![Example graph](img/example_graph.jpg)

The corresponding code to build that graph would be:
```jldoctest
using Tissue

mutable struct SourceCalculator 
    count::Int64
    SourceCalculator() = new(0)
end

function Tissue.process(c::SourceCalculator)
    c.count += 1
    if c.count > 5
        # Indicates that the data stream is closed.
        # This is the last time that the function will be called
        return nothing
    end

    return c.count
end

struct AddConstantCalculator
    constant::Int
end

function Tissue.process(c::AddConstantCalculator, num_in::Int)::Int
    return num_in + c.constant
end

struct MultiplyCalculator end

function Tissue.process(c::MultiplyCalculator, first_num::Int, second_num::Int)::Int
    return first_num * second_num
end

struct PrinterCalculator end

function Tissue.process(c::PrinterCalculator, num_to_print)
    println(num_to_print)
end

@graph NumberGraph begin
    # 1. Declare calculators.
    @calculator source  = SourceCalculator()
    @calculator add0    = AddConstantCalculator(0)
    @calculator add42   = AddConstantCalculator(42)
    @calculator mult    = MultiplyCalculator()
    @calculator printer = PrinterCalculator()

    # 2. Declare the streams which connect the calculators together
    @bindstreams add0 (num_in = source)
    @bindstreams add42 (num_in = source)
    @bindstreams mult (first_num = add0) (second_num = add42)
    @bindstreams printer (num_to_print = mult)
end

graph = NumberGraph()
start(graph)
wait_until_done(graph)

# output
43
88
135
184
235
```

There's a lot going on here, so let's parse through this example one bit at a time.

```julia
using Tissue
```
This brings the functions and macros we are going to need into scope: 

+ `start()` launches all the calculators, each in its own task, and starts pulling data from the *source* calculator
+ `wait_until_done()` blocks the main thread until the source stops generating data, and all calculators are done processing.
+ `@graph` defines a graph, concretely a `struct NumberGraph`, with a topology as described in the `begin ... end` block.
+ `@calculator` declares a new node in the graph corresponding to a calculator object of any type.
+ `@bindstreams` declares the edges in the graph. To define an edge, one specifies the output of a calculator with a named input stream of another calculator.

```julia
mutable struct SourceCalculator 
    count::Int64
    SourceCalculator() = new(0)
end
```
This defines a calculator type which we will use to instantiate our *source* calculator. The source calculator is the one and only node in the graph which has no input streams. It is equally an error to instantiate more than one, or none at all. As you can see, there's nothing special about the type. More on the source calculator when we get to the graph definition.

```julia
function Tissue.process(c::SourceCalculator)
    c.count += 1
    if c.count > 5
        # Indicates that the data stream is closed.
        # This is the last time that the function will be called
        return nothing
    end

    return c.count
end
```
This is the crux of it all. We specify how a calculator of type `X` goes from input to output by adding a method to the `Tissue.process()` function; that is, the `process()` function that lives in the `Tissue` module. The convention is that the first argument to the function needs to be of type `X`, and the rest of the arguments define the streams which the calculator accepts. In this case, there are no streams, because we intend to use this calculator as our source calculator.

Note that more than one `Tissue.process(c::X, ...)` can be implemented. This is how you let the same calculator accept different streams, depending on the graph it is to be used in.


```julia
struct AddConstantCalculator
    constant::Int
end

function Tissue.process(c::AddConstantCalculator, num_in::Int)::Int
    return num_in + c.constant
end
```
We define a new calculator type called `AddConstantCalculator`. There is one difference with the source calculator though: its `process()` method accepts one stream named `num_in`. This is key. The name of the arguments in a `process()` method matter. They name a stream that will later be used when defining the graph topology with the `@graph` and `@bindstreams` macros. More on this later.

Here, we specified the type of the stream and the return type of `process()` for documentation purposes; they are by no means required.

```julia
struct MultiplyCalculator end

function Tissue.process(c::MultiplyCalculator, first_num::Int, second_num::Int)::Int
    return first_num * second_num
end
```
We define a new calculator type called `MultiplyCalculator`, as well as a `process()` which now takes 2 stream arguments. This is interesting. Remember that all calculators in the graph run concurrently. Then, both values are going to arrive at this calculator at different points in time. As a result, Tissue.jl buffers the data until at least one packet per stream has arrived, after which it calls this `process()` method. This complexity taken care for you is one of the perks of Tissue.jl.

```julia
struct PrinterCalculator end

function Tissue.process(c::PrinterCalculator, num_to_print)
    println(num_to_print)
end
```
Come to our final calculator type, `PrinterCalculator`. Nothing new here, except to show that really, all computation, including I/O calls, happens within calculators.

```julia
@graph NumberGraph begin
```
Finally, we get to the graph definition. The `@graph` macro takes 2 arguments: The name of the type, `NumberGraph`, and a code block in which we use `@calculator` and `@bindstreams` to define the topology; that is, the nodes and edges of the graph.

```julia
    # 1. Declare calculators.
    @calculator source  = SourceCalculator()
```
This defines a new calculator object of type `SourceCalculator`, and `source` is the variable that refers to it. This looks like and is a simple variable assignment as you know it, using the `SourceCalculator` struct constructor that you defined. The default one in this case.

```julia
    @calculator add0    = AddConstantCalculator(0)
    @calculator add42   = AddConstantCalculator(42)
    @calculator mult    = MultiplyCalculator()
    @calculator printer = PrinterCalculator()
```
Similarly, this defines four new calculator objects. Note that `add0` and `add42` are two calculators of the same type.

```julia
    # 2. Declare the streams which connect the calculators together
    @bindstreams add0 (num_in = source)
```
We get to our first `@bindstreams` declaration. The purpose of `@bindstreams` is to encode, for each calculator in our graph, where the data comes from for each stream. Here, the `add0`'s input stream called `num_in` will have its data come from the output stream of `source`. The parentheses around `num_in = source` are optional; we add them for clarity. Visually, this adds an edge in the graph from `source` to `add0`. As a reminder, we declared the stream `num_in` when we defined the `process(c::AddConstantCalculator, num_in::Int)` method.

```julia
    @bindstreams add42 (num_in = source)
```
This declaration is analogous to the previous one.

```julia
    @bindstreams mult (first_num = add0) (second_num = add42)
```
The `process()` method that we defined for the `MultiplyCalculator` defines two streams: `first_num` and `second_num`. Therefore, the `@bindstreams` declaration must bind the output of a calculator to each of them. By now, you probably figured out what this does: it takes the output of `add0` and sends it in `mult`'s `first_num` stream, and similarly for `add42` in the `second_num` stream.

```julia
    @bindstreams printer (num_to_print = mult)
end
```
This is the final `@bindstreams` declaration, which completes the graph definition! We defined all of our calculators and how they interact. Note that we didn't bind any stream to `source`, which tells `Tissue.jl` that this is the calculator we intend to use as our *source* calculator.

```julia
graph = NumberGraph()
```
We now get to actually use our graph! The `@graph` macro created a `struct NumberGraph` with a default constructor. We thus instantiate a new graph simply by creating an object of type `NumberGraph`.

```julia
start(graph)
```
This call starts every calculator in its own task and starts pulling data from the *source* calculator. It returns immediately.

```julia
wait_until_done(graph)
```
Finally, this blocks the main thread until the graph is done. In our case, this happens when our *source* returns `nothing`, indicating that it is done generating data. `wait_until_done` will wait until all the calculators are finished processing the last packet, cleanup and return.

That's all folks! Now, there's a thing or two we omitted in this example, so if you're hungry for more, follow me on to a more complicated example.

## A more complicated example

TODO: Show the use of `close()`, `stop()`, and the `;graph` kw argument to `process()`
TODO: You need to launch julia with as many threads as you want
TODO: Talk about immutability
TODO: talk about stream and sink
TODO: Replace the talk of "in parallel" with "concurrently"
TODO: Talk about when packets are being dropped
TODO: What about spawning your own tasks within calculators?