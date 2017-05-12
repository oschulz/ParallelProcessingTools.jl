# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads
using Compat


export AbstractThreadLocal
@compat abstract type AbstractThreadLocal{T} end


"""
    threadlocal{T}(x::T)::T
    threadlocal{T}(x::AbstractThreadLocal{T})::T
"""
function threadlocal end
export threadlocal


"""
    isdefined_local(v::AbstractThreadLocal)::Bool
"""
function isdefined_local end
export isdefined_local


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


@inline Base.getindex(x::ThreadLocal) = x.value[threadid()]

@inline Base.setindex!(x::ThreadLocal, y) = x.value[threadid()] = y

@inline threadlocal(x) = x
@inline threadlocal(x::ThreadLocal) = x[]


isdefined_local(v::ThreadLocal) = isdefined(v.value, threadid())

all_thread_values(v::ThreadLocal) = v.value
