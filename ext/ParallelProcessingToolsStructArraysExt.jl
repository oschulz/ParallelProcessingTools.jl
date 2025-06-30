# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

module ParallelProcessingToolsStructArraysExt

using ParallelProcessingTools
import ParallelProcessingTools: parallel_copyto!

using StructArrays: StructArray, components

function parallel_copyto!(A::StructArray{T,N}, B::StructArray{T,N}) where {T,N}
    map(parallel_copyto!, components(A), components(B))
    return A
end

end # module ParallelProcessingToolsStructArraysExt
