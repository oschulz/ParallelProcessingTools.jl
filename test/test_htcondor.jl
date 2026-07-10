# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

@testset "htcondor" begin
    @testset "worker_start_command" begin
        manager = ParallelProcessingTools.ppt_cluster_manager()
        mktempdir(prefix = "ppt-htcondor-test") do dir
            runmode = OnHTCondor(
                n = 3, jobfile_dir = dir, julia_flags = `--depwarn=yes`,
                condor_settings = Dict("request_memory" => "4GB")
            )
            cmd, m, n = worker_start_command(runmode, manager)
            @test m == 1
            @test n == 3
            @test first(cmd.exec) == "condor_submit"

            submit_file = last(cmd.exec)
            @test isfile(submit_file)
            submit_content = read(submit_file, String)
            @test occursin("queue 3", submit_content)
            @test occursin("request_memory=4GB", submit_content)
            @test occursin("executable = /bin/bash", submit_content)

            worker_script = replace(submit_file, r"\.sub$" => ".sh")
            @test isfile(worker_script)
            script_content = read(worker_script, String)
            @test occursin("JULIA_DEPOT_PATH", script_content)
            @test count("--depwarn=yes", script_content) == 1
            @test occursin("--threads=1", script_content)
            @test occursin("--heap-size-hint=2048M", script_content)
        end
    end
end
