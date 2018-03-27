# This file is a part of BAT.jl, licensed under the MIT License (MIT).

using MultiThreadingTools
using Compat.Test

@testset "threadsafe" begin
    @testset "ThreadSafe" begin
        tsReLock = @inferred ThreadSafeReentrantLock()
        
    end
end

