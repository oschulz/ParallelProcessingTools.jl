# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using ParallelProcessingTools
using Test

using Distributed

if length(workers()) < 2
    addprocs(2, exename = ParallelProcessingTools.mtjulia_exe())
end

@testset "workpartition" begin
    @testset "parallel histogramming" begin
        using Distributed, ParallelProcessingTools
        addprocs(2, exename = mtjulia_exe())
        @everywhere using ParallelProcessingTools, Base.Threads,
            DistributedArrays, Statistics, StatsBase

        data = drandn(10^8)
        procsel = procs(data)
        @onprocs procsel size(localpart(data))

        @onprocs procsel nthreads()

        proc_hists = @onprocs procsel begin
            local_data = localpart(data)
            tl_hist = ThreadLocal(Histogram((-6:0.1:6,), :left))
            @onthreads allthreads() begin
                data_for_this_thread = workpart(local_data, allthreads(), threadid())
                append!(tl_hist[], data_for_this_thread)
            end
            merged_hist = merge(getallvalues(tl_hist)...)
        end
        final_hist = merge(proc_hists...)

        @test sum(final_hist.weights) ≈ length(data)
    end
end
