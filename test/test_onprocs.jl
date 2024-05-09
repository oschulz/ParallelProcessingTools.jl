# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed

include("testtools.jl")


@testset "onprocs" begin
    @testset "worker-init" begin
        if length(workers()) < 2
            classic_addprocs(2)
        end
        eval(:(@everywhere using Distributed))
        @test length(workers()) >= 2
    end

    @testset "macro onprocs" begin
        @everywhere using ParallelProcessingTools, Base.Threads

        @test (@onprocs workers() myid()) == workers()

        threadinfo = [collect(1:n) for n in [fetch(@spawnat w nthreads()) for w in workers()]]
        ref_result = ((w,t) -> (proc = w, threads = t)).(workers(), threadinfo)

        @test (@onprocs workers() begin
            tl = ThreadLocal(0)
            @onthreads allthreads() tl[] = threadid()
            (proc = myid(), threads = getallvalues(tl))
        end) == ref_result
    end

    @testset "Examples" begin
        @test begin
            workers() == (@onprocs workers() myid())
        end
    end
end
