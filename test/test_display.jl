# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using ParallelProcessingTools: in_vscode_notebook, printover

@testset "display" begin
    withenv("VSCODE_CWD" => nothing) do
        @test in_vscode_notebook() == false

        io = IOBuffer()
        printover(io) do tmpio
            println(tmpio, "foo")
            println(tmpio, "bar")
        end
        output = String(take!(io))
        @test occursin("foo", output)
        @test occursin("bar", output)
    end

    withenv("VSCODE_CWD" => pwd()) do
        @test in_vscode_notebook() == true

        io = IOBuffer()
        printover(io) do tmpio
            println(tmpio, "foo")
            println(tmpio, "bar")
        end
        output = String(take!(io))
        @test occursin("foo | bar", output)
    end
end
