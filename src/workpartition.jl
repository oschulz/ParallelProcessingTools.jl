# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads


"""
    workpartition(A, n::Integer, i::Integer)
"""
function workpartition end
export workpartition


"""
    workpartitions(A, n::Integer)
"""
function workpartitions end
export workpartitions


"""
    threadpartition(A, n_workers::Integer = nthreads(), i::Integer = threadid())
"""
function threadpartition end
export threadpartition


"""
    processpartition(A, n_workers::Integer = nworkers(), i::Integer = threadid())
"""
function processpartition end
export processpartition


function _workpartition_hi{T<:Integer}(n_items::T, n_partitions::T, i::T)
    @assert n_items >= 0
    @assert n_partitions > 0
    @assert i >= 0 && i <= n_partitions

    a = div(n_items, n_partitions)
    b = rem(n_items, n_partitions)
    c = div(b * i, n_partitions)
    (a * i + c)::T
end


function _workpartition_impl(n_items::Integer, n_partitions::Integer, i::Integer)
    n_items_T, n_partitions_T, i_T = promote(n_items, n_partitions, i)

    if !(0 < i_T <= n_partitions_T)
        one(i_T):zero(i_T)
    else
        (_workpartition_hi(n_items_T, n_partitions_T, i_T - 1) + 1):_workpartition_hi(n_items_T, n_partitions_T, i_T)
    end
end

workpartition(range::StepRange, n::Integer, i::Integer) =
    step(range) * (_workpartition_impl(length(range), n, i) - 1) + first(range)

workpartition(range::AbstractUnitRange, n::Integer, i::Integer) =
    (_workpartition_impl(length(range), n, i) - 1) + first(range)

workpartition(A::AbstractArray, n::Integer, i::Integer) =
    view(A, workpartition(linearindices(A), n, i))


workpartitions(A, n::Integer) = (workpartition(A, n, i) for i in one(n):n)


threadpartition(A, n_threads::Integer = nthreads(), i::Integer = threadid()) =
    workpartition(A, n_threads, i)

processpartition(A, n_procs::Integer = nworkers(), i::Integer = (nprocs() == 1) ? 1 : myid() - 1) =
    workpartition(A, n_procs, i)
