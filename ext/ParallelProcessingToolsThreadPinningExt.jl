module ParallelProcessingToolsThreadPinningExt

import ParallelProcessingTools
import LinearAlgebra
import Distributed
import ThreadPinning


@static if isdefined(ThreadPinning, :Utility)
    const _threadpinning_supported = true #!!!!!!!!!!!!!
    _get_available_cpus() = ThreadPinning.Utility.affinitymask2cpuids(ThreadPinning.getaffinity())
else # ThreadPinning v0.7
    # ThreadPinning.jl does not support all operating systems, currently:
    const _threadpinning_supported = isdefined(ThreadPinning, :affinitymask2cpuids)

    _get_available_cpus() = ThreadPinning.affinitymask2cpuids(ThreadPinning.get_affinity_mask())
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
        let available_cpus = _get_available_cpus()
            ThreadPinning.pinthreads(:affinitymask)
            LinearAlgebra.BLAS.set_num_threads(length(available_cpus))
        end
    end
end


ParallelProcessingTools._getcpuids_impl(::Val{true}) = ThreadPinning.getcpuids()


end # if _threadpinning_supported

end # module ChangesOfVariablesInverseFunctionsExt
