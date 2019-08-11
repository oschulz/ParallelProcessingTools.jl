# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


_run_on_procs(f, procsel::Integer) = remotecall_fetch(f, procsel)

_run_on_procs(f, procsel::AbstractArray) =
    fetch.([remotecall(f, pid) for pid in procsel])


"""
    @onprocs procsel expr

Executes `expr` in parallel on all processes in `procsel`. Waits until
all processes are done. Returns all results as a vector (or as a single
scalar value, if `procsel` itself is a scalar).

Example:

```julia
using Distributed
addprocs(2)
workers() == @onprocs workers() myid()
```
"""
macro onprocs(procsel, expr)
    f = esc(:(()->($expr)))
    quote
        let procsel = $(esc(procsel)), f = $f
            _run_on_procs(f, procsel)
        end
    end
end
export @onprocs


"""
    @mp_async expr

Run `expr` asynchronously on a worker process.

Compatible with `@sync`.

Equivalent to `Distributed.@spawn expr` on Julia <= v1.2, equivalent to
`Distributed.@spawn :any expr` on Julia >= v1.3.
"""
macro mp_async(expr)
    # Code taken from Distributed.@spawn:
    thunk = esc(:(()->($expr)))
    var = esc(Base.sync_varname)
    quote
        local ref = Distributed.spawn_somewhere($thunk)
        if $(Expr(:isdefined, var))
            push!($var, ref)
        end
        ref
    end
end
export @mp_async


function mtjulia_exe()
    if Sys.islinux()
        joinpath(@__DIR__, "..", "bin", "mtjulia.sh")
    else
        # No equivalent for "mtjulia.sh" implemented for non-Linux systems yet,
        # return default exename:
        joinpath(Sys.BINDIR, Base.julia_exename())
    end
end
export mtjulia_exe
