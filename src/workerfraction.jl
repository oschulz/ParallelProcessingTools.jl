# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads


"""
    workerfraction(A, n_workers::Integer, i::Integer)
"""
function workerfraction end
export workerfraction


"""
    threadfraction(A, n_workers::Integer = nthreads(), i::Integer = threadid())
"""
function threadfraction end
export threadfraction


"""
    processfraction(A, n_workers::Integer = nworkers(), i::Integer = threadid())
"""
function processfraction end
export processfraction


function _workerfraction_hi(n_items::Integer, n_workers::Integer, i::Integer)
    @assert n_items > 0
    @assert n_workers > 0
    @assert i >= 0 && i <= n_workers

    a = div(n_items, n_workers)
    b = rem(n_items, n_workers)
    c = div(b * i, n_workers)
    result = a * i + c
end


function _workerfraction_impl(n_items::Integer, n_workers::Integer, i::Integer)
    @assert i >= 1
    (_workerfraction_hi(n_items, n_workers, i - 1) + 1):_workerfraction_hi(n_items, n_workers, i)
end

workerfraction(range::StepRange, n_workers::Integer, i::Integer) =
    step(range) * (_workerfraction_impl(length(range), n_workers, i) - 1) + first(range)

workerfraction(range::AbstractUnitRange, n_workers::Integer, i::Integer) =
    (_workerfraction_impl(length(range), n_workers, i) - 1) + first(range)


threadfraction(A, n_workers::Integer = nthreads(), i::Integer = threadid()) =
    workerfraction(A, n_workers, i)

processfraction(A, n_workers::Integer = nworkers(), i::Integer = threadid()) =
    workerfraction(A, n_workers, i)
