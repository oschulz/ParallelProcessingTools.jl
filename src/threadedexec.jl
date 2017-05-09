# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads


const _thread_local_error_err = ThreadLocalValue(Any)
const _thread_local_error_set = ThreadLocalValue(Bool)

const _running_on_threads = Atomic{Int}(0)


_clear_thread_local_errors() = fill!(all_thread_values(_thread_local_error_set), false)

function _check_thread_local_errors()
    i = findfirst(all_thread_values(_thread_local_error_set), true)
    (i > 0) && throw(all_thread_values(_thread_local_error_err)[i])
    nothing
end

function _set_thread_local_error(err)
    set_local!(_thread_local_error_err, err)
    set_local!(_thread_local_error_set, true)
end



function _run_on_threads(f)
    try
        already_on_threads = atomic_cas!(_running_on_threads, 0, 1)
        @assert(already_on_threads == 0, "Can't nest threaded execution")

        _clear_thread_local_errors()
        ccall(:jl_threading_run, Void, (Any,), Core.svec(f))
        _check_thread_local_errors()
    finally
        atomic_cas!(_running_on_threads, 1, 0)
    end
end


function _thread_exec_func(body)
    f_sym = gensym("_oneachthread")
    quote
        function $f_sym()
            try
                $(esc(body))
            catch err
                _set_thread_local_error(err)
                rethrow()
            end
        end
        _run_on_threads($f_sym)
    end
end


export @everythread
macro everythread(body)
    _thread_exec_func(body)
end
