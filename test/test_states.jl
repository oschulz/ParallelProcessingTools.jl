# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using ParallelProcessingTools: getlabel, isactive, hasfailed, whyfailed

@testset "states" begin
    good_task = Threads.@spawn 42
    bad_task = Threads.@spawn error("Some error")

    @static if Sys.isunix()
        good_process = open(`true`)
        bad_process = open(`false`)
    elseif Sys.iswindows()
        good_process = open(`cmd /C "exit 0"`)
        bad_process = open(`cmd /C "exit 1"`)
    else
        error("Unsupported OS")
    end

    sleep(2)

    @testset "getlabel" begin
        @test getlabel(missing) isa String
        @test getlabel(good_task) isa String
        @test getlabel(bad_task) isa String
        @test getlabel(good_process) isa String
        @test getlabel(bad_process) isa String
    end

    @testset "isactive" begin
        @test isactive(missing) == true
        @test isactive(good_task) == false
        @test isactive(bad_task) == false
        @test isactive(good_process) == false
        @test isactive(bad_process) == false
    end

    @testset "hasfailed" begin
        @test hasfailed(missing) == false
        @test hasfailed(good_task) == false
        @test hasfailed(bad_task) == true
        @test hasfailed(good_process) == false
        @test hasfailed(bad_process) == true
    end

    @testset "whyfailed" begin
        @test_throws ArgumentError whyfailed(missing)
        @test_throws ArgumentError whyfailed(good_task)
        @test_throws ArgumentError whyfailed(good_process)

        @test whyfailed(bad_task) isa ErrorException
        @test whyfailed(bad_process) == ParallelProcessingTools.NonZeroExitCode(1)
    end
end
