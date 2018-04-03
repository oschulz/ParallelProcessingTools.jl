# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads
using Compat


export ThreadSafe
@compat abstract type ThreadSafe{T} end



export ThreadSafeReentrantLock

type ThreadSafeReentrantLock
    thread_lock::RecursiveSpinLock
    task_lock::ReentrantLock

    ThreadSafeReentrantLock() = new(RecursiveSpinLock(), ReentrantLock())
end

function Base.lock(l::ThreadSafeReentrantLock)
    # info("LOCKING $l")
    lock(l.thread_lock)
    try
        lock(l.task_lock)
    catch err
        unlock(l.thread_lock)
        rethrow()
    end
end


function Base.unlock(l::ThreadSafeReentrantLock)
    # info("UNLOCKING $l")
    try
        unlock(l.task_lock)
    finally
        unlock(l.thread_lock)
    end
end



export LockableValue

type LockableValue{T} <: ThreadSafe{T}
    x::T
    l::ThreadSafeReentrantLock

    (::Type{LockableValue{T}}){T}(x::T) = new{T}(x, ThreadSafeReentrantLock())
end

LockableValue{T}(x::T) = LockableValue{T}(x)


function Base.broadcast(f, lx::LockableValue)
    lock(lx.l) do
        f(lx.x)
    end
end

Base.map(f, lx::LockableValue) = broadcast(f, lx)


@compat abstract type ThreadSafeIO <: IO end



export LockableIO

immutable LockableIO{T<:IO}
    lx::LockableValue{T}

    (::Type{LockableIO{T}}){T<:IO}(x::T) = new{T}(LockableValue(x))
end

LockableIO{T<:IO}(x::T) = LockableIO{T}(x)


@inline Base.broadcast(f, lio::LockableIO) = broadcast(f, lio.lx)
@inline Base.map(f, lio::LockableIO) = broadcast(f, lio)

@inline Base.read(lio::LockableIO, args...; kwargs...) = map(lio) do io
    read(io, args...; kwargs...)
end

@inline Base.read!(lio::LockableIO, args...; kwargs...) = map(lio) do io
    read(io, args...; kwargs...)
end

@inline Base.write(lio::LockableIO, args...; kwargs...) = map(lio) do io
    write(io, args...; kwargs...)
end



const _stdout_lock = ThreadSafeReentrantLock()
const _stderr_lock = ThreadSafeReentrantLock()


export threadsafe_info

"""
    threadsafe_info(...)

Thread-safe wrapper for `info(STDERR, ...)`.
"""
@inline threadsafe_info(args...; kwargs...) = lock(_stderr_lock) do
    info(STDERR, args...; kwargs...)
end


export threadsafe_warn

"""
    threadsafe_warn(...)

Thread-safe wrapper for `warn(STDERR, ...)`.
"""
@inline threadsafe_warn(args...; kwargs...) = lock(_stderr_lock) do
    warn(STDERR, args...; kwargs...)
end


export threadsafe_print

"""
    threadsafe_print(...)

Thread-safe wrapper for `print(STDOUT, ...)`.
"""
@inline threadsafe_print(args...; kwargs...) = lock(_stdout_lock) do
    info(STDOUT, args...; kwargs...)
end


export threadsafe_info

"""
    threadsafe_write(...)

Thread-safe wrapper for `write(STDOUT, ...)`.
"""
@inline threadsafe_write(args...; kwargs...) = lock(_stdout_lock) do
    write(STDOUT, args...; kwargs...)
end
