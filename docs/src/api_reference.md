# API reference
## Exported functions
```@autodocs
Modules = [Tissue]
Private = false
Order   = [:function, :type]
```

## Exported macros
```@docs
Tissue.@graph(graph_name, init_block)
```

```@docs
Tissue.@calculator(assign_expr)
```

```@docs
Tissue.@bindstreams(calculator_handle, binding_exprs)
```

## Functions to be implemented by user
```@docs
Tissue.process(calculator)
```

```@docs
Tissue.close(calculator)
```
