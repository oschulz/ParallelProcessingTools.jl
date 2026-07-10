# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


"""
    TimelimitExceeded <: Exception

Exception thrown when something times out.
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


_should_retry(::Any) = false
_should_retry(::Exception) = false
_should_retry(::TimelimitExceeded) = true
_should_retry(err::RemoteException) = _should_retry(err.captured.ex)


"""
    onworker(
        f::Function, args...;
        pool::AbstractWorkerPool = ppt_worker_pool(),
        maxtime::Real = 0, tries::Integer = 1, label::AbstractString = ""
    )

Runs `f(args...)` on an available worker process from the given `pool` and
returns the result.

If `maxtime > 0`, a maximum time for the activity is set. If the activity takes longer
than `maxtime` seconds, the process running it (if not the main process) will be
terminated.

`label` is used for debug-logging.

If a problem occurs (maxtime or worker failure) while running the activity,
reschedules the task if the maximum number of tries has not yet been reached,
otherwise throws an exception. Worker failures do not count against `tries`,
but only up to `3 * tries` worker failures are tolerated.
"""
function onworker(
    f::Function, args...;
    @nospecialize(pool::AbstractWorkerPool = ppt_worker_pool()),
    @nospecialize(maxtime::Real = 0), @nospecialize(tries::Integer = 1), @nospecialize(label::AbstractString = "")
)
    R = Base.promote_op(f, map(typeof, args)...)
    untyped_result = _on_worker_impl(f, args, pool, Float64(maxtime), Int(tries), String(label))
    return convert(R, untyped_result)::R
end
export onworker


# Outcome of a single attempt to run an activity on a worker:
struct _AttemptSucceeded; value::Any; end
struct _AttemptFailed; err::Exception; retriable::Bool; end
struct _AttemptTimedOut; elapsed::Float64; end
struct _WorkerUnusable; err::Exception; end

const _AttemptOutcome = Union{_AttemptSucceeded,_AttemptFailed,_AttemptTimedOut,_WorkerUnusable}

function _attempt_onworker(@nospecialize(f::Function), @nospecialize(args::Tuple), worker::Int, maxtime::Float64)
    t_start = time()
    try
        future_result = remotecall(f, worker, args...)
        if maxtime > 0
            wait_for_any(future_result, maxtime = maxtime)
            isready(future_result) || return _AttemptTimedOut(time() - t_start)
        end
        # With a `remotecall` to the current process, fetch will return exceptions
        # originating in the called function, while if run on a remote process they
        # will be thrown to the caller of fetch. `@return_exceptions` unifies this:
        result = @return_exceptions fetch(future_result)
        return result isa Exception ? _classify_failure(result) : _AttemptSucceeded(result)
    catch err
        if err isa Union{ProcessExitedException,RemoteException}
            return _classify_failure(err)
        else
            rethrow()
        end
    end
end

function _classify_failure(err::Exception)
    orig_err = inner_exception(err)
    if orig_err isa ProcessExitedException
        return _WorkerUnusable(err)
    elseif orig_err isa MethodError && _worker_seems_corrupted(orig_err)
        return _WorkerUnusable(err)
    else
        return _AttemptFailed(err, _should_retry(err))
    end
end

# A method that exists locally but is missing on the worker indicates a
# corrupted (serializer-)state on the worker:
function _worker_seems_corrupted(err::MethodError)
    func_module = nameof(parentmodule(parentmodule(typeof(err.f))))
    func_module == :Serialization && hasmethod(err.f, map(typeof, err.args))
end

@noinline function _on_worker_impl(
    @nospecialize(f::Function), @nospecialize(args::Tuple),
    @nospecialize(pool::AbstractWorkerPool), maxtime::Float64, tries::Int, label::String
)
    activity = _Activity(f, label, tries)
    n_tries::Int = 0
    n_workers_lost::Int = 0
    max_workers_lost = 3 * tries

    while true
        n_tries += 1
        @debug "Preparing to run $activity, taking a worker from $(getlabel(pool))"
        worker = take!(pool)

        outcome::_AttemptOutcome = try
            @debug "Running $activity on worker $worker"
            _attempt_onworker(f, args, worker, maxtime)
        finally
            put!(pool, worker)
        end

        if outcome isa _AttemptSucceeded
            @debug "Worker $worker ran $activity successfully"
            return outcome.value
        elseif outcome isa _WorkerUnusable
            orig_err = inner_exception(outcome.err)
            @warn "Worker $worker became unusable during $activity, removing it." orig_err
            rmprocs(worker)
            # Worker loss doesn't count as a try, but don't tolerate it indefinitely:
            n_tries -= 1
            n_workers_lost += 1
            if n_workers_lost > max_workers_lost
                throw(MaxTriesExceeded(tries, n_tries, orig_err))
            end
        elseif outcome isa _AttemptTimedOut
            @warn "Running $activity on worker $worker timed out after $(outcome.elapsed) s (max runtime $maxtime s)"
            if worker == myid()
                # ToDo: Cancel the task running the timed-out activity, once Julia
                # supports robust task cancellation
                # (see https://github.com/JuliaLang/julia/pull/60281):
                @warn "Will not terminate main process $worker, making it available again, but it may still be running timed-out $activity"
            else
                @warn "Terminating worker $worker due to activity maxtime"
                rmprocs(worker)
            end
            if !(n_tries < tries)
                err = TimelimitExceeded(maxtime, outcome.elapsed)
                @debug "Giving up on $activity after $n_tries tries due to" err
                throw(MaxTriesExceeded(tries, n_tries, err))
            end
        elseif outcome isa _AttemptFailed
            err = outcome.err
            if !outcome.retriable
                @debug "Encountered exception while trying to run $activity on worker $worker:" inner_exception(err)
                throw(err)
            elseif !(n_tries < tries)
                @debug "Giving up on $activity after $n_tries tries due to" err
                throw(MaxTriesExceeded(tries, n_tries, inner_exception(err)))
            else
                @debug "Will retry $activity ($n_tries tries so far) due to" err
            end
        end
    end
end


# ToDo: Turn Actitity into a runnable thing, with map and bcast specialiizations:
struct _Activity
    f::Function
    label::String
    max_tries::Int
    # n_tries::Int # ToDo - should n_tries be part of activity objects?
    # Add max_time::Float64
end

function Base.show(io::IO, activity::_Activity)
    print(io, "activity ")
    if isempty(activity.label)
        print(io, nameof(typeof(activity.f)))
    else
        print(io, "\"$(activity.label)\"")
    end
    #if activity.n_tries > 1 && activity.max_tries > 1
    #    print(io, " (try $(activity.n_tries) of $(activity.max_tries))")
    #end
end


# ToDo: Add function `async_onworker(f, ...)` ?
