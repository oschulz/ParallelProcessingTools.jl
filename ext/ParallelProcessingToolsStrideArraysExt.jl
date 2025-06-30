# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

module ParallelProcessingToolsStrideArraysExt

using ParallelProcessingTools
using ParallelProcessingTools: PPTypeAdapter, _LinIndexCPUArrayLike
import ParallelProcessingTools: pp_adapter, pp_module_adapter, _ppt_adapt_storage
    
@inline pp_adapter(::Type{StrideArrays.StrideArray}) = PPTypeAdapter{StrideArrays.StrideArray}()
@inline pp_module_adapter(::Val{nameof(StrideArrays)}) = pp_adapter(StrideArrays.StrideArray)
# Only adapt CPU arrays with linear indexing to StrideArray:
_ppt_adapt_storage(::PPTypeAdapter{StrideArrays.StrideArray}, A::_LinIndexCPUArrayLike) = StrideArrays.StrideArray(A)

end # module ParallelProcessingToolsStrideArraysExt
