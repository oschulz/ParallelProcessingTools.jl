# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


export AbstractThreadLocal
abstract type AbstractThreadLocal{T} end


@deprecate isdefined_local(x) isassigned(x)


"""
    threadlocal(x) = x
    threadlocal(x::ThreadLocal) = x[]

Useful for unified access to plain values and thread-local values.
"""
function threadlocal end
export threadlocal


"""
    threadglobal(v::AbstractThreadLocal{T})::AbstractVector{T}
"""
function threadglobal end
export threadglobal



export ThreadLocal

struct ThreadLocal{T} <: AbstractThreadLocal{T}
    value::Vector{T}

    ThreadLocal{T}(::UndefInitializer) where {T} = new{T}(Vector{T}(undef, nthreads()))

    ThreadLocal{T}(value::T) where {T} = new{T}([deepcopy(value) for i in 1:nthreads()])
end

ThreadLocal{T}() where {T} = ThreadLocal{T}(T)

ThreadLocal(value::T) where {T} = ThreadLocal{T}(value)


@inline Base.getindex(x::ThreadLocal) = x.value[threadid()]

@inline Base.setindex!(x::ThreadLocal, y) = x.value[threadid()] = y


Base.eltype(x::Type{<:ThreadLocal{T}}) where {T} = @isdefined(T) ? T : Any


@inline Base.get(x::ThreadLocal) = x[]

@inline Base.get(default::Base.Callable, x::ThreadLocal{T}) where {T} = isassigned(x) ? x[] : convert(T, default())

@inline Base.get(x::ThreadLocal, default) = get(() -> default, x)

function Base.get!(default::Base.Callable, x::ThreadLocal{T}) where {T}
    if isassigned(x)
        x[]
    else
        x[] = convert(T, default())
    end
end

Base.get!(x::ThreadLocal, default) = get!(() -> default, x)


@inline threadlocal(x) = x
@inline threadlocal(x::ThreadLocal) = x[]


Base.isassigned(v::ThreadLocal) = isassigned(v.value, threadid())

threadglobal(v::ThreadLocal) = v.value
