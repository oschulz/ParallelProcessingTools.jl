# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using ParallelProcessingTools: getlabel, isactive, wouldwait, hasfailed, whyfailed

using Distributed: myid, remotecall

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

    running_future = remotecall(()->sleep(20), myid())
    complete_future = remotecall(()-> 42, myid())

    empty_open_channel = Channel{Int}(1)
    ready_open_channel = Channel{Int}(1)
    put!(ready_open_channel, 42)
    good_closed_channel = Channel{Int}(1)
    close(good_closed_channel)
    bad_closed_channel = Channel{Int}(1)
    close(bad_closed_channel, ErrorException("Some error"))

    active_timer = Timer(120)
    stopped_timer = Timer(0)

    active_condition = Base.AsyncCondition()
    closed_condition = Base.AsyncCondition()
    close(closed_condition)

    sleep(2)

    @testset "getlabel" begin
        @test getlabel(nothing) isa String
        @test getlabel(missing) isa String
        @test getlabel(good_task) isa String
        @test getlabel(bad_task) isa String
        @test getlabel(good_process) isa String
        @test getlabel(bad_process)  isa String
        @test getlabel(active_timer) isa String
        @test getlabel(stopped_timer) isa String
        @test getlabel(running_future) isa String
        @test getlabel(complete_future) isa String
        @test getlabel(empty_open_channel) isa String
        @test getlabel(ready_open_channel) isa String
        @test getlabel(good_closed_channel) isa String
        @test getlabel(bad_closed_channel) isa String
        @test getlabel(active_condition) isa String
        @test getlabel(closed_condition)  isa String
    end

    @testset "isactive" begin
        @test isactive(nothing)== false
        @test isactive(missing) == true
        @test isactive(good_task) == false
        @test isactive(bad_task) == false
        @test isactive(good_process) == false
        @test isactive(bad_process) == false
        @test isactive(active_timer) == true
        @test isactive(stopped_timer) == false
        @test isactive(running_future) == true
        @test isactive(complete_future) == false
        @test isactive(empty_open_channel) == true
        @test isactive(ready_open_channel) == true
        @test isactive(good_closed_channel) == false
        @test isactive(bad_closed_channel) == false
        @test isactive(active_condition) == true
        @test isactive(closed_condition) == false
    end

    @testset "wouldwait" begin
        @test wouldwait(nothing) == false
        @test_throws ArgumentError wouldwait(missing)
        @test wouldwait(good_task) == false
        @test wouldwait(bad_task) == false
        @test wouldwait(good_process) == false
        @test wouldwait(bad_process) == false
        @test wouldwait(active_timer) == true
        @test wouldwait(stopped_timer) == false
        @test wouldwait(running_future) == true
        @test wouldwait(complete_future) == false
        @test wouldwait(empty_open_channel) == true
        @test wouldwait(ready_open_channel) == false
        @test wouldwait(good_closed_channel) == false
        @test wouldwait(bad_closed_channel) == false
        @test wouldwait(active_condition) == true
        @test wouldwait(closed_condition) == false
    end

    @testset "hasfailed" begin
        @test hasfailed(nothing) == false
        @test hasfailed(missing) == false
        @test hasfailed(good_task) == false
        @test hasfailed(bad_task) == true
        @test hasfailed(good_process) == false
        @test hasfailed(bad_process) == true
        @test hasfailed(empty_open_channel) == false
        @test hasfailed(good_closed_channel) == false
        @test hasfailed(bad_closed_channel) == true
    end

    @testset "whyfailed" begin
        @test_throws ArgumentError whyfailed(nothing)
        @test_throws ArgumentError whyfailed(missing)
        @test_throws ArgumentError whyfailed(good_task)
        @test_throws ArgumentError whyfailed(good_process)

        @test whyfailed(bad_task) isa ErrorException
        @test whyfailed(bad_process) == ParallelProcessingTools.NonZeroExitCode(1)

        @test_throws ArgumentError whyfailed(empty_open_channel)
        @test whyfailed(bad_closed_channel) isa ErrorException
    end
end
