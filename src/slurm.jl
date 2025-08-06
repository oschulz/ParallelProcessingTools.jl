# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

"""
    OnSlurm(;
        slurm_flags::Cmd = {defaults}
        julia_flags::Cmd = {defaults}
        dir = pwd()
        env::Dict{String,String} = Dict{String,String}()
        redirect_output::Bool = true
    )

Mode to add worker processes via SLURM `srun`.

`srun` and Julia worker `julia` command line flags are inferred from SLURM
environment variables (e.g. when inside of an `salloc` or batch job), as
well as `slurm_flags` and `julia_flags`.

Workers are started with current directory set to `dir`.

Example:

```julia
runmode = OnSlurm(slurm_flags = `--ntasks=4 --cpus-per-task=8 --mem-per-cpu=8G`)
task = runworkers(runmode)

Threads.@async begin
    wait(task)
    @info "SLURM workers have terminated."
end

@wait_while nprocs()-1 < n
```

Workers can also be started manually, use
[`worker_start_command(runmode)`](@ref) to get the `srun` start command and
run it from a separate process or so.
"""
@with_kw struct OnSlurm <: DynamicAddProcsMode
    slurm_flags::Cmd = _default_slurm_flags()
    julia_flags::Cmd = _default_julia_flags()
    dir = pwd()
    env::Dict{String,String} = Dict{String,String}()
    redirect_output::Bool = true
end
export OnSlurm

@deprecate SlurmRun OnSlurm

const _g_slurm_nextjlstep = Base.Threads.Atomic{Int}(1)

function worker_start_command(runmode::OnSlurm, manager::ElasticManager)
    slurm_flags = runmode.slurm_flags
    julia_flags = runmode.julia_flags
    dir = runmode.dir

    tc = _get_slurm_taskconf(slurm_flags, ENV)

    n_workers = _slurm_nworkers(tc)
    mem_per_task = _slurm_mem_per_task(tc)

    heap_size_hint_fraction = 0.5
    heap_size_hint_in_MB = isnothing(mem_per_task) ? nothing : ceil(Int, mem_per_task * heap_size_hint_fraction / 1024^2)
    jl_heap_size_hint_flag = isnothing(heap_size_hint_in_MB) ? `` : `--heap-size-hint=$(heap_size_hint_in_MB)M`

    jl_threads_flag = isnothing(tc.cpus_per_task) ? `` : `--threads=$(tc.cpus_per_task)`

    additional_julia_flags = `$jl_threads_flag $jl_heap_size_hint_flag $julia_flags`
    jlstep = atomic_add!(_g_slurm_nextjlstep, 1)
    jobname = "julia-$(getpid())-$jlstep"

    worker_cmd = worker_local_startcmd(
        manager;
        julia_flags = `$julia_flags $additional_julia_flags`,
        redirect_output = runmode.redirect_output, env = runmode.env
    )

    return `srun --job-name=$jobname --chdir=$dir $slurm_flags $worker_cmd`, 1, n_workers
end

function _slurm_nworkers(tc::NamedTuple)
    if !isnothing(tc.n_tasks)
        tc.n_tasks
    elseif !isnothing(tc.n_nodes) && !isnothing(tc.ntasks_per_node)
        tc.n_nodes * tc.ntasks_per_node
    else
        throw(ArgumentError("Could not infer number of tasks/processes from SLURM environment and flags."))
    end
end

function _slurm_mem_per_task(tc::NamedTuple)
    if !isnothing(tc.cpus_per_task) && !isnothing(tc.mem_per_cpu)
        tc.cpus_per_task * tc.mem_per_cpu
    elseif !isnothing(tc.n_nodes) && !isnothing(tc.mem_per_node) && !isnothing(tc.ntasks_per_node)
        div(tc.mem_per_node, tc.ntasks_per_node)
    elseif !isnothing(tc.n_nodes) && !isnothing(tc.mem_per_node) && !isnothing(tc.n_tasks)
        div(tc.n_nodes * tc.mem_per_node, tc.n_tasks)
    else
        nothing
    end
end


function runworkers(runmode::OnSlurm, manager::ElasticManager)
    srun_cmd, m, n = worker_start_command(runmode, manager)
    @info "Starting SLURM job: $srun_cmd"
    task = Threads.@async begin
        process = open(srun_cmd)
        wait(process)
        @info "SLURM job terminated: $srun_cmd"
    end
    return task, n
end


function _default_slurm_flags()
    # `srun` in `salloc`/`sbatch` doesn't seem to always pick up
    # SLURM_CPUS_PER_TASK, resulting in incorrect thread pinning. So we'll
    # set `--cpus-per-task` explicitly:
    haskey(ENV, "SLURM_CPUS_PER_TASK") ? `--cpus-per-task=$(ENV["SLURM_CPUS_PER_TASK"])` : ``
end


const _slurm_memunits = IdDict{Char,Int}('K' => 1024^1, 'M' => 1024^2, 'G' => 1024^3, 'T' => 1024^4)

const _slurm_memsize_regex = r"^([0-9]+)(([KMGT])B?)?$"
function _slurm_parse_memoptval(memsize::AbstractString)
    s = strip(memsize)
    m = match(_slurm_memsize_regex, s)
    if isnothing(m)
        throw(ArgumentError("Invalid SLURM memory size specification \"$s\""))
    else
        value = parse(Int, m.captures[1])
        unitchar = only(something(m.captures[3], 'M'))
        unitmult = _slurm_memunits[unitchar]
        return value * unitmult
    end
end
_slurm_parse_memoptval(::Nothing) = nothing

_slurm_parse_intoptval(value::AbstractString) = parse(Int, value)
_slurm_parse_intoptval(::Nothing) = nothing

function _slurm_parse_shortopt(opt::Char, args::Vector{String}, i::Int, default)
    if i <= lastindex(args)
        arg = args[i]
        if arg == "-$opt"
            if i < lastindex(args) && !startswith(args[i+1], "-")
                return args[i+1], i+2
            else
                throw(ArgumentError("Missing value for option \"-$opt\""))
            end
        elseif startswith(arg, "-$opt")
            if length(arg) > 2
                return arg[begin+2:end], i+1
            else
                throw(ArgumentError("Missing value for option \"-$opt\""))
            end
        else
            return default, i
        end
    else
        return default, i
    end
end

function _slurm_parse_longopt(opt::String, args::Vector{String}, i::Int, default)
    if i <= lastindex(args)
        arg = args[i]
        if arg == "--$opt"
            if i < lastindex(args) && !startswith(args[i+1], "-")
                return args[i+1], i+2
            else
                throw(ArgumentError("Missing value for option \"--$opt\""))
            end
        elseif startswith(arg, "--$opt=")
            if length(arg) > length(opt) + 3
                return arg[begin+length(opt)+3:end], i+1
            else
                throw(ArgumentError("Missing value for option \"--$opt\""))
            end
        else
            return default, i
        end
    else
        return default, i
    end
end

function _get_slurm_taskconf(slurmflags::Cmd, env::AbstractDict{String,String})
    n_tasks = get(env, "SLURM_NTASKS", nothing)
    cpus_per_task = get(env, "SLURM_CPUS_PER_TASK", nothing)
    mem_per_cpu = get(env, "SLURM_MEM_PER_CPU", nothing)
    n_nodes = get(env, "SLURM_JOB_NUM_NODES", nothing)
    ntasks_per_node = get(env, "SLURM_NTASKS_PER_NODE", nothing)
    mem_per_node = get(env, "SLURM_MEM_PER_NODE", nothing)

    args = collect(slurmflags)
    i::Int = firstindex(args)
    while i <= lastindex(args)
        last_i = i
        n_tasks, i = _slurm_parse_shortopt('n', args, i, n_tasks)
        n_tasks, i = _slurm_parse_longopt("ntasks", args, i, n_tasks)
        cpus_per_task, i = _slurm_parse_shortopt('c', args, i, cpus_per_task)
        cpus_per_task, i = _slurm_parse_longopt("cpus-per-task", args, i, cpus_per_task)
        mem_per_cpu, i = _slurm_parse_longopt("mem-per-cpu", args, i, mem_per_cpu)
        n_nodes, i = _slurm_parse_shortopt('N', args, i, n_nodes)
        n_nodes, i = _slurm_parse_longopt("nodes", args, i, n_nodes)
        mem_per_node, i = _slurm_parse_longopt("mem", args, i, mem_per_node)
        ntasks_per_node, i = _slurm_parse_longopt("ntasks-per-node", args, i, ntasks_per_node)
        
        if last_i == i
            i += 1
        end
    end

    return (
        n_tasks = _slurm_parse_intoptval(n_tasks),
        cpus_per_task = _slurm_parse_intoptval(cpus_per_task),
        mem_per_cpu = _slurm_parse_memoptval(mem_per_cpu),
        n_nodes = _slurm_parse_intoptval(n_nodes),
        ntasks_per_node = _slurm_parse_intoptval(ntasks_per_node),
        mem_per_node = _slurm_parse_memoptval(mem_per_node),
    )
end
