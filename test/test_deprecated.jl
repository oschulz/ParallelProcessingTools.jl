# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed

include("testtools.jl")


@testset "deprecated" begin
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

    @testset "macro mt_async" begin
        @test_deprecated begin
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

    pids = classic_addprocs(2)
    @testset "macro mp_async" begin
        @test_deprecated begin
            n = 128
            A = Vector{Future}(undef, n)
            @sync for i in 1:n
                A[i] = @mp_async begin
                    @assert myid() != 1
                    log(i)
                end
            end
            fetch.(A) == log.(1:n)
        end
    end
    rmprocs(pids)
end
