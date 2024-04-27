# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools


@testset "util" begin
    if Sys.islinux()
        sleep_test_precision = 1
    else
        sleep_test_precision = 5
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

        @test measure_idle_sleep(0, 10e-6, 100e-6, ntimes = 10000) < sleep_test_precision * 1e-6
        @test 5e-6 < measure_idle_sleep(1, 10e-6, 100e-6, ntimes = 1000) < sleep_test_precision * 15e-6
        @test 10e-6 < measure_idle_sleep(2, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 25e-6
        @test 15e-6 < measure_idle_sleep(5, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 35e-6
        @test 30e-6 < measure_idle_sleep(10, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 40e-6
        @test 50e-6 < measure_idle_sleep(100, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 80e-6
        @test 85e-6 < measure_idle_sleep(100000, 10e-6, 100e-6, ntimes = 100) < sleep_test_precision * 120e-6
    end
end
