# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


"""
    ParallelProcessingTools.getlabel(obj)

Returns a descriptive label for `obj` suitable for using in exceptions and
logging messages. Defaults to `string(obj)`.
"""
function getlabel end

getlabel(obj) = convert(String, string(obj))
getlabel(task::Task) = "Task $(nameof(typeof(task.code)))"
getlabel(process::Process) = "Process $(getlabel(process.cmd))"


"""
    ParallelProcessingTools.isactive(obj)::Bool

Checks if `obj` is still active, running or whatever applies to the type of
`obj`. Supports `Task` and `Process` and may be specialized for other object
types.

Returns `true` if `ismissing(obj)`.
"""
function isactive end

isactive(::Missing) = true
isactive(task::Task) = !istaskdone(task)
isactive(process::Process) = process_running(process)


"""
    ParallelProcessingTools.hasfailed(obj)::Bool

Checks if `obj` has failed in some way. Supports `Task` and `Process` and may
be specialized for other object types.

Returns `false` if `ismissing(obj)`.
"""
function hasfailed end

hasfailed(::Missing) = false
hasfailed(task::Task) = istaskfailed(task)
hasfailed(process::Process) = !iszero(process.exitcode)


"""
    ParallelProcessingTools.whyfailed(obj)::Exception

Returns a reason, as an `Exception` instance, why `obj` has failed. Supports
`Task` and `Process` and may be specialized for other object types. `obj`
must not be `missing`.
"""
function whyfailed end

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

"""
    ParallelProcessingTools.NonZeroExitCode(cmd::Cmd, exitcode::Integer) isa Exception

Exception to indicate that a an external process running `cmd` failed with the
given exit code (not equal zero).
"""
struct NonZeroExitCode <: Exception
    exitcode::Int
end

function NonZeroExitCode(exitcode::Integer)
    exitcode == 0 && throw(ArgumentError("NonZeroExitCode exitcode must not be zero"))
    NonZeroExitCode(exitcode)
end
