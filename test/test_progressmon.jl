# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed


@testset "progressmon" begin
end


#!!!!!!!!!!

using ParallelProcessingTools
using ParallelProcessingTools: g_progress_channel, g_progress_states, _total_progress
a = ProgressTracker("foo")
push!(a, 0.1)

sleep(2)
isnothing(g_progress_channel) || isopen(g_progress_channel)
_total_progress(g_progress_states)
ParallelProcessingTools._progresss_channel_impl(g_progress_channel)
