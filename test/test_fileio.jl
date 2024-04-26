# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools


@testset "fileio" begin
    mktempdir() do dir
        data1 = "Hello"
        data2 = "World"

        fn1 = joinpath(dir, "hello.txt")
        fn2 = joinpath(dir, "world.txt")

        create_files(fn1, fn2) do fn1, fn2
            write(fn1, data1)
            write(fn2, data2)
        end

        @test read(fn1, String) == data1 && read(fn2, String) == data2
    end
end
