# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using ParallelProcessingTools
using Test

@testset "workpartition" begin
    
    @testset "workpartition" begin
        num = 99
        part = 7
        tmp = div(num, part)
        cmp_res = [tmp, tmp+1]
        old = 0
        for j=1:part
            res = @inferred ParallelProcessingTools._workpart_hi(num, part, j)
            @test res - old in cmp_res
            old = res
        end
        res = @inferred ParallelProcessingTools._workpart_hi(Int32(99), Int32(7), Int32(7))
        @test res == Int32(99)
        @test typeof(res) <: Int32
        @test_throws AssertionError ParallelProcessingTools._workpart_hi(-1, 7, 1)
        @test_throws AssertionError ParallelProcessingTools._workpart_hi(20, 0, 1)
        @test_throws AssertionError ParallelProcessingTools._workpart_hi(20, 7, -1)
        @test_throws AssertionError ParallelProcessingTools._workpart_hi(0, 7, 8)

        res = Array{Int}([])
        num = 24
        part = 6
        tmp = div(num, part)
        cmp_res = [tmp, tmp+1]
        for i =1:part
            tmp = @inferred ParallelProcessingTools._workpart_scheme(Base.OneTo(num), part, i)
            @test length(tmp) in cmp_res
            res = vcat(res, tmp)
        end
        @test res == collect(1:num)
        
        res = Array{Int}([])
        num = 27
        part = 3
        stp = 4
        fi = 3
                
        for i =1:part
            res = vcat(res, @inferred workpart(fi:stp:num, 1:part, i))
        end
        @test res == collect(fi:stp:num)

        res = Array{Int}([])
        num = 14
        part = 3
        fi = 7
                
        for i =1:part
            res = vcat(res, @inferred workpart(UnitRange(fi:num), 1:part, i))
        end
        @test res == collect(fi:num)

        num = 20
        part = 3
        cmp_res = rand(num)
        res = Array{Float64}([])
                
        for i =1:part
            res = vcat(res, @inferred workpart(cmp_res, 1:part, i))
        end
        @test res == cmp_res

        A = collect(1:10)
        @test workpart(A, [2, 5, 7], 5) == workpart(A, 1:3, 2)
        @test_throws ArgumentError workpart(A, [5, 2, 7], 5)
        @test_throws ArgumentError workpart(A, [2, 2, 7], 2)
        @test_throws ArgumentError workpart(A, [2, 5, 7], 3)
        @test workpart(A, 4, 4) === A
        @test_throws ArgumentError workpart(A, 4, 5)
        @test isempty(ParallelProcessingTools._workpart_scheme(Base.OneTo(10), 3, 0))
    end

    @testset "Examples" begin
        using Distributed, Base.Threads
        @test begin
            A = rand(100)
            # ...
            sub_A = workpart(A, procs(), myid())
            # ...
            @onthreads allthreads() begin
                idxs = workpart(eachindex(sub_A), allthreads(), threadid())
                for i in idxs
                    # ...
                end
            end
            true
        end
    end
end
