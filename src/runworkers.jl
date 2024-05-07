# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


"""
    pinthreads_auto()

Use default thread-pinning strategy for the current Julia process.
"""
function pinthreads_auto()
    if Distributed.myid() == 1
        let n_juliathreads = nthreads()
            if n_juliathreads > 1
                LinearAlgebra.BLAS.set_num_threads(n_juliathreads)
            end
        end
    else
        @static if isdefined(ThreadPinning, :affinitymask2cpuids)
            # Not available on all platforms:
            let available_cpus = ThreadPinning.affinitymask2cpuids(ThreadPinning.get_affinity_mask())
                ThreadPinning.pinthreads(:affinitymask)
                LinearAlgebra.BLAS.set_num_threads(length(available_cpus))
            end
        end
    end
end
export pinthreads_auto


"""
    worker_resources

Get the distributed Julia process resources currently available.
"""
function worker_resources()
    pids = Distributed.workers()
    load_ft = Distributed.remotecall.(Core.eval, pids, Ref(Main), Ref(:(import ParallelProcessingTools)))
    fetch.(load_ft)
    resources_ft = Distributed.remotecall.(ParallelProcessingTools._current_process_resources, pids)
    resources = fetch.(resources_ft)
    sorted_resources = sort(resources, by = x -> x.workerid)
    sorted_resources
end
export worker_resources

function _current_process_resources()
    return (
        workerid = Distributed.myid(),
        hostname = Base.gethostname(),
        nthreads = nthreads(),
        blas_nthreads = LinearAlgebra.BLAS.get_num_threads(),
        cpuids = _getcpuids()
    )
end

@static if isdefined(ThreadPinning, :getcpuids)
    # Not available on all platforms:
    _getcpuids() = ThreadPinning.getcpuids()
else
    _getcpuids() = missing
end


"""
    abstract type ParallelProcessingTools.RunProcsMode

Abstract supertype for worker process run modes.

Subtypes must implement:

* `ParallelProcessingTools.runworkers(runmode::SomeRunProcsMode, manager::Distributed.AbstractClusterManager)`
"""
abstract type RunProcsMode end


"""
    runworkers(
        runmode::ParallelProcessingTools.RunProcsMode
        manager::Distributed.AbstractClusterManager = ppt_cluster_manager()
    )

Run Julia worker processes.

By default ensures that all workers processes use the same Julia project
environment as the current process (requires that file systems paths are
consistenst across compute hosts).

The new workers are managed via [`ppt_cluster_manager()`](@ref) and
automatically added to the [`ppt_worker_pool()`](@ref)

Returns a tuple `(task, n)`. Here, `task::Task` is done when all workers
have terminated. `n` is either an `Integer`, if the number of workers that
will be started is known, or `Nothing`, if the number of workers can't be
predicted (accurately).

Example:

```julia
task, n = runworkers(OnLocalhost(nprocs = 4))
```

See also [`worker_resources()`](@ref).
"""
function runworkers end
export runworkers

runworkers(runmode::RunProcsMode) = runworkers(runmode, ppt_cluster_manager())


"""
    ParallelProcessingTools.ppt_cluster_manager()
    ParallelProcessingTools.ppt_cluster_manager(manager::ClusterManager)

Get the default ParallelProcessingTools cluster manager.
"""
function ppt_cluster_manager end
export ppt_cluster_manager

const _g_cluster_manager = Ref{Union{Nothing,ClusterManager}}(nothing)

function ppt_cluster_manager()
    if isnothing(_g_cluster_manager[])
        _g_cluster_manager[] = ClusterManagers.ElasticManager(
            addr=:auto, port=0, topology=:master_worker, manage_callback = _get_elasticmgr_add_to_pool_callback()
        )
    end
    return _g_cluster_manager[]
end

"""
    ParallelProcessingTools.ppt_cluster_manager!(manager::ClusterManagers.ElasticManager)

Set the default ParallelProcessingTools cluster manager.
"""
function ppt_cluster_manager!(manager::ClusterManagers.ElasticManager)
    _g_cluster_manager[] = manager
    return _g_cluster_manager[]
end
export ppt_cluster_manager!

function _get_elasticmgr_add_to_pool_callback(get_workerpool::Function = ppt_worker_pool)
    function mgr_add_too_pool(::ClusterManagers.ElasticManager, pid::Integer, op::Symbol)
        pool = get_workerpool()::AbstractWorkerPool
        if op == :register
            Threads.@async begin
                @debug "Adding process $pid to worker pool $(getlabel(pool))."
                push!(pool, pid)
                @debug "Added process $pid to worker pool $(getlabel(pool))."
            end
        elseif  op == :deregister
            @debug "Process $pid is being deregistered."
        else
            @error "Unknown ElasticManager manage op: $op."
        end
    end
    return mgr_add_too_pool
end


"""
    abstract type ParallelProcessingTools.DynamicAddProcsMode <: ParallelProcessingTools.RunProcsMode

Abstract supertype for worker start modes that use an elastic cluster manager
that enables dynamic addition and removal of worker processes.

Subtypes must implement:

* `ParallelProcessingTools.worker_start_command(runmode::SomeDynamicAddProcsMode, manager::ClusterManager)`
* `ParallelProcessingTools.runworkers(runmode::SomeDynamicAddProcsMode, manager::ClusterManager)`
"""
abstract type DynamicAddProcsMode <: RunProcsMode end


"""
    worker_start_command(
        runmode::DynamicAddProcsMode,
        manager::ClusterManager = ParallelProcessingTools.ppt_cluster_manager()
    )::Tuple{Cmd,Integer,Integer}

Return a tuple `(cmd, m, n)`, with system command `cmd` that needs to be
run `m` times (in parallel) to start `n` workers.
"""
function worker_start_command end
export worker_start_command

worker_start_command(runmode::DynamicAddProcsMode) = worker_start_command(runmode, ppt_cluster_manager())


"""
    write_worker_start_script(
        filename::AbstractString,
        runmode::DynamicAddProcsMode,
        manager::ClusterManager = ParallelProcessingTools.ppt_cluster_manager()
    )

Writes the system command to start worker processes to a shell script.
"""
function write_worker_start_script(
    filename::AbstractString,
    runmode::DynamicAddProcsMode,
    manager::ClusterManager = ParallelProcessingTools.ppt_cluster_manager()
)
    wstartcmd, m, _ = worker_start_command(runmode, manager)
    @assert m isa Integer && (m >= 0)
    _, ext = split_basename_ext(basename(filename))
    if Sys.iswindows()
        if ext == ".bat" || ext == ".BAT"
            error("Worker start script generation isn't supported on Windows OS yet.")
            # write(filename, Base.shell_escape_wincmd(wstartcmd))
        else
            throw(ArgumentError("Script filename extension \"$ext\" not supported on Windows.")) 
        end
    else
        if ext == ".sh"
            open(filename, "w") do io
                chmod(filename, 0o700)
                println(io, "#!/bin/sh")
                if m > 0
                    if m > 1
                        print(io, "printf \"%s\\n\" {1..$m} | xargs -n1 -P$m -I{} ")
                    end
                    println(io, Base.shell_escape_posixly(wstartcmd))
                end
            end
        else
            throw(ArgumentError("Script filename extension \"$ext\" not supported on Posix-like OS.")) 
        end
    end
    return nothing
end
export write_worker_start_script


function _elastic_worker_startjl(manager::ClusterManagers.ElasticManager, redirect_output::Bool, worker_timeout::Real)
    cookie = Distributed.cluster_cookie()
    socket_name = manager.sockname
    address = string(socket_name[1])
    port = convert(Int, socket_name[2])
    """import ClusterManagers; ClusterManagers.elastic_worker("$cookie", "$address", $port, stdout_to_master=$redirect_output, worker_timeout=$worker_timeout)"""
end

const _default_addprocs_params = Distributed.default_addprocs_params()

_default_julia_cmd() = `$(_default_addprocs_params[:exename]) $(_default_addprocs_params[:exeflags])`
_default_julia_flags() = ``
_default_julia_project() = Pkg.project().path

_default_worker_timeout() = parse(Int, strip(get(ENV, "JULIA_WORKER_TIMEOUT", "60")))


"""
    ParallelProcessingTools.worker_local_startcmd(
        manager::Distributed.ClusterManager;
        julia_cmd::Cmd = _default_julia_cmd(),
        julia_flags::Cmd = _default_julia_flags(),
        julia_project::AbstractString = _default_julia_project()
        redirect_output::Bool = true, worker_timeout::Real = ...,
    )::Cmd

Return the system command required to start a Julia worker process locally
on some host, so that it will connect to `manager`.
"""
function worker_local_startcmd(
    manager::Distributed.ClusterManager;
    julia_cmd::Cmd = _default_julia_cmd(),
    julia_flags::Cmd = _default_julia_flags(),
    julia_project::AbstractString = _default_julia_project(),
    redirect_output::Bool = true, worker_timeout::Real = _default_worker_timeout()
)
    julia_code = _elastic_worker_startjl(manager, redirect_output, worker_timeout)

    `$julia_cmd --project=$julia_project $julia_flags -e $julia_code`
end


"""
    OnLocalhost(;
        n::Integer = 1
        worker_timeout::Float64 = ...
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
    worker_timeout::Float64 = _default_worker_timeout()
end
export OnLocalhost

function worker_start_command(runmode::OnLocalhost, manager::ClusterManagers.ElasticManager)
    worker_nthreads = nthreads()
    julia_flags = `$(_default_julia_flags()) --threads=$worker_nthreads`
    worker_cmd = worker_local_startcmd(
        manager;
        julia_flags = julia_flags,
        worker_timeout = runmode.worker_timeout
    )
    return worker_cmd, runmode.n, runmode.n
end

function runworkers(runmode::OnLocalhost, manager::ClusterManagers.ElasticManager)
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


"""
    stopworkers()
    stopworkers(pid::Int)
    stopworkers(pids::AbstractVector{Int})

Stops all or the specified worker processes. The current process is ignored.
"""
function stopworkers end
export stopworkers

stopworkers() = stopworkers(workers())

function stopworkers(pid::Int)
    pid!=myid() && rmprocs(pid)
    return nothing
end

function stopworkers(pids::AbstractVector{Int})
    rmprocs(filter(!isequal(myid()), pids))
    return nothing
end
