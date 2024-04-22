# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


function _current_thread_selected(threadsel::Union{Integer,AbstractVector{<:Integer}})
    tid = threadid()
    checkindex(Bool, tid:tid, threadsel)
end


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


"""
    allthreads()

Convencience function, returns an equivalent of `1:Base.Threads.nthreads()`.
"""
allthreads() = Base.OneTo(Base.Threads.nthreads())
export allthreads


"""
    @onthreads threadsel expr

Execute code in `expr` in parallel on the threads in `threadsel`.

`threadsel` should be a single thread-ID or a range (or array) of thread-ids.
If `threadsel == Base.Threads.threadid()`, `expr` is run on the current
tread with only minimal overhead.

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


function ThreadLocal{T}(f::Base.Callable) where {T}
    result = ThreadLocal{T}(undef)
    result.value
    @onthreads allthreads() result.value[threadid()] = f()
    result
end




"""
    @mt_out_of_order begin expr... end

Runs all top-level expressions in `begin expr... end` on parallel
multi-threaded tasks.

Example:

```
@mt_out_of_order begin
    a = foo()
    bar()
    c = baz()
end

will run `a = foo()`, `bar()` and `c = baz()` in parallel and in arbitrary
order, results of assignments will appear in the outside scope.
"""
macro mt_out_of_order(ex)
    if !(ex isa Expr && ex.head == :block)
        throw(ErrorException("@mt_out_of_order expects a code block as it's argument"))
    end

    exprs = ex.args
    idxs = eachindex(ex.args)
    tasks = gensym(:tasks)
    handle_results = Vector{Expr}()
    for i in idxs
        if exprs[i] isa Expr && exprs[i].head == :(=)
            trg = exprs[i].args[1]
            val = exprs[i].args[2]
            if val isa Expr
                exprs[i] = :(push!($tasks, Base.Threads.@spawn($(esc(val)))))
                push!(handle_results, :($(esc(trg)) = fetch(popfirst!($tasks))))
            else
                exprs[i] = esc(exprs[i])
            end
        elseif exprs[i] isa Expr
            ftvar = gensym()
            exprs[i] = :(push!($tasks, Base.Threads.@spawn($(esc(exprs[i])))))
            push!(handle_results, :(wait(popfirst!($tasks))))
        else
            exprs[i] = esc(exprs[i])
        end
    end
    pushfirst!(exprs, :($tasks = Vector{Task}()))
    append!(exprs, handle_results)
    push!(exprs, :(@assert isempty($tasks)))
    push!(exprs, :nothing)
    ex
end
export @mt_out_of_order
