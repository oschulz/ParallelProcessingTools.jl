# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


const _thread_local_error_err = ThreadLocal{Any}(undef)
const _thread_local_error_set = ThreadLocal{Bool}(undef)


_clear_thread_local_errors() = fill!(threadglobal(_thread_local_error_set), false)

function _check_thread_local_errors()
    i = something(findfirst(isequal(true), threadglobal(_thread_local_error_set)), 0)
    (i > 0) && throw(threadglobal(_thread_local_error_err)[i])
    nothing
end

function _set_thread_local_error(err)
    _thread_local_error_err[] = err
    _thread_local_error_set[] = true
end


function _check_threadsel(threadsel::Union{Integer,AbstractVector{<:Integer}})
    if !checkindex(Bool, allthreads(), threadsel)
        throw(ArgumentError("Thread selection not within available threads"))
    end
    threadsel
end

function _current_thread_selected(threadsel::Union{Integer,AbstractVector{<:Integer}})
    tid = threadid()
    checkindex(Bool, tid:tid, threadsel)
end


function _run_on_threads(f)
    try
        @assert(!Base.Threads.in_threaded_loop[], "Can't nest threaded execution")
        Base.Threads.in_threaded_loop[] = true
        _clear_thread_local_errors()
        ccall(:jl_threading_run, Ref{Cvoid}, (Any,), f)
        _check_thread_local_errors()
    finally
        Base.Threads.in_threaded_loop[] = false
    end
end


function _thread_exec_func(threadsel, body)
    quote
        local thread_body_wrapper_fun
        let threadsel_eval = $(esc(threadsel))
            function thread_body_wrapper_fun()
                try
                    if Base.Threads.threadid() in threadsel_eval
                        $(esc(body))
                    end
                catch err
                    _set_thread_local_error(err)
                    rethrow()
                end
            end
            if _current_thread_selected(threadsel_eval)
                thread_body_wrapper_fun()
            else
                _run_on_threads(thread_body_wrapper_fun)
            end
            nothing
        end
    end
end


export allthreads
allthreads() = 1:nthreads()


export @onallthreads
macro onallthreads(body)
    _thread_exec_func(:(ParallelProcessingTools.allthreads()), body)
end


export @onthreads
macro onthreads(threadsel, body)
    _thread_exec_func(threadsel, body)
end


function ThreadLocal{T}(f::Base.Callable) where {T}
    result = ThreadLocal{T}(undef)
    result.value
    @onallthreads result.value[threadid()] = f()
    result
end
