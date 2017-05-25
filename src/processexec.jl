# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).


export @everyworker
macro everyworker(expr)
    expr = Base.localize_vars(esc(:(()->($expr))), false)
    i = gensym("idx")
    quote
        futures = map($i -> Base.spawnat($i, $expr), workers())
        fetch.(futures)
    end
end
