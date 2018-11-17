# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


function _workpart_hi(n_items::T, n_partitions::T, i::T) where {T<:Integer}
    @assert n_items >= 0
    @assert n_partitions > 0
    @assert i >= 0 && i <= n_partitions

    a = div(n_items, n_partitions)
    b = rem(n_items, n_partitions)
    c = div(b * i, n_partitions)
    (a * i + c)::T
end


function _workpart_scheme(range::Base.OneTo{<:Integer}, n_partitions::Integer, i::Integer)
    n_items = last(range)
    n_items_T, n_partitions_T, i_T = promote(n_items, n_partitions, i)

    if !(0 < i_T <= n_partitions_T)
        one(i_T):zero(i_T)
    else
        (_workpart_hi(n_items_T, n_partitions_T, i_T - 1) + 1):_workpart_hi(n_items_T, n_partitions_T, i_T)
    end
end


_workpart_scheme(range::StepRange, n::Integer, i::Integer) =
    step(range) * (_workpart_scheme(Base.OneTo(length(range)), n, i) .- 1) .+ first(range)

_workpart_scheme(range::AbstractUnitRange, n::Integer, i::Integer) =
    _workpart_scheme(Base.OneTo(length(range)), n, i) .+ (first(range) - 1)

_workpart_scheme(A::AbstractArray, n::Integer, i::Integer) =
    view(A, _workpart_scheme(eachindex(A), n, i))



_is_sorted_and_unique(A::AbstractRange) = true

function _is_sorted_and_unique(A::AbstractVector)
    if isempty(A)
        return true
    elseif !issorted(A)
        return false
    else
        idxs = LinearIndices(A)
        prev = A[first(idxs)]
        @inbounds for i in (first(idxs)+1):last(idxs)
            current = A[i]
            if current == prev
                return false
            else
                prev = current
            end
        end
        return true
    end
end


"""
    workpart(data::AbstractArray, workersel::AbstractVector{W}, current_worker::W) where {W}

Get the part of `data` that the execution unit `current_worker` is
responsible for. Implies a partition of `data` across the workers listed in
`workersel`.

For generic `data` arrays, `workpart` will return a view. If `data` is a
`Range` (e.g. indices to be processed), a sub-range will be returned.

Type `W` will typically be `Int` and `workersel` will usually be a range/array
of thread/process IDs.

Note: `workersel` is required to be sorted in ascending order and to contain
no duplicate entries.

Examples:

```julia
using Distributed, Base.Threads
A = rand(100)
# ...
sub_A = workpart(A, workers(), myid())
# ...
idxs = workpart(eachindex(sub_A), allthreads(), threadid())
for i in idxs
    # ...
end
```
"""
function workpart end
export workpart

function workpart(data::AbstractArray, workersel::AbstractVector{W}, current_worker::W) where {W}
    _is_sorted_and_unique(workersel) || throw(ArgumentError("List of selected workers must be sorted and contain no duplicates"))

    worker_idxs = eachindex(workersel)
    n = length(worker_idxs)
    i = searchsortedfirst(workersel, current_worker)
    checkindex(Bool, worker_idxs, i) && workersel[i] == current_worker || throw(ArgumentError("Worker $current_worker is not in specified list of selected workers"))

    _workpart_scheme(data, n, i)
end

function workpart(data::AbstractArray, workersel::Integer, current_worker::Integer)
    current_worker == workersel || throw(ArgumentError("Worker $current_worker does not equal specified worker"))
    data
end


@deprecate(
    workpartition(A::AbstractArray, n::Integer, i::Integer),
    workpart(A, 1::n, i)
)

@deprecate(
    threadpartition(A::AbstractArray, n_threads::Integer = length(allthreads()), i::Integer = threadid()),
    workpart(A, 1::n_threads, i)
)
