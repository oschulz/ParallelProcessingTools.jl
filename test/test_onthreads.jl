# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Base.Threads


@testset "distexec" begin
    @testset "threads-init" begin
        @test nthreads() >= 2
    end

    @testset "onprocs" begin
        @test (begin
            tl = ThreadLocal(0)
            @onthreads allthreads() tl[] = threadid()
            getallvalues(tl)
        end) == 1:nthreads()
    end

    @testset "Examples" begin
        @testset "Example 1" begin
            tlsum = ThreadLocal(0.0)
            data = rand(100)
            @onthreads allthreads() begin
                tlsum[] = sum(workpart(data, allthreads(), Base.Threads.threadid()))
            end
            @test sum(getallvalues(tlsum)) ≈ sum(data)
        end

        if nthreads() >= 4
            @testset "Example 2" begin
                # Assuming 4 threads:
                tl = ThreadLocal(42)
                threadsel = 2:3
                @onthreads threadsel begin
                    tl[] = Base.Threads.threadid()
                end
                @test getallvalues(tl)[threadsel] == [2, 3]
                @test getallvalues(tl)[[1,4]] == [42, 42]
            end
        end
    end
end
