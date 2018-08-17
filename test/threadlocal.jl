# This file is a part of BAT.jl, licensed under the MIT License (MIT).

using ParallelProcessingTools
using Test
using Base.Threads

@testset "threadlocal" begin
    @testset "ThreadLocal" begin
        tl = @inferred ThreadLocal{Float32}(undef)
        @test typeof(tl) <: ThreadLocal{Float32}
        @test length(tl.value) == nthreads()

        tmp = 2.5
        tl = @inferred ThreadLocal(tmp)
        tmp = 0.0
        @test tl[] ≈ 2.5

        tl[] = 1.0
        @test tl[] ≈ 1.0

        tmpF = () -> 3.0

        @test get(tl) == tl[]
        @test get(tl, tmpF) ≈ 1.0
        @test get!(tmpF, tl) ≈ 1.0
        @test get!(tl, 2.0) ≈ 1.0        

        tmpF = () -> "test"
        tl = @inferred ThreadLocal{String}(undef)

        @test get(tmpF, tl) == "test"
        @test get(tl, "default") == "default"

        @test get!(tmpF, tl) == "test"
        @test get(tl) == "test"
        
        tl = @inferred ThreadLocal{String}(undef)
        @test get!(tl, "default") == "default"
        @test get(tl) == "default"

        @test threadlocal(3) == 3
        @test threadlocal(tl) == "default"

        @test threadglobal(tl) == tl.value
    end
end
