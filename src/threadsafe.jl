# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


export ThreadSafe
abstract type ThreadSafe{T} end



export ThreadSafeReentrantLock

struct ThreadSafeReentrantLock
    thread_lock::RecursiveSpinLock
    task_lock::ReentrantLock

    ThreadSafeReentrantLock() = new(RecursiveSpinLock(), ReentrantLock())
end

function Base.lock(l::ThreadSafeReentrantLock)
    # @info "LOCKING $l"
    lock(l.thread_lock)
    try
        lock(l.task_lock)
    catch err
        unlock(l.thread_lock)
        rethrow()
    end
end


function Base.unlock(l::ThreadSafeReentrantLock)
    # @info "UNLOCKING $l"
    try
        unlock(l.task_lock)
    finally
        unlock(l.thread_lock)
    end
end



export LockableValue

struct LockableValue{T} <: ThreadSafe{T}
    x::T
    l::ThreadSafeReentrantLock

    (::Type{LockableValue{T}})(x::T) where {T} = new{T}(x, ThreadSafeReentrantLock())
end

LockableValue(x::T) where {T} = LockableValue{T}(x)


function Base.broadcast(f, lx::LockableValue)
    lock(lx.l) do
        f(lx.x)
    end
end

Base.map(f, lx::LockableValue) = broadcast(f, lx)


abstract type ThreadSafeIO <: IO end



export LockableIO

struct LockableIO{T<:IO}
    lx::LockableValue{T}

    (::Type{LockableIO{T}})(x::T) where {T<:IO} = new{T}(LockableValue(x))
end

LockableIO(x::T) where {T<:IO} = LockableIO{T}(x)


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


const _critical_section_lock = ThreadSafeReentrantLock()

macro critical(body)
    quote
        try
            lock(_critical_section_lock)
            $(esc(body))
        finally
            unlock(_critical_section_lock)
        end
    end
end

export @critical
