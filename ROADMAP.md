# 0.2.0
- [ ] Macro: `@bindstreams`
- [ ] Rethink the bootstrap of the flow limiter
    + takes a few seconds to get to limiting fps
    + BUG: If a packet is dropped on the first run of a graph, the graph just hangs.
- [ ] Rethink the generator calculator and registering callbacks
    + The generator calculator is not a real calculator (not taken into account for the flow limiter, and separate macro needed)
    + registered callbacks are not taken into account for the flow limiter. If they don't run fast enough, channels will get clobbered.