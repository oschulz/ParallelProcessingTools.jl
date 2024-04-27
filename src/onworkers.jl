# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


"""
    TimelimitExceeded <: Exception

Exception thrown something timed out.
"""
struct TimelimitExceeded <: Exception
    max_time::Float64
    elapsed_time::Float64
end


"""
    MaxTriesExceeded <: Exception

Exception thrown when a number of (re-)tries was exceeded.
"""
struct MaxTriesExceeded <: Exception
    max_tries::Int
    n_tries::Int
    retry_reason::Exception
end


struct _ActivityThunk
    body::Function
    result_ch::Channel{Any}
    label::String
    max_runtime::Float64
    max_tries::Int
    n_tries::Int
end

function _next_try!!(activity::_ActivityThunk)
    _ActivityThunk(
        activity.body, activity.result_ch, activity.label,
        activity.max_runtime, activity.max_tries, activity.n_tries + 1
    )
end

function _return_result!(@nospecialize(activity::_ActivityThunk), @nospecialize(result::Any))
    put!(activity.result_ch, result)
    return nothing
end

function Base.show(io::IO, activity::_ActivityThunk)
    print(io, "activity ")
    if isempty(activity.label)
        print(io, " ", nameof(typeof(activity.body)))
    else
        print(io, " \"$(activity.label)\"")
    end
    if activity.n_tries > 1 && activity.max_tries > 1
        print(io, " (try $(activity.n_tries) of $(activity.max_tries))")
    end
end


struct _SchedulerNewWorkers
    new_workers::Vector{Int}
end


struct _SchedulerJob
    activity::_ActivityThunk
    result::Future
    started::Float64
end



struct _WorkerScheduler
    all_workers::Set{Int}
    free_workers::Set{Int}
    active_work::IdDict{Int,_SchedulerJob}
    dispatch_ch::Channel{_ActivityThunk}
    maintenance_ch::Channel{_SchedulerNewWorkers}
end

function Base.show(io::IO, sched::_WorkerScheduler)
    print(io, "ParallelProcessingTools._WorkerScheduler (")
    print(io, length(sched.all_workers), " workers, ")
    print(io, length(sched.free_workers), " free, ")
    print(io, length(sched.active_work), " busy)")
end



function _WorkerScheduler(workerprocs::Vector{Int})
    all_workers = Set(copy(workerprocs))
    free_workers = copy(all_workers)
    active_work = IdDict{Int,_SchedulerJob}()
    dispatch_ch = Channel{_ActivityThunk}(1000)
    maintenance_ch = Channel{_SchedulerNewWorkers}(10)

    sched = _WorkerScheduler(
        all_workers, free_workers, active_work,
        dispatch_ch, maintenance_ch
    )    

    task = Task(() -> _worker_scheduler_loop(sched))
    bind(sched.dispatch_ch, task)
    bind(sched.maintenance_ch, task)

    task.sticky = false
    schedule(task)
    yield()

    return sched
end


function _worker_scheduler_step(sched::_WorkerScheduler)
    main_proc = Distributed.myid()
    did_something::Bool = false

    if !isopen(sched.dispatch_ch)
        @error "Worker scheduler dispatch channel was closed unexpectedly"
    end
    if !isopen(sched.maintenance_ch)
        @error "Worker scheduler maintenance channel was closed unexpectedly"
    end

    while isready(sched.maintenance_ch)
        did_something = true
        msg = take!(sched.maintenance_ch)
        @assert msg isa _SchedulerNewWorkers
        new_workers = Set(msg.new_workers)
        union!(sched.all_workers, new_workers)
        union!(sched.free_workers, new_workers)
        @info "Added $(length(new_workers)) new worker processes to scheduler"
    end

    if main_proc in sched.free_workers && length(sched.free_workers) > 1
        did_something = true
        delete!(sched.all_workers, main_proc)
        delete!(sched.free_workers, main_proc)
        @info "Removing main process $main_proc from free workers since other workers are now available"
    end
    if isempty(sched.free_workers) && isempty(sched.active_work)
        did_something = true
        @assert isempty(sched.all_workers)
        @warn "No workers left, adding main process $main_proc back to workers pool"
        push!(sched.all_workers, main_proc)
        push!(sched.free_workers, main_proc)
    end

    while isready(sched.dispatch_ch) && !isempty(sched.free_workers)
        did_something = true
        activity = take!(sched.dispatch_ch)
        worker = first(sched.free_workers)
        try
            @debug "Dispatching $activity to worker $worker"
            result = remotecall(activity.body, worker)
            job = _SchedulerJob(activity, result, time())
            sched.active_work[worker] = job
            delete!(sched.free_workers, worker)
        catch err
            if err isa ProcessExitedException
                @warn "Worker $worker is gone, rescheduling $activity"
                _purge_worker!(sched, worker)
                _reschedule_activity!(sched, activity)
            else
                rethrow()
            end
        end
    end

    busy_workers = collect(keys(sched.active_work))
    for worker in busy_workers
        did_something = true
        job = sched.active_work[worker]
        activity = job.activity
        elapsed_time = time() - job.started
        try
            result_isready = try
                isready(job.result)
            catch err
                @warn "Exception during test if $activity terminated on worker $worker" err
                rethrow()
            end
            if result_isready
                @debug "Worker $worker finished running $activity, marking worker as free"
                delete!(sched.active_work, worker)
                push!(sched.free_workers, worker)

                # With a `remotecall` to the current process, fetch will return exceptions
                # originating in the called function, while if run on a remote process they
                # will be thrown to the caller of fetch. We need to unify this behavior:
                fetched_result = try
                    fetch(job.result)
                catch err
                    if err isa RemoteException
                        @debug "Running $activity on worker $worker resulted in RemoteException" err
                    else
                        @error "Running $activity on worker $worker resulted in unexpected exception" err
                    end
                    err
                end
                if _should_retry(fetched_result)
                    _schedule_activity!(sched, activity, fetched_result)
                else
                    _return_result!(activity, fetched_result)
                end
            elseif activity.max_runtime > 0 && elapsed_time > activity.max_runtime
                @warn "Work on worker $worker timed out after $elapsed_time s (max runtime $(activity.max_runtime))"
                delete!(sched.active_work, worker)
                if worker == main_proc
                    @info "Will not terminate main process $worker, marking it as free even though it may still running timed-out activity"
                    # We don't want to kill the main process, so we declare it
                    # free again, even though it's probably still working on the
                    # activity:
                    push!(sched.free_workers, worker)
                else
                    @info "Terminating worker $worker due to activity timeout"
                    delete!(sched.all_workers, worker)
                    # Kill the worker process. Should find a way to make an elastic worker restart.
                    killworkers(worker)
                end
                _schedule_activity!(sched, activity, TimelimitExceeded(activity.max_runtime, elapsed_time))
            end
        catch err
            if err isa ProcessExitedException
                @warn "Worker $worker terminated during $activity, removing it from scheduler"
                _purge_worker!(sched, worker)
                _schedule_activity!(sched, activity, err)
            else
                @error "Encountered unexpected exception in worker scheduler, running $activity on worker $worker" err
                rethrow()
            end
        end
    end
    return did_something
end


_should_retry(::Any) = false
_should_retry(::Exception) = false
_should_retry(::TimelimitExceeded) = true
_should_retry(err::RemoteException) = _should_retry(err.captured.ex)


const _g_worker_scheduler_sleep_interval = 10e-6 # 10 microseconds
const _g_worker_scheduler_max_sleep_time = 1000e-6 # 1000 microseconds


function _worker_scheduler_loop(sched::_WorkerScheduler)
    idle_count::Int = 0
    @info "Worker scheduler started"
    try
        while isopen(sched.dispatch_ch)
            did_something = _worker_scheduler_step(sched)
            idle_count = did_something ? 0 : idle_count + 1
            idle_sleep(idle_count, _g_worker_scheduler_sleep_interval, _g_worker_scheduler_max_sleep_time)
        end
        @info "Worker scheduler shutting down gracefully"
    catch err
        if err isa InterruptException
            @info "Worker scheduler interrupted and shutting down"
        elseif err isa EOFError
            # Seems to happen if Julia exits?
            @warn "Worker scheduler shutting by EOFError"
        else
            @error "Worker scheduler crashing due to unhandled exception" err
            rethrow()
        end
    end
    return nothing
end


function _purge_worker!(sched::_WorkerScheduler, worker::Int)
    worker in sched.all_workers && delete!(sched.all_workers, worker)
    worker in sched.free_workers && delete!(sched.free_workers, worker)
    haskey(sched.active_work, worker) && delete!(sched.active_work, worker)
end


function _schedule_activity!(sched::_WorkerScheduler, activity::_ActivityThunk, @nospecialize(reason::Union{Exception,Nothing} = nothing))
    if activity.n_tries < activity.max_tries
        scheduled_activity = _next_try!!(activity)
        if scheduled_activity.n_tries > 1
            if !isnothing(reason)
                @debug "Rescheduling $activity due to $reason"
            else
                @debug "Rescheduling $activity"
            end
        end
        if isopen(sched.dispatch_ch)
            put!(sched.dispatch_ch, scheduled_activity)
        else
            throw(ErrorException("Worker scheduler seems to have crashed"))
        end
    else
        if activity.max_tries == 1
            _return_result!(activity, reason)
        else
            _return_result!(activity, MaxTriesExceeded(activity.max_tries, activity.n_tries, reason))
        end
    end
end


# Just reschedule, doesn't increment n_tries, don't abort activity:
function _reschedule_activity!(sched::_WorkerScheduler, activity::_ActivityThunk)
    if !isopen(sched.dispatch_ch)
        @error "Worker scheduler dispatch channel closed unexpectedly"
    end
    put!(sched.dispatch_ch, activity)
end


const _g_worker_scheduler = Ref{Union{_WorkerScheduler,Nothing}}(nothing)
const _g_worker_scheduler_lock = ReentrantLock()

function _get_worker_scheduler()
    lock(_g_worker_scheduler_lock)
    sched = _g_worker_scheduler[]
    unlock(_g_worker_scheduler_lock)
    if !isnothing(sched)
        return sched
    else
        try
            lock(_g_processops_lock)
            try
                lock(_g_worker_scheduler_lock)
                new_sched = _WorkerScheduler(Distributed.workers())
                _g_worker_scheduler[] = new_sched
                return new_sched
            finally
                unlock(_g_worker_scheduler_lock)
            end
        finally
            unlock(_g_processops_lock)
        end
    end
end


function _add_workers_to_scheduler!(sched::_WorkerScheduler, new_workers::Vector{Int})
    put!(sched.maintenance_ch, _SchedulerNewWorkers(new_workers))
end

function _maybe_add_workers_to_scheduler(new_workers::Vector{Int})
    try
        lock(_g_worker_scheduler_lock)
        sched = _g_worker_scheduler[]
        if !isnothing(sched)
            _add_workers_to_scheduler!(sched, new_workers)
        end
    finally
        unlock(_g_worker_scheduler_lock)
    end
end


function Base.close(sched::_WorkerScheduler)
    close(sched.dispatch_ch)
    try
        lock(_g_worker_scheduler_lock)
        if _g_worker_scheduler[] === sched
            _g_worker_scheduler[] = nothing
        end
    finally
        unlock(_g_worker_scheduler_lock)
    end
end

atexit() do 
    if !isnothing(_g_worker_scheduler[])
        close(_g_worker_scheduler[].dispatch_ch)
    end
end


@static if VERSION >= v"1.9"

"""
    on_free_worker(f::Function, args..., time::Real = 0, tries::Integer = 1)

Runs `f(args...)` on a worker process that is not busy and return the result.

If `time > 0`, a maximum runtime for the activity is set. If the activity takes longer
than `time` seconds, the process running it (if not the main process) will be
terminated.

If a problem occurs (timeout or otherwise) while running the activity, reschedules
the taks if the maximum number of tries has not yet been reached, otherwise
throws an exception.

!!! compat "Compatibility"
    Requires Julia v1.9
"""
function on_free_worker end
export on_free_worker

function on_free_worker(
    f::Function;
    @nospecialize(time::Real = 0), @nospecialize(tries::Integer = 1), @nospecialize(label::AbstractString = "")
)
    R = _return_type(f, ())
    untyped_result = _on_free_worker_impl_(f, Float64(time), Int(tries), String(label))
    return convert(R, untyped_result)::R
end

function on_free_worker(
    f::Function, arg1, args...;
    @nospecialize(time::Real = 0), @nospecialize(tries::Integer = 1), @nospecialize(label::AbstractString = "")
)
    all_args = (arg1, args...)
    R = _return_type(f, all_args)
    f_withargs = () -> f(all_args...)
    untyped_result = _on_free_worker_impl_(f_withargs, Float64(time), Int(tries), String(label))
    return convert(R, untyped_result)::R
end

_return_type(f, args::Tuple) = Core.Compiler.return_type(f, typeof(args))

@noinline function _on_free_worker_impl_(
    @nospecialize(f::Function), time::Float64, tries::Int, label::String
)
    sched = _get_worker_scheduler()
    result_ch = Channel{Any}()
    activity = _ActivityThunk(f, result_ch, label, time, tries, 0)
    _schedule_activity!(sched, activity)
    result = take!(result_ch)
    if result isa Exception
        throw(result)
    else
        return result
    end
    throw(ArgumentError("tries must be greater than zero"))
end

end # Julia >= v1.9
