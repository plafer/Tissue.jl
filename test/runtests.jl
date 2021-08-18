using SafeTestsets

@safetestset "Graph topology" begin include("graph.jl") end
@safetestset "Packet drop"    begin include("packet_drop.jl") end