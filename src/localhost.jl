# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    OnLocalhost(;
        n::Integer = 1
        env::Dict{String,String} = Dict{String,String}()
        julia_flags::Cmd = _default_julia_flags()
        dir = pwd()
    ) isa DynamicAddProcsMode

Mode that runs `n` worker processes on the current host.

Example:

```julia
runmode = OnLocalhost(n = 4)
task, n = runworkers(runmode)

Threads.@async begin
    wait(task)
    @info "SLURM workers have terminated."
end

@wait_while nprocs()-1 < n)
```

Workers can also be started manually, use
[`worker_start_command(runmode)`](@ref) to get the system (shell) command and
run it from a separate process or so.
"""
@with_kw struct OnLocalhost <: DynamicAddProcsMode
    n::Int
    julia_flags::Cmd = _default_julia_flags()
    dir = pwd()
    env::Dict{String,String} = Dict{String,String}()
end
export OnLocalhost

function worker_start_command(runmode::OnLocalhost, manager::ElasticManager)
    julia_flags = runmode.julia_flags
    dir = runmode.dir

    jl_threads_flag = any(occursin.(Ref("--threads"), string.(julia_flags))) ? `` : `--threads=$(nthreads())`
    jl_dir_flags = `-e "cd(\"$(dir)\")"`
    additional_julia_flags = `$jl_threads_flag $julia_flags $jl_dir_flags`

    worker_cmd = worker_local_startcmd(
        manager;
        julia_flags = additional_julia_flags,
        env = runmode.env
    )
    return worker_cmd, runmode.n, runmode.n
end

function runworkers(runmode::OnLocalhost, manager::ElasticManager)
    start_cmd, m, n = worker_start_command(runmode, manager)

    task = Threads.@async begin
        processes = Base.Process[]
        for _ in 1:m
            push!(processes, open(start_cmd))
        end
        @wait_while any(isactive, processes)
    end

    return task, n
end


#=
# ToDo: Add SSHWorkers or similar:

@with_kw struct SSHWorkers <: RunProcsMode
    hosts::Vector{Any}
    ssd_flags::Cmd = _default_slurm_flags()
    julia_flags::Cmd = _default_julia_flags()
    dir = ...
    env = ...
    tunnel::Bool = false
    multiplex::Bool = false
    shell::Symbol = :posix
    max_parallel::Int = 10
    enable_threaded_blas::Bool = true
    topology::Symbol = :all_to_all
    lazy_connections::Bool = true
end
=#