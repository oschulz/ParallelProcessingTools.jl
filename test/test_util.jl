# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools


@testset "util" begin
    function measure_sleep_ns(t_s; ntimes)
        t_ns = round(Int64, t_s * 1e9)
        sleep_ns(t_ns)
        minimum(broadcast(1:10) do _
            inv(ntimes) * @elapsed for _ in 1:ntimes
                sleep_ns(t_ns)
            end
        end)
    end

    @test measure_sleep_ns(0e-6, ntimes = 10000) < 1e-6
    @test 0.5e-6 < measure_sleep_ns(1e-6, ntimes = 10000) < 2e-6
    @test 5e-6 < measure_sleep_ns(10e-6, ntimes = 1000) < 15e-6
    @test 50e-6 < measure_sleep_ns(100e-6, ntimes = 100) < 150e-6
    @test 500e-6 < measure_sleep_ns(1000e-6, ntimes = 10) < 1500e-6
    @test 5000e-6 < measure_sleep_ns(10000e-6, ntimes = 1) < 15000e-6
    @test 50000e-6 < measure_sleep_ns(100000e-6, ntimes = 1) < 150000e-6

    function measure_idle_sleep(n_idle, t_interval_s, t_max_s; ntimes)
        idle_sleep(n_idle, t_interval_s, t_max_s)
        minimum(broadcast(1:10) do _
            inv(ntimes) * @elapsed for _ in 1:ntimes
                idle_sleep(n_idle, t_interval_s, t_max_s)
            end
        end)
    end

    @test measure_idle_sleep(0, 10e-6, 100e-6, ntimes = 10000) < 1e-6
    @test 5e-6 < measure_idle_sleep(1, 10e-6, 100e-6, ntimes = 1000) < 15e-6
    @test 10e-6 < measure_idle_sleep(2, 10e-6, 100e-6, ntimes = 100) < 25e-6
    @test 15e-6 < measure_idle_sleep(5, 10e-6, 100e-6, ntimes = 100) < 35e-6
    @test 30e-6 < measure_idle_sleep(10, 10e-6, 100e-6, ntimes = 100) < 40e-6
    @test 50e-6 < measure_idle_sleep(100, 10e-6, 100e-6, ntimes = 100) < 80e-6
    @test 85e-6 < measure_idle_sleep(100000, 10e-6, 100e-6, ntimes = 100) < 120e-6
end
