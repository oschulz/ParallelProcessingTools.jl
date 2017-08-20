# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).


export procs_this
function procs_this()
    pid = myid()
    pid:pid
end


export @everyworker
macro everyworker(expr)
    @static if VERSION < v"0.6.0-"
        expr = Base.localize_vars(esc(:(()->($expr))), false)
        i = gensym("idx")
        quote
            futures = map($i -> Base.spawnat($i, $expr), workers())
            fetch.(futures)
        end
    else
        expr = esc(:(()->($expr)))
        i = gensym("idx")
        quote
            futures = map($i -> Base.Distributed.spawnat($i, $expr), workers())
            fetch.(futures)
        end
    end
end


export onprocs
function onprocs(body, procsel::AbstractVector{<:Integer})
    if procsel == procs_this()
        [body()]
    else
        if (1 in procsel) && (first(workers()) > 1)
            error("Process 1 is not a worker, can't spawn at it")
        end
        futures = map(i -> Base.Distributed.spawnat(i, body), workers())
        fetch.(futures)
    end
end
