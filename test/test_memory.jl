# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

@testset "memory" begin
    @testset "memory_limit" begin
        @test @inferred(memory_limit()) isa Tuple{<:Integer,<:Integer}
        limit = Int(min(typemax(Int), 8 * Int64(1024)^3))
        new_limits = (limit, -1)
        if Sys.islinux()
            @test @inferred(memory_limit!(new_limits...)) == new_limits
            @test @inferred(memory_limit()) == new_limits
            stricter_limit = round(Int, 0.9*limit)
            @test_throws ArgumentError @inferred(memory_limit!(limit, stricter_limit))
        else
            @test @inferred(memory_limit!(new_limits...)) == (-1, -1)
            @test @inferred(memory_limit()) == (-1, -1)
        end
    end
end
