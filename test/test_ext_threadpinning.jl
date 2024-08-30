# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using ParallelProcessingTools
using Test

import ThreadPinning

@testset "ext_threadpinning" begin
    @test ThreadPinning.pinthreads(AutoThreadPinning()) isa Nothing
end
