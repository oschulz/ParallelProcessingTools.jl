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
        end) == allthreads()
    end

    @testset "interactive threadpool" begin
        @test allthreads() == Threads.threadpooltids(:default)

        prog = """
        using ParallelProcessingTools, Base.Threads
        @assert nthreads(:interactive) == 1 && nthreads(:default) == 2
        @assert allthreads() == Threads.threadpooltids(:default)
        tl = ThreadLocal(0)
        @onthreads allthreads() tl[] = threadid()
        @assert getallvalues(tl) == allthreads()
        tl2 = ThreadLocal{Vector{Int}}()
        @onthreads allthreads() push!(tl2[], threadid())
        @assert sort!(reduce(vcat, getallvalues(tl2))) == allthreads()
        println("OK")
        """
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$(Base.active_project()) -t 2,1 -e $prog`
        @test strip(read(cmd, String)) == "OK"
    end

    @testset "current-thread fast path" begin
        tl = ThreadLocal(0)
        @onthreads threadid() tl[] = threadid() + 100
        @test tl[] == threadid() + 100
    end

    @testset "non-contiguous threadsel" begin
        @test (begin
            tl = ThreadLocal(0)
            @onthreads reverse(collect(allthreads())) tl[] = threadid()
            getallvalues(tl)
        end) == allthreads()

        if nthreads() >= 3
            tl = ThreadLocal(0)
            threadsel = allthreads()[[1, end]]
            @onthreads threadsel tl[] = threadid()
            @test getallvalues(tl)[[1, end]] == threadsel
            @test all(iszero, getallvalues(tl)[2:end-1])
        end
    end


    @testset "macro mt_out_of_order" begin
        @test_throws ErrorException @macroexpand @mt_out_of_order 42

        @test begin
            b = 0
            foo() = b = 9
            bar() = 33

            @mt_out_of_order begin
                a = (sleep(0.05); 42)
                foo()
                c::Int = bar()

                d = :trivial
            end
            (a, b, c, d) == (42, 9, 33, :trivial)
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
                # Assuming 4 threads in the default threadpool:
                tl = ThreadLocal(42)
                threadsel = allthreads()[2:3]
                @onthreads threadsel begin
                    tl[] = Base.Threads.threadid()
                end
                @test getallvalues(tl)[2:3] == threadsel
                @test getallvalues(tl)[[1,4]] == fill(42, 2)
            end
        end
    end
end
