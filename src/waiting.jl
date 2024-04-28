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
    @wait_while(cond)

Wait while `cond` is true, using slowly increasing sleep times in between
evaluating `cond`.

`cond` may be an arbitrary Julia expression.

Example, wait for a task with a timeout:

```julia
task = Threads.@spawn sleep(10)
timer = Timer(2)
@wait_while !istaskdone(task) && isopen(timer)
istaskdone(task) == false
```
"""
macro wait_while(cond)
    quote
        t_start = time_ns()
        while $(esc(cond))
            t_waited = signed(time_ns() -t_start)
            # Wait again for 12.5% of the time waited so far, but for 1 second
            # at most:
            t_sleep = min(t_waited >> 3, Int64(1000000000))
            sleep_ns(t_sleep)
        end
    end
end
export @wait_while


"""
    wait_for_any(objs...)

Wait for any of the objects `objs` to become ready.

Readiness of objects is as defined by [`wouldwait`](@ref).

Example, wait for a task with a timeout:

```julia
task = Threads.@spawn sleep(10)
timer = Timer(2)
wait_for_any(timer, task)
istaskdone(task) == false
```

Similar to `waitany` (new in Julia v1.12), but applies to a wider range of
object types.
"""
function wait_for_any(objs...)
    @wait_while all(wouldwait, objs)
end
export wait_for_any

# ToDo: Use `waitany` (Julia >= v1.12) in wait_for_any implementation where possible.


"""
    wait_for_all(objs...)

Wait for all of the objects `objs` to become ready.

Readiness of objects is as defined by [`wouldwait`](@ref).

Example, wait for two tasks to finish:

```julia
task1 = Threads.@spawn sleep(10)
task2 = Threads.@spawn sleep(2)
wait_for_all(task1, task2)
```
"""
function wait_for_all(objs...)
    if any(wouldwait, objs)
        map(wait, objs)
    end
    @assert !any(wouldwait, objs)
end
export wait_for_all
