# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using ParallelProcessingTools: TimelimitExceeded


@testset "waiting" begin
    if Sys.islinux()
        sleep_test_precision = 2
    elseif Sys.isapple()
        sleep_test_precision = 10
    else
        sleep_test_precision = 3
    end

    @testset "sleep_ns" begin
        function measure_sleep_ns(t_s; ntimes)
            t_ns = round(Int64, t_s * 1e9)
            sleep_ns(t_ns)
            minimum(broadcast(1:10) do _
                inv(ntimes) * @elapsed for _ in 1:ntimes
                    sleep_ns(t_ns)
                end
            end)
        end

        @test measure_sleep_ns(0e-6, ntimes = 10000) < sleep_test_precision * 1e-6
        @test 0.5e-6 < measure_sleep_ns(1e-6, ntimes = 10000) < sleep_test_precision * 2e-6
        @test 5e-6 < measure_sleep_ns(10e-6, ntimes = 1000) < sleep_test_precision * 15e-6
        @test 50e-6 < measure_sleep_ns(100e-6, ntimes = 100) < sleep_test_precision * 150e-6
        @test 500e-6 < measure_sleep_ns(1000e-6, ntimes = 10) < sleep_test_precision * 1500e-6
        @test 5000e-6 < measure_sleep_ns(10000e-6, ntimes = 1) < sleep_test_precision * 15000e-6
        @test 50000e-6 < measure_sleep_ns(100000e-6, ntimes = 1) < sleep_test_precision * 150000e-6
    end

    @testset "idle_sleep" begin
        function measure_idle_sleep(n_idle, t_interval_s, t_max_s; ntimes)
            idle_sleep(n_idle, t_interval_s, t_max_s)
            minimum(broadcast(1:10) do _
                inv(ntimes) * @elapsed for _ in 1:ntimes
                    idle_sleep(n_idle, t_interval_s, t_max_s)
                end
            end)
        end

        @test measure_idle_sleep(0, 10e-6, 100e-6, ntimes = 10000) < sleep_test_precision * 2e-6
        @test 5e-6 < measure_idle_sleep(1, 10e-6, 100e-6, ntimes = 1000) < sleep_test_precision * 15e-6
        @test 10e-6 < measure_idle_sleep(2, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 25e-6
        @test 15e-6 < measure_idle_sleep(5, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 35e-6
        @test 30e-6 < measure_idle_sleep(10, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 40e-6
        @test 50e-6 < measure_idle_sleep(100, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 80e-6
        @test 85e-6 < measure_idle_sleep(100000, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 120e-6
    end

    @testset "wait_while" begin
        t0 = time()
        task = Threads.@spawn sleep(5)
        timer = Timer(0.2)
        @wait_while !istaskdone(task) && isopen(timer)
        @test istaskdone(task) == false
        @test time() - t0 < 3

        @test_throws ArgumentError @wait_while maxtime true
        @test_throws ArgumentError @wait_while someopt=1 true
        @test_throws TimelimitExceeded @wait_while maxtime=0.25 timeout_error=true true
        @timed(@wait_while maxtime=-0.5 true).time < 0.1
        t = Timer(2); 0.3 < @timed(@wait_while maxtime=0.5 isopen(t)).time < 0.7
        t = Timer(0.5); 0.3 < @timed(@wait_while timeout_error=true isopen(t)).time < 0.7
    end

    @testset "wait_for_any" begin
        @test wait_for_any(nothing) isa Nothing
        @test wait_for_any(nothing, nothing, nothing) isa Nothing
        @test wait_for_any([nothing, nothing, nothing]) isa Nothing

        t0 = time()
        wait_for_any(Timer(0.5))
        @test 0.1 < time() - t0 < 0.9

        @test_throws TimelimitExceeded wait_for_any(Timer(0.5), maxtime = 0.1, timeout_error = true)
        
        t0 = time()
        task1 = Threads.@spawn sleep(0.2)
        task2 = Threads.@spawn sleep(0.6)
        wait_for_any(task1, task2, maxtime = 0.4, timeout_error = true)
        @test istaskdone(task1) == true
        @test istaskdone(task2) == false
        @test 0.1 < time() - t0 < 0.5

        t0 = time()
        task1 = Threads.@spawn sleep(0.4)
        task2 = Threads.@spawn sleep(0.6)
        @test_throws TimelimitExceeded wait_for_any(task1, task2, maxtime = 0.1, timeout_error = true)

        t0 = time()
        task1 = Threads.@spawn sleep(0.2)
        task2 = Threads.@spawn sleep(0.6)
        wait_for_any([task1, task2], maxtime = 0.4, timeout_error = true)
        @test istaskdone(task1) == true
        @test istaskdone(task2) == false
        @test 0.1 < time() - t0 < 0.5

        t0 = time()
        task1 = Threads.@spawn sleep(0.4)
        task2 = Threads.@spawn sleep(0.6)
        @test_throws TimelimitExceeded wait_for_any([task1, task2], maxtime = 0.1, timeout_error = true)
    end

    @testset "wait_for_all" begin
        @test wait_for_all(nothing) isa Nothing
        @test wait_for_all(nothing, nothing, nothing) isa Nothing
        @test wait_for_all([nothing, nothing, nothing]) isa Nothing

        t0 = time()
        wait_for_all(Timer(1))
        @test 0.5 < time() - t0 < 3

        t0 = time()
        @test_throws TimelimitExceeded wait_for_all(Timer(5); maxtime = 0.4, timeout_error = true)
        @test 0.2 < time() - t0 < 0.6

        t0 = time()
        task1 = Threads.@spawn sleep(1)
        task2 = Threads.@spawn sleep(0.1)
        wait_for_all(task1, nothing, task2)
        @test 0.8 < time() - t0 < 3

        t0 = time()
        task1 = Threads.@spawn sleep(1)
        task2 = Threads.@spawn sleep(0.1)
        wait_for_all([task1, nothing, task2])
        @test 0.8 < time() - t0 < 3

        t0 = time()
        task1 = Threads.@spawn sleep(1)
        task2 = Threads.@spawn sleep(0.1)
        @test_throws TimelimitExceeded wait_for_all(task1, nothing, task2; maxtime = 0.4, timeout_error = true)
        @test 0.2 < time() - t0 < 0.6

        t0 = time()
        task1 = Threads.@spawn sleep(1)
        task2 = Threads.@spawn sleep(0.1)
        @test_throws TimelimitExceeded wait_for_all([task1, nothing, task2]; maxtime = 0.4, timeout_error = true)
        @test 0.2 < time() - t0 < 0.6
    end
end
