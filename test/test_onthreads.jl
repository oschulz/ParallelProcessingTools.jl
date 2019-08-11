# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Base.Threads


@testset "onthreads" begin
    if nthreads() < 2
        @warn "JULIA multithreading not enabled"
    end


    function do_work(n)
        if n < 0
            throw(ArgumentError("n must be >= 0"))
        end
        s::Float64 = 0
        for i in 1:n
            if n % 1000 == 0
                yield()
            end
            s += log(abs(asin(sin(Complex(log(i), log(i))))) + 1)
        end
        s
    end


    @testset "macro onthreads" begin
        @test (begin
            tl = ThreadLocal(0)
            @onthreads allthreads() tl[] = threadid()
            getallvalues(tl)
        end) == 1:nthreads()
    end

    @testset "macro mt_async" begin
        @test begin
            n = 128
            A = zeros(n)
            @sync for i in eachindex(A)
                @mt_async begin
                    do_work(10^3)
                    A[i] = log(i)
                end
            end
            A == log.(1:n)
        end
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
