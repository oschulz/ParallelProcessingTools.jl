# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

const _g_yield_time_ns = Int64(250) # typical time for a `yield()`
const _g_sleep_0_time_ns = Int64(1500) # typical time for a `sleep(0)`
const _g_sleep_t_time_ns = Int64(2000000) # typical minimum time for a `sleep(t)`

const _g_sleep_n_yield = 3 * div(_g_sleep_0_time_ns, _g_yield_time_ns)
const _g_sleep_n_sleep_0 = 3 * div(_g_sleep_t_time_ns, _g_sleep_0_time_ns)
const _g_sleep_yield_threshold = 3 * _g_sleep_0_time_ns
const _g_sleep_sleep_0_threshold = 3 * _g_sleep_t_time_ns

"""
    sleep_ns(t_in_ns::Real)

Sleep for `t_in_ns` nanoseconds, using a mixture of `yield()`, `sleep(0)`
and `sleep(t)` to be able sleep for short times as well as long times with
good relative precision.

Guaranteed to `yield()` at least once, even if `t_in_ns` is zero.
"""
function sleep_ns(t_in_ns::Integer)
    t_ns = Int64(t_in_ns)
    t_remaining_ns::Int64 = t_ns
    t0 = time_ns()
    yield()
    if t_remaining_ns <= _g_sleep_yield_threshold
        for _ in 1:_g_sleep_n_yield
            t_slept = Int64(time_ns() - t0)
            t_remaining_ns = t_ns - t_slept
            t_remaining_ns > 0 || return nothing
            yield()
        end
    end
    if t_remaining_ns <= _g_sleep_sleep_0_threshold
        for _ in 1:_g_sleep_n_sleep_0
            t_slept = Int64(time_ns() - t0)
            t_remaining_ns = t_ns - t_slept
            t_remaining_ns > 0 || return nothing
            sleep(0)
        end
    end
    if t_remaining_ns > 0
        t_remaining_s = 1e-9 * t_remaining_ns
        sleep(t_remaining_s)
    end
    return nothing
end
export sleep_ns


"""
    idle_sleep(n_idle::Integer, t_interval_s, t_max_s)

Sleep due to something haven't been idle for `n_idle` times.

Will sleep for `log2(n_idle + 1) * t_interval_s` seconds, but at most for
`t_max_s` seconds.

Guaranteed `yield()` at least once, even if `n_idle` is zero.
"""
function idle_sleep(n_idle::Integer, t_interval_s::Real, t_max_s::Real)
    sleep_time = min(t_max_s, log2(n_idle + 1) * t_interval_s)
    sleep_time_ns = round(Int64, 1e9 * sleep_time)
    sleep_ns(sleep_time_ns)
end
export idle_sleep


"""
    @wait_while [maxtime=nothing] [timeout_error=false] cond

Wait while `cond` is true, using slowly increasing sleep times in between
evaluating `cond`.

`cond` may be an arbitrary Julia expression.

If `maxtime` is given with an real value, will only wait for `maxtime`
seconds, if the value is zero or negative will not wait at all.

If `timeout_error` is `true`, will throw a `TimelimitExceeded` exception
if the maximum waiting time is exceeded.

Example, wait for a task with a maxtime:

```julia
task = Threads.@spawn sleep(10)
timer = Timer(2)
@wait_while !istaskdone(task) && isopen(timer)
istaskdone(task) == false
```
"""
macro wait_while(args...)
    maxtime = :(nothing)
    timeout_error = :(false)
    for arg in args[begin:end-1]
        if arg isa Expr && arg.head == :(=) && length(arg.args) == 2
            optname, optval = arg.args[1], arg.args[2]
            if optname == :maxtime
                maxtime = optval
            elseif optname == :timeout_error
                timeout_error = optval
            else
                return quote
                    quoted_optname = $(esc(Expr(:quote, optname)))
                    throw(ArgumentError("Invalid option name for @wait_while: $quoted_optname"))
                end
            end
        else
            return quote
                quoted_arg = $(esc(Expr(:quote, arg)))
                throw(ArgumentError("Invalid option format for @wait_while: $quoted_arg"))
            end
        end
    end
    cond = args[end]
    quote
        maxtime_set, maxtime_s, maxtime_ns = _process_maxtime($(esc(maxtime)))
        timeout_error = $(esc(timeout_error))
        t_start = time_ns()
        while $(esc(cond))
            _wait_while_inner(maxtime_set, maxtime_s, maxtime_ns, timeout_error, t_start) || break
        end
        nothing
    end
end
export @wait_while

_process_maxtime(maxtime::Real) = _process_maxtime(Float64(maxtime))
function _process_maxtime(maxtime::Union{Float64,Nothing})
    maxtime_set = !isnothing(maxtime)
    maxtime_s::Float64 = maxtime_set ? max(zero(Float64), maxtime) : zero(Float64)
    maxtime_ns::UInt64 = unsigned(round(Int64, maxtime_s * 1e9))
    return maxtime_set, maxtime_s, maxtime_ns
end

function _wait_while_inner(maxtime_set::Bool, maxtime_s::Float64, maxtime_ns::UInt64, timeout_error::Bool, t_start::UInt64)
    t_waited = time_ns() - t_start
    if maxtime_set && t_waited > maxtime_ns
        if timeout_error
            throw(TimelimitExceeded(maxtime_s, t_waited * 1e-9))
        else
            return false
        end
    end
    # Wait for 12.5% of the time waited so far, but for one second and until maxtime at most:
    max_sleeptime_ns = maxtime_set ? min(maxtime_ns - t_waited, _one_sec_in_ns) : _one_sec_in_ns
    t_sleep = min(t_waited >> 3, max_sleeptime_ns)
    sleep_ns(t_sleep)
    return true
end

const _one_sec_in_ns = Int64(1000000000)


"""
    wait_for_any(
        objs...;
        maxtime::Union{Real,Nothing} = nothing, timeout_error::Bool = false
    )

    wait_for_all(objs::Union{Tuple,AbstractVector,Base.Generator,Base.ValueIterator}; kwargs...)

Wait for any of the objects `objs` to become ready.

Readiness of objects is as defined by [`wouldwait`](@ref). Objects that are
`Nothing` are ignored, i.e. not waited for.

See [`@wait_while`](@ref) for the effects of `maxtime` and `timeout_error`.

Example, wait for a task with a timeout:

```julia
task1 = Threads.@spawn sleep(1.0)
task2 = Threads.@spawn sleep(5.0)
wait_for_any(task1, task2, maxtime = 3.0)
istaskdone(task1) == true
istaskdone(task2) == false
```

Similar to `waitany` (new in Julia v1.12), but applies to a wider range of
object types.
"""
function wait_for_any end
export wait_for_any

function wait_for_any(obj::Any; maxtime::Union{Real,Nothing} = nothing, timeout_error::Bool = false)
    if isnothing(maxtime)
        wait(obj)
    else
        mt, te = maxtime, timeout_error
        @wait_while maxtime=mt timeout_error=te wouldwait(obj)
    end
end

wait_for_any(::Nothing; maxtime::Union{Real,Nothing} = nothing, timeout_error::Bool = false) = nothing

wait_for_any(obj, objs...; kwargs...) = _wait_for_any_in_iterable((obj, objs...); kwargs...)

function wait_for_any(objs::Union{Tuple,AbstractVector,Base.Generator,Base.ValueIterator}; kwargs...)
    _wait_for_any_in_iterable(objs; kwargs...)
end

function _wait_for_any_in_iterable(objs; maxtime::Union{Real,Nothing} = nothing, timeout_error::Bool = false)
    mt, te = maxtime, timeout_error
    @wait_while maxtime=mt timeout_error=te all(wouldwait, objs)
end

# ToDo: Use `waitany` (Julia >= v1.12) in wait_for_any implementation where possible.


"""
    wait_for_all(
        objs...;
        maxtime::Union{Real,Nothing} = nothing, timeout_error::Bool = false
    )

    wait_for_all(objs::Union{Tuple,AbstractVector,Base.Generator,Base.ValueIterator}; kwargs...)

Wait for all of the `objs` to become ready.

Readiness of objects is as defined by [`wouldwait`](@ref). Objects that are
`Nothing` are ignored, i.e. not waited for.

See [`@wait_while`](@ref) for the effects of `maxtime` and `timeout_error`.

Example, wait for two tasks to finish:

```julia
task1 = Threads.@spawn sleep(10)
task2 = Threads.@spawn sleep(2)
wait_for_all(task1, task2)
```
"""
function wait_for_all end
export wait_for_all

wait_for_all(obj; kwargs...) = wait_for_any(obj; kwargs...)

wait_for_all(obj, objs...; kwargs...) = _wait_for_all_in_iterable((obj, objs...); kwargs...)

function wait_for_all(objs::Union{Tuple,AbstractVector,Base.Generator,Base.ValueIterator}; kwargs...)
    _wait_for_all_in_iterable(objs; kwargs...)
end

function _wait_for_all_in_iterable(objs; maxtime::Union{Real,Nothing} = nothing, timeout_error::Bool = false)
    maxtime_set, maxtime_s, maxtime_ns = _process_maxtime(maxtime)
    t_start = time_ns()
    te = timeout_error
    for o in objs
        t_waited_ns = time_ns() - t_start
        maxtime_remaining_ns = maxtime_ns > t_waited_ns ? maxtime_ns - t_waited_ns : zero(maxtime_ns)
        mt = maxtime_set ? maxtime_remaining_ns * 1e-9 : nothing
        @wait_while maxtime=mt timeout_error=te wouldwait(o)
    end
    return nothing
end

function _wait_for_all_in_iterable(objs::Tuple; maxtime::Union{Real,Nothing} = nothing, timeout_error::Bool = false)
    maxtime_set, maxtime_s, maxtime_ns = _process_maxtime(maxtime)
    t_start_ns = time_ns()
    _wait_for_all_in_tuple(objs, t_start_ns, maxtime_set, maxtime_ns, timeout_error)
end


_wait_for_all_in_tuple(::Tuple{}, ::UInt64, ::Bool, ::UInt64, ::Bool) = nothing

function _wait_for_all_in_tuple(objs::Tuple, t_start_ns::UInt64, maxtime_set::Bool, maxtime_ns::UInt64, timeout_error::Bool)
    t_waited_ns = time_ns() - t_start_ns
    maxtime_rest_ns = maxtime_ns > t_waited_ns ? maxtime_ns - t_waited_ns : zero(maxtime_ns)
    mt = maxtime_set ? maxtime_rest_ns * 1e-9 : nothing
    te = timeout_error
    o = objs[1]
    @wait_while maxtime=mt timeout_error=te wouldwait(o)
    _wait_for_all_in_tuple(Base.tail(objs), t_start_ns, maxtime_set, maxtime_ns, timeout_error)
end
