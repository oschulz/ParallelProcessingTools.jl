# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    ParallelProcessingTools.original_exception(err)

Replaces `TaskFailedException`s and `RemoteException`s with the underlying
exception that originated within the task or on the remote process.
"""
function original_exception end

original_exception(err) = err
original_exception(err::CompositeException) = CompositeException(original_exception.(err.exceptions))
original_exception(err::TaskFailedException) = err.task.result
original_exception(err::RemoteException) = err.captured.ex


"""
    ParallelProcessingTools.onlyfirst_exception(err)

Replaces `CompositeException`s with their first exception.

Also employs `original_exception` if `simplify` is `true`.
"""
function onlyfirst_exception end

onlyfirst_exception(err) = err
onlyfirst_exception(err::CompositeException) = first(err.exceptions)


"""
    @userfriendly_exceptions expr

Transforms exceptions originating from `expr` into more user-friendly ones.

If multiple exceptions originate from parallel code in `expr`, only one
is rethrown, and `TaskFailedException`s and `RemoteException`s are replaced
by the original exceptions that caused them.

See [`original_exception`] and [`onlyfirst_exception`](@ref).
"""
macro userfriendly_exceptions(expr)
    quote
        try
            $(esc(expr))
        catch err
            rethrow(original_exception(onlyfirst_exception(err)))
        end
    end
end
export @userfriendly_exceptions
