# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using ParallelProcessingTools
using Test

import ThreadPinning

@testset "ext_threadpinning" begin
    ParallelProcessingToolsThreadPinningExt = Base.get_extension(ParallelProcessingTools, :ParallelProcessingToolsThreadPinningExt)
    @test ParallelProcessingToolsThreadPinningExt isa Module

    @test pinthreads_auto() isa Nothing
end
