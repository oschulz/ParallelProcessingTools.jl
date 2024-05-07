# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    ParallelProcessingTools.inner_exception(err)

Replaces exceptions like a `TaskFailedException` or a `RemoteException` with
their underlying cause. Leaves other exceptions unchanged.
"""
function inner_exception end
export inner_exception

inner_exception(err) = err
inner_exception(err::CompositeException) = CompositeException(inner_exception.(err.exceptions))
inner_exception(err::TaskFailedException) = err.task.result
inner_exception(err::RemoteException) = err.captured.ex


"""
    ParallelProcessingTools.original_exception(err)

Replaces (possibly nested) exceptions like a `TaskFailedException` or
`RemoteException`s with the innermost exception, likely to be the one that
was thrown originally. Leaves other exceptions unchanged.
"""
function original_exception end
export original_exception

original_exception(err) = err
original_exception(err::CompositeException) = CompositeException(original_exception.(err.exceptions))
original_exception(err::TaskFailedException) = original_exception(err.task.result)
original_exception(err::RemoteException) = original_exception(err.captured.ex)


"""
    ParallelProcessingTools.onlyfirst_exception(err)

Replaces `CompositeException`s with their first exception.

Also employs `inner_exception` if `simplify` is `true`.
"""
function onlyfirst_exception end
export onlyfirst_exception

onlyfirst_exception(err) = err
onlyfirst_exception(err::CompositeException) = first(err)


"""
    @userfriendly_exceptions expr

Transforms exceptions originating from `expr` into more user-friendly ones.

If multiple exceptions originate from parallel code in `expr`, only one
is rethrown, and `TaskFailedException`s and `RemoteException`s are replaced
by the original exceptions that caused them.

See [`inner_exception`] and [`onlyfirst_exception`](@ref).
"""
macro userfriendly_exceptions(expr)
    quote
        try
            $(esc(expr))
        catch err
            rethrow(inner_exception(onlyfirst_exception(err)))
        end
    end
end
export @userfriendly_exceptions


"""
    @return_exceptions expr

Runs `expr` and catches and returns exceptions as values instead of having
them thrown.

Useful for user-side debugging, especially of parallel and/or remote code
execution.

See also [`@userfriendly_exceptions`](@ref).
"""
macro return_exceptions(expr)
    quote
        try
            $(esc(expr))
        catch err
            err
        end
    end
end
export @return_exceptions
