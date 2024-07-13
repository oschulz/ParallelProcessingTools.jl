# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    HTCondorRun(;
        n::Int = 1
        condor_flags::Cmd = _default_condor_flags()
        condor_settings::Dict{String,String} = Dict{String,String}()
        julia_flags::Cmd = _default_julia_flags()
        julia_depot::Vector{String} = DEPOT_PATH
        jobfile_dir = homedir()
        env::Dict{String,String} = Dict{String,String}()
        redirect_output::Bool = true
    )

Mode to add worker processes via HTCondor `condor_submit`.

Condor submit script and steering `.sh` files are stored in `jobfile_dir`.

Example:

```julia-repl
julia> runmode = HTCondorRun(n = 10; condor_settings=Dict("universe" => "vanilla", "+queue" => "short", "request_memory" => "4GB"))
task = runworkers(runmode)

julia> runworkers(runmode)
[ Info: Submitting HTCondor job: `condor_submit /home/jiling/jl_rAHyFadwHa.sub`
Submitting job(s)..........
10 job(s) submitted to cluster 3198291.
[ Info: HTCondor job submitted: `condor_submit /home/jiling/jl_rAHyFadwHa.sub`
(nothing, 10)

julia> sleep(10)

julia> nworkers()
10
```

Workers can also be started manually, use
[`worker_start_command(runmode)`](@ref) to get the `condor_submit` start command and
run it from a separate process or so.
"""
@with_kw struct HTCondorRun <: DynamicAddProcsMode
    n::Int = 1
    condor_flags::Cmd = _default_condor_flags()
    condor_settings::Dict{String,String} = Dict{String,String}()
    julia_flags::Cmd = _default_julia_flags()
    julia_depot::Vector{String} = DEPOT_PATH
    jobfile_dir = homedir()
    env::Dict{String,String} = Dict{String,String}()
    redirect_output::Bool = true
end
export HTCondorRun

_default_condor_flags() = ``
const _g_condor_nextjlstep = Base.Threads.Atomic{Int}(1)

function worker_start_command(runmode::HTCondorRun, manager::ElasticManager)
    flags = runmode.condor_flags
    n_workers = runmode.n
    temp_name = tempname(runmode.jobfile_dir)
    worker_script_path = temp_name*".sh"
    submit_file_path = temp_name*".sub"
    _generate_condor_worker_script(worker_script_path, runmode, manager)
    _generate_condor_submit_file(submit_file_path, worker_script_path, runmode)

    return `condor_submit $flags $submit_file_path`, 1, n_workers
end

function _generate_condor_worker_script(filename, runmode::HTCondorRun, manager::ElasticManager)
    julia_flags = runmode.julia_flags

    request_memory = get(runmode.condor_settings, "request_memory", "2GB")
    mem_per_task = _slurm_parse_memoptval(request_memory)

    heap_size_hint_fraction = 0.5
    heap_size_hint_in_MB = isnothing(mem_per_task) ? nothing : ceil(Int, mem_per_task * heap_size_hint_fraction / 1024^2)
    jl_heap_size_hint_flag = isnothing(heap_size_hint_in_MB) ? `` : `--heap-size-hint=$(heap_size_hint_in_MB)M`

    jl_threads_flag = `--threads=$(1)`

    additional_julia_flags = `$jl_threads_flag $jl_heap_size_hint_flag $julia_flags`
    worker_cmd = worker_local_startcmd(
        manager;
        julia_flags = `$julia_flags $additional_julia_flags`,
        redirect_output = runmode.redirect_output, env = runmode.env
    )
    depot_path = join(runmode.julia_depot, ":")
    open(filename, "w") do io
        write(io, 
        """
        export JULIA_DEPOT_PATH='$depot_path'
        $worker_cmd
        """)
    end
end

function _generate_condor_submit_file(submit_file_path, worker_script_path, runmode::HTCondorRun)
    jlstep = atomic_add!(_g_condor_nextjlstep, 1)
    jobname = "julia-$(getpid())-$jlstep"
    default_dict = Dict(
        "batch_name" => jobname,
    )
    condor_settings = merge(default_dict, runmode.condor_settings)

    condor_option_strings = join(["$key=$value" for (key, value) in condor_settings], "\n")
    open(submit_file_path, "w") do io
        write(io,
    """
    executable = /bin/bash
    arguments = $(basename(worker_script_path))
    should_transfer_files = yes
    transfer_input_files = $worker_script_path
    Notification = Error
    $condor_option_strings
    queue $(runmode.n)
    """)
    end
end

function runworkers(runmode::HTCondorRun, manager::ElasticManager)
    run_cmd, m, n = worker_start_command(runmode, manager)
    @info "Submitting HTCondor job: $run_cmd"
    process = run(run_cmd)
    @info "HTCondor job submitted: $run_cmd"
    return nothing, n
end
