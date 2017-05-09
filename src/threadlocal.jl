# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads
using Compat


export ThreadLocal
@compat abstract type ThreadLocal{T} end


"""
    get_local{T}(v::ThreadLocal{T})::T
    get_local{T}(v::ThreadLocal{T}, init_function())::T
"""
function get_local end
export get_local


"""
    set_local!{T}(v::ThreadLocal{T}, x)::T
"""
function set_local! end
export set_local!


"""
    isdefined_local(v::ThreadLocal)::Bool
"""
function isdefined_local end
export isdefined_local


"""
    all_thread_values{T}(v::ThreadLocal{T})::AbstractVector{T}
"""
function all_thread_values end
export all_thread_values



export ThreadLocalValue

type ThreadLocalValue{T} <: ThreadLocal{T}
    value::Vector{T}

    (::Type{ThreadLocalValue{T}}){T}() = new{T}(Vector{T}(nthreads()))
end

ThreadLocalValue{T}(::Type{T}) = ThreadLocalValue{T}()


get_local(v::ThreadLocalValue) = v.value[threadid()]

function get_local(v::ThreadLocalValue, init_function)
    tid = threadid()
    if !isdefined(v.value, tid)
        v.value[tid] = init_function()
    end
    v.value[tid]
end

set_local!(v::ThreadLocalValue, x) = v.value[threadid()] = x

isdefined_local(v::ThreadLocalValue) = isdefined(v.value, threadid())

all_thread_values(v::ThreadLocalValue) = v.value
