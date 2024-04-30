# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

import Test

import ThreadPinning
ThreadPinning.Prefs.set_os_warning(false)

Test.@testset "Package ParallelProcessingTools" begin
    @info "Testing with $(Base.Threads.nthreads()) Julia threads."

    include("test_aqua.jl")
    include("test_waiting.jl")
    include("test_states.jl")
    include("test_fileio.jl")
    include("test_threadsafe.jl")
    include("test_threadlocal.jl")
    include("test_workpartition.jl")
    include("test_onthreads.jl")
    include("test_onprocs.jl")
    include("test_procinit.jl")
    include("test_workerpool.jl")
    include("test_onworkers.jl")
    include("test_deprecated.jl")
    include("test_docs.jl")
end # testset
