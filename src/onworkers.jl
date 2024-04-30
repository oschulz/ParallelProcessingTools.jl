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


_should_retry(::Any) = false
_should_retry(::Exception) = false
_should_retry(::TimelimitExceeded) = true
_should_retry(err::RemoteException) = _should_retry(err.captured.ex)


@static if VERSION >= v"1.9"

"""
    onworker(
        f::Function, args...;
        pool::AbstractWorkerPool = default_flex_worker_pool(),
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
otherwise throws an exception.

!!! compat "Compatibility"
    Requires Julia v1.9
"""
function onworker end
export onworker

function onworker(
    f::Function;
    @nospecialize(pool::AbstractWorkerPool = default_flex_worker_pool()),
    @nospecialize(maxtime::Real = 0), @nospecialize(tries::Integer = 1), @nospecialize(label::AbstractString = "")
)
    R = _return_type(f, ())
    untyped_result = _on_worker_impl(f, (), pool, Float64(maxtime), Int(tries), String(label))
    return convert(R, untyped_result)::R
end

function onworker(
    f::Function, arg1, args...;
    @nospecialize(pool::AbstractWorkerPool = default_flex_worker_pool()),
    @nospecialize(maxtime::Real = 0), @nospecialize(tries::Integer = 1), @nospecialize(label::AbstractString = "")
)
    all_args = (arg1, args...)
    R = _return_type(f, all_args)
    untyped_result = _on_worker_impl(f, all_args, pool, Float64(maxtime), Int(tries), String(label))
    return convert(R, untyped_result)::R
end

_return_type(f, args::Tuple) = Core.Compiler.return_type(f, typeof(args))


@noinline function _on_worker_impl(
    @nospecialize(f::Function), @nospecialize(args::Tuple),
    @nospecialize(pool::AbstractWorkerPool), maxtime::Float64, tries::Int, label::String
)
    n_tries::Int = 0
    while n_tries < tries
        n_tries += 1
        activity = _Activity(f, label, tries, n_tries)

        @debug "Preparing to run $activity, taking a worker from $(getlabel(pool))"
        worker = take!(pool)

        start_time = time()
        elapsed_time = zero(start_time)

        try
            @debug "Running $activity on worker $worker"

            future_result = remotecall(f, worker, args...)

            if maxtime > 0
                # May throw an exception:
                wait_for_any(future_result, Timer(maxtime))
            else
                # May throw an exception:
                wait(future_result)
            end
            elapsed_time = time() - start_time

            # May throw an exception:
            result_isready = isready(future_result)

            if result_isready
                # With a `remotecall` to the current process, fetch will return exceptions
                # originating in the called function, while if run on a remote process they
                # will be thrown to the caller of fetch. We need to unify this behavior:

                fetched_result = try
                    fetch(future_result)
                catch err
                    err
                end

                if _should_retry(fetched_result)
                    if !(n_tries < tries)
                        err = original_exception(fetched_result)
                        throw(MaxTriesExceeded(tries, n_tries, err))
                    end
                else
                    if fetched_result isa Exception
                        err = fetched_result
                        orig_err = original_exception(fetched_result)
                        throw(err)
                    else
                        @debug "Worker $worker ran $activity successfully in $elapsed_time s"
                        return fetched_result
                    end    
                end
            else
                # Sanity check: if we got here, we must have timed out:
                @assert maxtime > 0 && elapsed_time > maxtime

                @warn "Running $activity on worker $worker timed out after $elapsed_time s (max runtime $(maxtime) s)"

                if worker == myid()
                    @warn "Will not terminate main process $worker, making it available again, but it may still running timed-out $activity"
                else
                    @warn "Terminating worker $worker due to activity maxtime"
                    rmprocs(worker)
                end

                if !(n_tries < tries)
                    err = TimelimitExceeded(maxtime, elapsed_time)
                    @debug "Giving up on $activity after $n_tries tries due to" err
                    throw(MaxTriesExceeded(tries, n_tries, err))
                end
            end
        catch err
            if err isa ProcessExitedException
                @warn "Worker $worker seems to have terminated during $activity"
                # This try doesn't count:
                n_tries -= 1
                # Make certain that worker is really gone:
                rmprocs(worker)
            elseif err isa RemoteException
                orig_err = original_exception(err)
                if orig_err isa MethodError
                    func = orig_err.f
                    func_args = orig_err.args
                    func_name = string(typeof(func))
                    func_module = nameof(parentmodule(parentmodule(typeof(func))))
                    func_hasmethod_local = hasmethod(func, map(typeof, func_args))
                    if func_module == :Serialization && func_hasmethod_local
                        @warn "Function $func_name may be corrupted on worker $worker (missing method), terminating worker."
                        rmprocs(worker)
                        # This try doesn't count:
                        n_tries -= 1
                    else
                        rethrow()
                    end
                else
                    @debug "Encountered exception while trying to run $activity on worker $worker:" orig_err
                    rethrow()
                end
            elseif err isa MaxTriesExceeded
                retry_reason = err.retry_reason
                @debug "Giving up on $activity after $err.n_tries tries due to" retry_reason
                rethrow()
            else
                @debug "Encountered unexpected exception while trying to run $activity on worker $worker:" err
                rethrow()
            end
        finally
            put!(pool, worker)
        end
    end
    # Should never reach this point:
    @assert false
end

@deprecate on_free_worker(f::Function, args...; time::Real = 0, tries::Integer = 1, label::AbstractString) onworker(f, args...; maxtime = time, tries = tries)


# For convient debugging output:
struct _Activity
    f::Function
    label::String
    max_tries::Int
    n_tries::Int
end

function Base.show(io::IO, activity::_Activity)
    print(io, "activity ")
    if isempty(activity.label)
        print(io, nameof(typeof(activity.f)))
    else
        print(io, "\"$(activity.label)\"")
    end
    if activity.n_tries > 1 && activity.max_tries > 1
        print(io, " (try $(activity.n_tries) of $(activity.max_tries))")
    end
end


# ToDo: Add function `async_onworker(f, ...)` ?

end # Julia >= v1.9
