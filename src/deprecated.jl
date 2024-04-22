# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


macro onallthreads(expr)
    quote
        Base.depwarn("`@onallthreads expr` is deprecated, use `@onthreads allthreads() expr` instead.", nothing)
        @onthreads allthreads() $(esc(expr))
    end
end
export @onallthreads


macro mt_async(expr)
    # Code taken from Base.@async and Base.Threads.@spawn:
    thunk = esc(:(()->($expr)))
    var = esc(Base.sync_varname)
    quote
        Base.depwarn("`@mt_async expr` is deprecated, use `Base.Threads.@spawn expr` instead.", nothing)
        local task = Task($thunk)
        @static if VERSION >= v"1.3.0-alpha.0"
            task.sticky = false
        end
        if $(Expr(:isdefined, var))
            push!($var, task)
        end
        schedule(task)
        task
    end
end
export @mt_async


macro mp_async(expr)
    # Code taken from Distributed.@spawn:
    thunk = esc(:(()->($expr)))
    var = esc(Base.sync_varname)
    quote
        Base.depwarn("`@mp_async expr` is deprecated, use `Distributed.@spawn expr` instead.", nothing)
        local ref = Distributed.spawn_somewhere($thunk)
        if $(Expr(:isdefined, var))
            push!($var, ref)
        end
        ref
    end
end
export @mp_async


@deprecate isdefined_local(x) isassigned(x)
