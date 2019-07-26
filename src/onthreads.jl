# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


function _current_thread_selected(threadsel::Union{Integer,AbstractVector{<:Integer}})
    tid = threadid()
    checkindex(Bool, tid:tid, threadsel)
end


@static if VERSION >= v"1.3.0-alpha.0"


# From Julia PR 32477:
function _run_on(t::Task, tid)
    @assert !istaskstarted(t)
    t.sticky = true
    ccall(:jl_set_task_tid, Cvoid, (Any, Cint), t, tid-1)
    schedule(t)
    return t
end


# Adapted from Julia PR 32477:
function _threading_run(func, threadsel::AbstractVector{<:Integer})
    tasks = Vector{Task}(undef, length(eachindex(threadsel)))
    for tid in threadsel
        i = firstindex(tasks) + (tid - first(threadsel))
        tasks[i] = _run_on(Task(func), tid)
    end
    foreach(wait, tasks)
    return nothing
end

_threading_run(func, threadsel::Integer) = _threading_run(func, threadsel:threadsel)


function _thread_exec_func(threadsel, expr)
    quote
        local thread_body_wrapper_fun
        let threadsel_eval = $(esc(threadsel))
            function thread_body_wrapper_fun()
                $(esc(expr))
            end
            if _current_thread_selected(threadsel_eval)
                thread_body_wrapper_fun()
            else
                _threading_run(thread_body_wrapper_fun, threadsel_eval)
            end
            nothing
        end
    end
end


else #VERSION < v"1.3.0-alpha.0"


const _thread_local_error_err = ThreadLocal{Any}(undef)
const _thread_local_error_set = ThreadLocal{Bool}(undef)


_clear_thread_local_errors() = fill!(getallvalues(_thread_local_error_set), false)

function _check_thread_local_errors()
    i = something(findfirst(isequal(true), getallvalues(_thread_local_error_set)), 0)
    (i > 0) && throw(getallvalues(_thread_local_error_err)[i])
    nothing
end

function _set_thread_local_error(err)
    _thread_local_error_err[] = err
    _thread_local_error_set[] = true
end

function _check_threadsel(threadsel::Union{Integer,AbstractVector{<:Integer}})
    if !checkindex(Bool, allthreads(), threadsel)
        throw(ArgumentError("Thread selection not within available threads"))
    end
    threadsel
end


function _run_on_threads(f)
    try
        @assert(!Base.Threads.in_threaded_loop[], "Can't nest threaded execution")
        _clear_thread_local_errors()
        Base.Threads.in_threaded_loop[] = true
        ccall(:jl_threading_run, Ref{Cvoid}, (Any,), f)
    finally
        Base.Threads.in_threaded_loop[] = false
        _check_thread_local_errors()
    end
end


function _thread_exec_func(threadsel, expr)
    quote
        local thread_body_wrapper_fun
        let threadsel_eval = $(esc(threadsel))
            function thread_body_wrapper_fun()
                try
                    if Base.Threads.threadid() in threadsel_eval
                        $(esc(expr))
                    end
                catch err
                    _set_thread_local_error(err)
                    rethrow()
                end
            end
            if _current_thread_selected(threadsel_eval)
                thread_body_wrapper_fun()
            else
                _run_on_threads(thread_body_wrapper_fun)
            end
            nothing
        end
    end
end


end # Julia version-dependent code



"""
    allthreads()

Convencience function, returns `1:Base.Threads.nthreads()`.
"""
allthreads() = 1:nthreads()
export allthreads


"""
    @onthreads threadsel expr

Execute code in `expr` in parallel on the threads in `threadsel`.

`threadsel` should be a single thread-ID or a range (or array) of thread-ids.
If `threadsel == Base.Threads.threadid()`, `expr` is run on the current
tread with only minimal overhead.

Note: Currently, multiple `@onthreads` sections will not run in parallel
to each other, even if they use disjunct sets of threads, due to limitations
of the Julia multithreading implementation. This restriction is likely to
disappear in future Julia versions.

In contrast to `Base.Threads.@threads`, `@onthreads` does forward
exceptions to the caller.

Example 1:

```juliaexpr
tlsum = ThreadLocal(0.0)
data = rand(100)
@onthreads allthreads() begin
    tlsum[] = sum(workpart(data, allthreads(), Base.Threads.threadid()))
end
sum(getallvalues(tlsum)) ≈ sum(data)
```

Example 2:

```julia
# Assuming 4 threads:
tl = ThreadLocal(42)
threadsel = 2:3
@onthreads threadsel begin
    tl[] = Base.Threads.threadid()
end
getallvalues(tl)[threadsel] == [2, 3]
getallvalues(tl)[[1,4]] == [42, 42]
```
"""
macro onthreads(threadsel, expr)
    _thread_exec_func(threadsel, expr)
end
export @onthreads


macro onallthreads(expr)
    quote
        Base.depwarn("`@onallthreads expr` is deprecated, use `@onallthreads allthreads() expr` instead.", nothing)
        $(_thread_exec_func(:(ParallelProcessingTools.allthreads()), expr))
    end
end
export @onallthreads


function ThreadLocal{T}(f::Base.Callable) where {T}
    result = ThreadLocal{T}(undef)
    result.value
    @onthreads allthreads() result.value[threadid()] = f()
    result
end
