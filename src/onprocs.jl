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
