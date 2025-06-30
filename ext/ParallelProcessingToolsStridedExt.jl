# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

module ParallelProcessingToolsStridedExt


using ParallelProcessingTools
using ParallelProcessingTools: PPTypeAdapter, _LinIndexCPUArrayLike
import ParallelProcessingTools: pp_adapter, pp_module_adapter, _ppt_adapt_storage

import Strided

@inline pp_adapter(::Type{Strided.StridedView}) = PPTypeAdapter{Strided.StridedView}()
@inline pp_module_adapter(::Val{nameof(Strided)}) = pp_adapter(Strided.StridedView)
# Only adapt CPU arrays with linear indexing to StridedView:
_ppt_adapt_storage(::PPTypeAdapter{Strided.StridedView}, A::_LinIndexCPUArrayLike) = Strided.StridedView(A)


end # module ParallelProcessingToolsStridedExt
