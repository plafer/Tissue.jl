using SafeTestsets

@safetestset GraphTopo = "Graph topology" begin include("graph.jl") end
@safetestset PacketDrop = "Packet drop"    begin include("packet_drop.jl") end
@safetestset FlowLimiter = "Flow limiter"   begin include("flow_limiter.jl") end
@safetestset BindStreams = "Bind streams" begin include("bind_streams.jl") end

# TODO: test that close() is called
# TODO: test error system once implemented