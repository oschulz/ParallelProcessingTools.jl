# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using ParallelProcessingTools
using Test

import LinearAlgebra #!!!!!!! DEBUGGING
import ThreadPinning

@testset "ext_threadpinning" begin
    ParallelProcessingToolsThreadPinningExt = Base.get_extension(ParallelProcessingTools, :ParallelProcessingToolsThreadPinningExt)
    @test ParallelProcessingToolsThreadPinningExt isa Module

    @test ParallelProcessingToolsThreadPinningExt._get_available_cpus() isa AbstractVector{<:Integer}
    @test !isempty(ParallelProcessingToolsThreadPinningExt._get_available_cpus())

    @test pinthreads_auto() isa Nothing

    # DEBUGGING
    ####!!!!!!!!!!!!!!!!!!!!!!:
    let n_juliathreads = Threads.nthreads()
        if n_juliathreads > 1
            LinearAlgebra.BLAS.set_num_threads(n_juliathreads)
        end
    end
    let available_cpus = ParallelProcessingToolsThreadPinningExt._get_available_cpus()
        ThreadPinning.pinthreads(:affinitymask)
        LinearAlgebra.BLAS.set_num_threads(length(available_cpus))
    end
end
