module ParallelProcessingToolsThreadPinningExt

import ParallelProcessingTools
import LinearAlgebra
import Distributed
import ThreadPinning


# ThreadPinning.jl does not fully support all operating systems, currently:
const _threadpinning_supported = try
    @assert convert(Int, ThreadPinning.getcpuid()) isa Int
    true
catch err
    false
end


@static if _threadpinning_supported

function ParallelProcessingTools._pinthreads_auto_impl(::Val{true})
    pid = Distributed.myid()
    if Distributed.myid() == 1
        @debug "On process $pid, leaving Julia threads unpinned"
        let n_juliathreads = Threads.nthreads()
            if n_juliathreads > 1
                LinearAlgebra.BLAS.set_num_threads(n_juliathreads)
            end
        end
    else
        @debug "On process $pid, pinning threads according to affinity mask"
        let available_cpus = _ThreadPinning.Utility.affinitymask2cpuids(ThreadPinning.getaffinity())
            ThreadPinning.pinthreads(:affinitymask)
            LinearAlgebra.BLAS.set_num_threads(length(available_cpus))
        end
    end
end


ParallelProcessingTools._getcpuids_impl(::Val{true}) = ThreadPinning.getcpuids()

end # if _threadpinning_supported

end # module ChangesOfVariablesInverseFunctionsExt
