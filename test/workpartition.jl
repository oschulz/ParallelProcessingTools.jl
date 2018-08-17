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
            res = @inferred ParallelProcessingTools._workpartition_hi(num, part, j)
            @test res - old in cmp_res
            old = res
        end
        res = @inferred ParallelProcessingTools._workpartition_hi(Int32(99), Int32(7), Int32(7))
        @test res == Int32(99)
        @test typeof(res) <: Int32
        @test_throws AssertionError ParallelProcessingTools._workpartition_hi(-1, 7, 1)
        @test_throws AssertionError ParallelProcessingTools._workpartition_hi(20, 0, 1)
        @test_throws AssertionError ParallelProcessingTools._workpartition_hi(20, 7, -1)
        @test_throws AssertionError ParallelProcessingTools._workpartition_hi(0, 7, 8)

        res = Array{Int}([])
        num = 24
        part = 6
        tmp = div(num, part)
        cmp_res = [tmp, tmp+1]
        for i =1:part
            tmp = @inferred ParallelProcessingTools._workpartition_impl(num, part, i)
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
            res = vcat(res, @inferred workpartition(fi:stp:num, part, i))
        end
        @test res == collect(fi:stp:num)

        res = Array{Int}([])
        num = 14
        part = 3
        fi = 7
                
        for i =1:part
            res = vcat(res, @inferred workpartition(UnitRange(fi:num), part, i))
        end
        @test res == collect(fi:num)

        num = 20
        part = 3
        cmp_res = rand(num)
        res = Array{Float64}([])
                
        for i =1:part
            res = vcat(res, @inferred workpartition(cmp_res, part, i))
        end
        @test res == cmp_res

        res = Array{Float64}([])
        for i=workpartitions(cmp_res, part)
            res = vcat(res, i)
        end
        @test res == cmp_res
    end
end
