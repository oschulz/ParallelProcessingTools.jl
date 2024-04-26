# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using ParallelProcessingTools
using Test

using Base.Threads

@testset "threadsafe" begin
    
    @testset "ThreadSafeReentrantLock" begin
        tsReLock = @inferred ThreadSafeReentrantLock()
    end
    
    @testset "LockableValue" begin
        lv = @inferred LockableValue{Array{Float64,1}}([2.5, 3.4, 7.0])
        @test typeof(lv) <: LockableValue{Array{Float64, 1}}

        f = x::Array{Float64,1} -> x .+ 1.0
        res = @inferred broadcast(f, lv)
        @test res ≈ [3.5, 4.4, 8.0]
        res = @inferred map(f, lv)
        @test res ≈ [3.5, 4.4, 8.0]
    end

    @testset "LockableIO" begin
        lv = @inferred LockableIO(IOBuffer())
        @test typeof(lv) <: LockableIO{typeof(IOBuffer())}
        
        f = s -> write(s, 10)
        broadcast(f, lv)
        broadcast(seekstart, lv)
        @test read(lv, Int) == 10

        map(f, lv)
        map(seekstart, lv)
        @test read(lv, Int) == 10
        map(seekstart, lv)
        @test read!(lv, Int) == 10

        map(seekstart, lv)        
        write(lv, 11)
        map(seekstart, lv)
        @test read(lv, Int) == 11
    end

    @testset "critical" begin
        @threads for i in 1:nthreads()
            @critical @info Base.Threads.threadid()
        end
    end    
end
