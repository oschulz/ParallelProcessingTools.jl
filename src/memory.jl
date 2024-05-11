# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

const _RLIMIT_AS = 9 # maximum size of the process's virtual memory

const _EINVAL = 22 # libc errno for "Invalid argument"

# Struct for libc getrlimit and setrlimit:
mutable struct _RLimit
    cur::Clong
    max::Clong
end


"""
    memory_limit()

Gets the virtual memory limit for the current Julia process.

Returns a tuple `(soft_limit::Int64, hard_limit::Int64)` (in units of bytes).
Values of `-1` mean unlimited. 

!!! note
    Currently only works on Linux, simply returns `(Int64(-1), Int64(-1))` on
    other operationg systems.
"""
function memory_limit end
export memory_limit

@static if Sys.islinux()
    function memory_limit()
        rlim = Ref(_RLimit(0, 0))
        rc = ccall(:getrlimit, Cint, (Cint, Ref{_RLimit}), _RLIMIT_AS, rlim)
        if rc != 0
            error("Failed to get memory limits: ", Base.Libc.strerror(Base.Libc.errno()))
        end
        return rlim[].cur, rlim[].max
    end
else
    memory_limit() = Int64(-1), Int64(-1)
end


"""
    memory_limit!(soft_limit::Integer, hard_limit::Integer = -1)

Sets the virtual memory limit for the current Julia process.

`soft_limit` and `hard_limit` are in units of bytes. Values of `-1` mean
unlimited. `hard_limit` must not be stricter than `soft_limit`, and should
typically be set to `-1`.

Returns `(soft_limit::Int64, hard_limit::Int64)`.

!!! note
    Currently only has an effect on Linux, does nothing and simply returns
    `(Int64(-1), Int64(-1))` on other operating systems.
"""
function memory_limit! end
export memory_limit!

@static if Sys.islinux()
    function memory_limit!(soft_limit::Integer, hard_limit::Integer = Int64(-1))
        GC.gc()

        rlim = Ref(_RLimit(soft_limit, hard_limit))
        rc = ccall(:setrlimit, Cint, (Cint, Ref{_RLimit}), _RLIMIT_AS, rlim)
        if rc != 0
            errno = Base.Libc.errno()
            if errno == _EINVAL
                throw(ArgumentError("Invalid soft/hard memory limit $soft_limit/$hard_limit."))
            else
                error("Failed to set memory limit: ", errno, Base.Libc.strerror(errno))
            end
        end
        return rlim[].cur, rlim[].max
    end
else
    memory_limit!(soft_limit::Integer, hard_limit::Integer) = Int64(-1), Int64(-1)
end
