# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).


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
