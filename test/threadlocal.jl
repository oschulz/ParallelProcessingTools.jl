# This file is a part of BAT.jl, licensed under the MIT License (MIT).

using MultiThreadingTools
using Compat.Test
using Base.Threads

@testset "threadlocal" begin
    
    @testset "ThreadLocal" begin
        tl = @inferred ThreadLocal{Float32}()
        @test typeof(tl) <: ThreadLocal{Float32}
        @test length(tl.value) == nthreads()

        @test_throws ArgumentError ThreadLocal{Float32}(Array{Float32}(nthreads()+1))
        
        tl = @inferred ThreadLocal{Float64}(ones(Float64, nthreads()))
        @test tl[] ≈ one(Float64)
        
        tmp = 2.5
        tl = @inferred ThreadLocal(tmp)
        tmp = 0.0
        @test tl[] ≈ 2.5

        tmpF = () -> 3.0
        tl = @inferred ThreadLocal(tmpF)
        @test tl[] ≈ 3.0

        tl[] = 1.0
        @test tl[] ≈ 1.0

        @test get(tl) == tl[]
        @test get(tl, tmpF) ≈ 1.0
        @test get!(tmpF, tl) ≈ 1.0
        @test get!(tl, 2.0) ≈ 1.0        
        
        tmpF = () -> "test"
        tl = @inferred ThreadLocal{String}()        

        @test get(tmpF, tl) == "test"
        @test get(tl, "default") == "default"

        @test get!(tmpF, tl) == "test"
        @test get(tl) == "test"
        
        tl = @inferred ThreadLocal{String}()
        @test get!(tl, "default") == "default"
        @test get(tl) == "default"

        @test threadlocal(3) == 3
        @test threadlocal(tl) == "default"

        @test all_thread_values(tl) == tl.value

    end
    
end
