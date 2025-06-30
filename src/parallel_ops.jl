# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


const _CPUArrayLike = Union{Array, SubArray{<:Any,<:Any,<:Array}}
const _LinIndexCPUArrayLike = Union{Array, SubArray{<:Any,<:Any,<:Array,<:Any,true}}
const _NonLinIndexView = SubArray{<:Any,<:Any,<:Array,<:Any,false}


"""
    parallel_copyto!(A, B)

Semantically equivalent to `copyto!(A, B)`, but may used multi-threading or
other parallelization techniques to speed up the operation.
"""
function parallel_copyto!(A, B) end

parallel_copyto!(A, B) = copyto!(⋮(A), ⋮(B))

parallel_copyto!(A::_CPUArrayLike, B::_NonLinIndexView) = _threads_parallel_copyto!(A, B)
parallel_copyto!(A::_NonLinIndexView, B::_CPUArrayLike) = _threads_parallel_copyto!(A, B)
parallel_copyto!(A::_NonLinIndexView, B::_NonLinIndexView) = _threads_parallel_copyto!(A, B)

function _threads_parallel_copyto!(A, B)
    idxs = eachindex(A)
    idxs == eachindex(B) || throw(ArgumentError("parallel_copyto! requires A and B to have exactly equal indices."))

    # ToDo: Tune heuristic for using multi-threading:
    if length(idxs) < 1000
        copyto!(A, B)
    else
        @inbounds Base.Threads.@threads for i in idxs
            A[i] = B[i]
        end
    end

    return A
end
