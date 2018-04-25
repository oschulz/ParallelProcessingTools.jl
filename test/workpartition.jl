# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using MultiThreadingTools
using Compat.Test

@testset "workpartition" begin
    
    @testset "workpartition" begin
        num = 99
        part = 7
        tmp = div(num, part)
        cmp = [tmp, tmp+1]
        old = 0
        for j=1:part
            res = @inferred MultiThreadingTools._workpartition_hi(num, part, j)
            @test  res - old in cmp
            old = res
        end
        res = @inferred MultiThreadingTools._workpartition_hi(Int32(99), Int32(7), Int32(7))
        @test res == Int32(99)
        @test typeof(res) <: Int32
        @test_throws AssertionError MultiThreadingTools._workpartition_hi(-1, 7, 1)
        @test_throws AssertionError MultiThreadingTools._workpartition_hi(20, 0, 1)
        @test_throws AssertionError MultiThreadingTools._workpartition_hi(20, 7, -1)
        @test_throws AssertionError MultiThreadingTools._workpartition_hi(0, 7, 8)

        res = Array{Int}([])
        num = 24
        part = 6
        tmp = div(num, part)
        cmp = [tmp, tmp+1]
        for i =1:part
            tmp = @inferred MultiThreadingTools._workpartition_impl(num, part, i)
            @test length(tmp) in cmp
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
        cmp = rand(num)
        res = Array{Float64}([])
                
        for i =1:part
            res = vcat(res, @inferred workpartition(cmp, part, i))
        end
        @test res == cmp

        res = Array{Float64}([])
        for i=workpartitions(cmp, part)
            res = vcat(res, i)
        end
        @test res == cmp        
    end
end
