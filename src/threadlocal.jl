# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads
using Compat


export AbstractThreadLocal
@compat abstract type AbstractThreadLocal{T} end


@deprecate isdefined_local(x) isassigned(x)


"""
    threadlocal(x) = x
    threadlocal(x::ThreadLocal) = x[]

Useful for unified access to plain values and thread-local values.
"""
function threadlocal end
export threadlocal


"""
    all_thread_values{T}(v::AbstractThreadLocal{T})::AbstractVector{T}
"""
function all_thread_values end
export all_thread_values



export ThreadLocal

type ThreadLocal{T} <: AbstractThreadLocal{T}
    value::Vector{T}

    (::Type{ThreadLocal{T}}){T}() = new{T}(Vector{T}(nthreads()))

    function (::Type{ThreadLocal{T}}){T}(xs::Vector{T})
        (length(xs) != nthreads()) && throw(ArgumentError("Vectors length doesn't match number of threads"))
        new{T}(xs)
    end
end

ThreadLocal{T}(x::T) = ThreadLocal{T}([deepcopy(x) for _ in 1:nthreads()])

function ThreadLocal(f::Base.Callable)
    values = [f() for _ in 1:nthreads()]
    ThreadLocal{eltype(values)}(values)
end


@inline Base.getindex(x::ThreadLocal) = x.value[threadid()]

@inline Base.setindex!(x::ThreadLocal, y) = x.value[threadid()] = y


@inline Base.get(x::ThreadLocal) = x[]

@inline Base.get{T}(default::Base.Callable, x::ThreadLocal{T}) = isassigned(x) ? x[] : convert(T, default())

@inline Base.get(x::ThreadLocal, default) = get(() -> default, x)

function Base.get!{T}(default::Base.Callable, x::ThreadLocal{T})
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

all_thread_values(v::ThreadLocal) = v.value
