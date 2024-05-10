# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    ParallelProcessingTools.NonZeroExitCode(cmd::Cmd, exitcode::Integer) isa Exception

Exception to indicate that a an external process running `cmd` failed with the
given exit code (not equal zero).
"""
struct NonZeroExitCode <: Exception
    exitcode::Int

    function NonZeroExitCode(exitcode::Int)
        exitcode == 0 && throw(ArgumentError("NonZeroExitCode exitcode must not be zero"))
        new(exitcode)
    end
end

NonZeroExitCode(exitcode::Integer) = NonZeroExitCode(Int(exitcode))


"""
    ParallelProcessingTools.getlabel(obj)

Returns a descriptive label for `obj` suitable for using in exceptions and
logging messages. Defaults to `string(obj)`.
"""
function getlabel end

getlabel(obj) = convert(String, string(obj))
getlabel(task::Task) = "Task $(nameof(typeof(task.code)))"
getlabel(process::Process) = "Process $(getlabel(process.cmd))"
getlabel(future::Future) = "Future $(future.id)"


"""
    ParallelProcessingTools.isactive(obj)::Bool

Checks if `obj` is still active, running or whatever applies to the type of
`obj`.

Supports `Task`, `Process`, `Future`, `Channel`, `Timer`,
`Base.AsyncCondition` and may be extended to other object types.

Returns `false` if `isnothing(obj)` and `true` if `ismissing(obj)`.
"""
function isactive end

isactive(::Nothing) = false
isactive(::Missing) = true
isactive(task::Task) = !istaskdone(task)
isactive(process::Process) = process_running(process)
isactive(future::Future) = !isready(future)
isactive(channel::Channel) = isopen(channel)
isactive(timer::Timer) = isopen(timer)
isactive(condition::Base.AsyncCondition) = isopen(condition)


"""
    ParallelProcessingTools.wouldwait(obj)::Bool

Returns `true` if `wait(obj)` would result in waiting and `false` if
`wait(obj)` would return (almost) immediately.

Supports `Task`, `Process`, `Future`, `Channel`, `Timer`,
`Base.AsyncCondition` and may be extended to other object types.

Returns `false` if `isnothing(obj)` but `obj` must not be `missing`.
"""
function wouldwait end

wouldwait(::Nothing) = false
wouldwait(::Missing) = throw(ArgumentError("wouldwait does not support Missing"))
wouldwait(task::Task) = !istaskdone(task)
wouldwait(process::Process) = process_running(process)
wouldwait(future::Future) = !isready(future)
wouldwait(channel::Channel) = isopen(channel) && !isready(channel)
wouldwait(timer::Timer) = isopen(timer)
wouldwait(condition::Base.AsyncCondition) = isopen(condition)


"""
    ParallelProcessingTools.hasfailed(obj)::Bool

Checks if `obj` has failed in some way.
    
Supports `Task` and `Process` and may be extended to other object types.

Returns `false` if `isnothing(obj)` or `ismissing(obj)`.
"""
function hasfailed end

hasfailed(::Nothing) = false
hasfailed(::Missing) = false
hasfailed(task::Task) = istaskfailed(task)
hasfailed(process::Process) = !isactive(process) && !iszero(process.exitcode)

function hasfailed(channel::Channel)
    if isactive(channel) return false
    else
        err = channel.excp
        if err isa InvalidStateException
            return err.state == :closed ? false : true
        else
            return true
        end
    end
end


"""
    ParallelProcessingTools.whyfailed(obj)::Exception

Returns a reason, as an `Exception` instance, why `obj` has failed.

Supports `Task` and `Process` and may be extended to other object types.

`obj` must not be `nothing` or `missing`.
"""
function whyfailed end

whyfailed(::Nothing) = throw(ArgumentError("whyfailed does not support Nothing"))
whyfailed(::Missing) = throw(ArgumentError("whyfailed does not support Missing"))

function whyfailed(task::Task)
    if hasfailed(task)
        err = task.result
        if err isa Exception
            return err
        else
            return ErrorException("Task failed with non-exception result of type $(nameof(typeof(err)))")
        end
    else
        throw(ArgumentError("Task $(getlabel(task)) did not fail, whyfailed not allowed"))
    end
end

function whyfailed(process::Process)
    if hasfailed(process)
        return NonZeroExitCode(process.exitcode)
    else
        throw(ArgumentError("Process $(getlabel(process)) did not fail, whyfailed not allowed"))
    end
end

function whyfailed(channel::Channel)
    if hasfailed(channel)
        return channel.excp
    else
        throw(ArgumentError("Channel $(getlabel(channel)) did not fail, whyfailed not allowed"))
    end
end
