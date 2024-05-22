# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    ParallelProcessingTools.bind_args(f, args...; kwargs...)

Bind some or all arguments of function `f` to `args` and `kwargs`.

Can be used repeatedly. For example:

```julia
f = (a, b, c, d, e; exponent = 2, ) -> x + y + z
```
"""
function bind_args end

@inline bind_args(f, args...; kwargs...) = FuncWithArgs(f, args, NamedTuple(kwargs))


"""
    struct FuncWithArgs{F}

An a function with bound arguments, these may only be some of the arguments
the function takes.

Do no construct directly, us    ntries::Inte [`bind_args`](@ref) instead.
"""
struct FuncWithArgs{F,PA<:Tuple,KA<:NamedTuple}
    f::F
    args::PA
    kwargs::KA
end
export FuncWithArgs

@inline FuncWithArgs(::Type{F}, args, kwargs) where F = FuncWithArgs{Type{F}}(F, args, kwargs)

@inline (fwa::FuncWithArgs)() = fwa.f(fwa.args...; fwa.kwargs...)

@inline function (fwa::FuncWithArgs)(args...; kwargs...)
    all_args = (fwa.args..., args...)
    all_kwargs = merge(fwa.kwargs, kwargs)
    fwa.f(all_args...; all_kwargs...)
end


"""
    PrecisionTime(time_in_seconds::Real)

Represents a precise time (stored in ns internally) with an arbitrary zero
reference. 

`PrecisionTime()` returns the current precision time.

Use `time(t::PrecisionTime)` to get the time in seconds and `time_ns(t)` to get
the time in nanoseconds.
"""
struct PrecisionTime
    ns::Int64

    PrecisionTime() = new(time_ns())
    PrecisionTime(; ns::Integer = 0) = new(ns)
end
export PrecisionTime

PrecisionTime(t::PrecisionTime) = t

Base.time_ns(d::PrecisionTime) = d.ns
Base.time(d::PrecisionTime) = d.ns * 1e-9

Base.:(+)(a::PrecisionTime, b::PrecisionTime) = PrecisionTime(ns = time_ns(a) + time_ns(b))
Base.:(-)(a::PrecisionTime, b::PrecisionTime) = PrecisionTime(ns = time_ns(a) - time_ns(b))

function Base.show(io::IO, t::PrecisionTime)
    print(io, time(t), " s")
end


"""
    struct PId(id::Int)

Represents a Julia process id.
"""
struct PId
    id::Int
end

Base.Int(pid::PId) = pid.id
Base.convert(::Type{Int}) = convert(T, id)




"""
    Activity(
        f::F, label::AbstractString = "";
        maxtime::Float64 = Inf, maxtries::Integer = 1,
        onthreads::Bool = true, onprocs::Bool = false
    ) isa Function

Represents an activity, i.e. a function with a label and information
regarding mode of execution, runtime limit and and retry strategy.
"""
struct Activity{F} <: Function
    f::F
    uuid::UUID
    parent::UUID
    label::String
    maxtime::Union(PrecisionTime, Nothing)
    maxtries::Int
    ntries::Int
    _use_maxtime::Bool
    _onthreads::Bool
    _onprocs::Bool
end

function Activity(
    f::F, label::AbstractString = "";
    maxtime::Float64 = Inf, maxtries::Integer = 1,
    onthreads::Bool = true, onprocs::Bool = false
) where F
    Activity{F}(f, uuidv4(), current_activity_context().uuid, label, maxtime, maxtries, 1, onthreads, onprocs)
end

@inline Activity(::Type{F}, args...; kwargs...) where F = Activity{Type{F}}(F, args...; kwargs...)


(act::Activity)(args...) = _run_activity(act, args...)

function _run_activity(act::Activity, args...)
    if ac.t._onprocs
        return _run_activity_onpool(act, ppt_worker_pool(), args...)
    else
        return _run_activity_here(act, args...)
    end
end


@noinline function _run_acivity_here(act::Activity, pool::AbstractWorkerPool, args:...)
    current_act::typeof(act) = act
    while activity.ntries < activity.maxtries
        current_act = _next_try!!(current_act)
        try
            @debug "Preparing to run $activity, taking a worker from $(getlabel(pool))"
            _try_activity_here(current_act, args...)
        catch err
            #!!!!!!!!!!!!
        end
    end
    # Should never reach this point:
    @assert false
end


@noinline function _run_activity_onpool(act::Activity, pool::AbstractWorkerPool, args:...)
#!!!!!!!!!!!!!!!!!!!!!!
end



@inline function _try_activity_here(act::Activity, args...)
    run_act = bind_args(_try_activity_impl, act, args...)
    return with(run_act, _g_current_activity => act)
end

@inline function _try_activity_remote(act::Activity, pid::Int, args...)
    R = _result_type(act, args)
    # !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    return untyped_result::T
end

@inline _return_type(f, args::Tuple) = Core.Compiler.return_type(f, typeof(args))
@inline _return_type(act::Activity, args::Tuple) = _return_type(act.f, typeof(args))

function _try_activity_impl(act::Activity, args...)
    tries = act.n_tries + 1
    t_start = time_ns()
    try
        value = act.f(args...; kwargs...)
        t_end = time_ns()
        return ActivityResult(value, act.uuid, true, PId(myid()), PrecisionTime(ns = t_end - t_start), tries)
    catch err
        t_end = time_ns()
        return ActivityResult(err, act.uuid, false, PId(myid()), PrecisionTime(ns = t_end - t_start), tries)
    end
end

function Base.show(io::IO, activity::_Activity)
    print(io, "activity ")
    if isempty(activity.label)
        print(io, nameof(typeof(activity.f)))
    else
        print(io, "\"$(activity.label)\"")
    end
end

@inline function bind_args(act::Activity, args...; kwargs...)
    Activity(
        bind_args(act.f, args...; kwargs...),
        act.label, act.max_tries, act.onthreads, act.onprocs
    )
end


struct _ProgressReport
    activity::UUID
    category::Symbol
    labelpatch::Vector{String}
    current::Float64
    comparator::Symbol
    target::Float64
    description::String
end

const _ReportChannel = RemoteChannel{Channel{Vector{_ProgressReport}}}


struct _ActivityContext
    activity::UUID
    labelpath::Vector{String}
    start_time::PrecisionTime
    report_channel::RemoteChannel{Channel{_ProgressReport}}
    report_interval::PrecisionTime
    progress_reports::Vector{_ProgressReport}
    last_report_time::Ref{PrecisionTime}
    lockable::ReentrantLock
end

_is_toplevel_context(ctx::_ActivityContext) = length(ctx.labelpath) == 1

function _ActivityContext(root_act::Activity)
    t = PrecisionTime()
    _ActivityContext(
        root_act.uuid,
        [root_act.label],
        t,
        _default_report_channel(),
        status_display_interval(),
        Vector{_ProgressReport}(),
        Ref(t),
        ReentrantLock(),
    )
end

function _ActivityContext(current_ctx::_ActivityContext, new_act::Activity)
    t = PrecisionTime()
    _ActivityContext(
        new_act.uuid,
        [current_ctx.labelpath..., new_act.label],
        t,
        current_ctx.report_channel,
        current_ctx.report_interval,
        Vector{_ProgressReport}(),
        Ref(t),
        ReentrantLock(),
    )
end

function _push_progress!(ctx::_ActivityContext, report::_ActivityReport)
    @assert ctx.activity == report.activity
    reports = ctx.progress_reports
    lock(ctx.lockable)
    try
        for i in eachindex(reports)
            r = reports[i]
            if r.category == report.category && r.label == report.label
                reports[i] = report
            else
                push!(reports, report)
            end
        end
        t = PrecisionTime()
        if time_ns(t - ctx.last_report_time[]) >= time_ns(ctx.report_interval)
            ctx.last_report_time[] = t
            put!(ctx.report_channel, reports)
            empty!(reports)
        end
    finally
        unlock(ctx.lockable)
    end
    return nothing
end

_new_report_channel() = RemoteChannel(Channel{_ProgressReport}(1000))
_g_report_channel = _ScopedValueWithDynamicDefault{_ReportChannel}(_new_report_channel)
_current_report_channel() = _get_current(_g_report_channel)


function _current_report_channel()
    return _g_report_channel[]
end

function report_finished(act::Activity, success::Bool)
    #!!!!!
end

function report_steps(n::Integer, ntotal::Integer, label::String = "steps")
    #!!!!!
end

function report_progress(x::Integer, target::Integer, label::String = "steps")
    #!!!!!
end

function report_convergence(value::Real, comparison::Function, target::Real, label::String = "convergence")
    #!!!!!
end

function report_value(value::Real, label::String)
    #!!!!!
end

function report_state(state, label::String = "state")
    #!!!!!
end


struct _WrappedActivity{A<:Activity} <: Function
    _act::A
    _report_channel::RemoteChannel{Channel{_ProgressReport}}
end

_WrappedActivity(act::Activity) = _WrappedActivity(act, _current_report_channel())
