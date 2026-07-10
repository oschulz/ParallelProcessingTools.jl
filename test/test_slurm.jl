# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using ParallelProcessingTools: _slurm_parse_memoptval, _slurm_parse_intoptval,
    _get_slurm_taskconf, _slurm_nworkers, _slurm_mem_per_task

@testset "slurm" begin
    @testset "SLURM option values" begin
        @test _slurm_parse_memoptval(nothing) === nothing
        @test _slurm_parse_memoptval("100") == 100 * 1024^2
        @test _slurm_parse_memoptval("16K") == 16 * 1024
        @test _slurm_parse_memoptval("2M") == 2 * 1024^2
        @test _slurm_parse_memoptval("32G") == 32 * 1024^3
        @test _slurm_parse_memoptval("32GB") == 32 * 1024^3
        @test _slurm_parse_memoptval("1T") == 1024^4
        @test_throws ArgumentError _slurm_parse_memoptval("32Q")
        @test_throws ArgumentError _slurm_parse_memoptval("foo")

        @test _slurm_parse_intoptval(nothing) === nothing
        @test _slurm_parse_intoptval("42") == 42
    end

    @testset "SLURM task configuration" begin
        no_env = Dict{String,String}()

        tc = _get_slurm_taskconf(``, no_env)
        @test tc == (
            n_tasks = nothing, cpus_per_task = nothing, mem_per_cpu = nothing,
            n_nodes = nothing, ntasks_per_node = nothing, mem_per_node = nothing
        )

        tc = _get_slurm_taskconf(`--ntasks=4 --cpus-per-task=8 --mem-per-cpu=2G`, no_env)
        @test tc == (
            n_tasks = 4, cpus_per_task = 8, mem_per_cpu = 2 * 1024^3,
            n_nodes = nothing, ntasks_per_node = nothing, mem_per_node = nothing
        )

        tc = _get_slurm_taskconf(`-n 4 -c8 -N 2 --mem=16G --ntasks-per-node=2`, no_env)
        @test tc == (
            n_tasks = 4, cpus_per_task = 8, mem_per_cpu = nothing,
            n_nodes = 2, ntasks_per_node = 2, mem_per_node = 16 * 1024^3
        )

        slurm_env = Dict(
            "SLURM_NTASKS" => "6", "SLURM_CPUS_PER_TASK" => "2",
            "SLURM_MEM_PER_CPU" => "1G", "SLURM_JOB_NUM_NODES" => "3"
        )
        tc = _get_slurm_taskconf(``, slurm_env)
        @test tc == (
            n_tasks = 6, cpus_per_task = 2, mem_per_cpu = 1024^3,
            n_nodes = 3, ntasks_per_node = nothing, mem_per_node = nothing
        )

        tc = _get_slurm_taskconf(`--ntasks=12`, slurm_env)
        @test tc.n_tasks == 12
        @test tc.cpus_per_task == 2

        # Unknown options are skipped, separate-value long options work:
        tc = _get_slurm_taskconf(`--partition=main --ntasks 4`, no_env)
        @test tc.n_tasks == 4

        @test_throws ArgumentError _get_slurm_taskconf(`-n`, no_env)
        @test_throws ArgumentError _get_slurm_taskconf(`-n -c4`, no_env)
        @test_throws ArgumentError _get_slurm_taskconf(`--ntasks`, no_env)
        @test_throws ArgumentError _get_slurm_taskconf(`--ntasks=`, no_env)
        @test_throws ArgumentError _get_slurm_taskconf(`--ntasks --nodes=2`, no_env)
    end

    @testset "workers and memory per task" begin
        template = (
            n_tasks = nothing, cpus_per_task = nothing, mem_per_cpu = nothing,
            n_nodes = nothing, ntasks_per_node = nothing, mem_per_node = nothing
        )

        @test _slurm_nworkers(merge(template, (n_tasks = 4,))) == 4
        @test _slurm_nworkers(merge(template, (n_nodes = 2, ntasks_per_node = 3))) == 6
        @test_throws ArgumentError _slurm_nworkers(template)

        @test _slurm_mem_per_task(merge(template, (cpus_per_task = 4, mem_per_cpu = 1024^3))) == 4 * 1024^3
        @test _slurm_mem_per_task(merge(template, (n_nodes = 2, ntasks_per_node = 4, mem_per_node = 8 * 1024^3))) == 2 * 1024^3
        @test _slurm_mem_per_task(merge(template, (n_nodes = 2, n_tasks = 4, mem_per_node = 8 * 1024^3))) == 4 * 1024^3
        @test _slurm_mem_per_task(template) === nothing
    end

    @testset "worker_start_command" begin
        manager = ParallelProcessingTools.ppt_cluster_manager()
        runmode = OnSlurm(
            slurm_flags = `--ntasks=2 --cpus-per-task=4 --mem-per-cpu=1G`,
            julia_flags = `--depwarn=yes`
        )
        cmd, m, n = worker_start_command(runmode, manager)
        @test m == 1
        @test n == 2
        cmd_string = string(cmd)
        @test first(cmd.exec) == "srun"
        @test count("--depwarn=yes", cmd_string) == 1
        @test occursin("--threads=4", cmd_string)
        @test occursin("--heap-size-hint=2048M", cmd_string)
    end
end
