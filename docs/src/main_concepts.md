# Main concepts
+ Here, give an extended discussion on the main concepts
    + Flow limiter
    + Bootstrap process
    + process() resolving
    + source and sink streams
    + graph definition DSL
    + Immutability of packets


+ Calculator: a stateful node in the graph which processes inputs to form outputs
    + Source: a special calculator which generates the data stream (e.g. video stream) that will be processed by the graph.
+ Stream: the edges in the graph. 
    + Output stream: 