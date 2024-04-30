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
    ParallelProcessingTools.pinthreads_distributed(procs::AbstractVector{<:Integer} = Distrib)

Use default thread-pinning strategy on all Julia processes processes `procs`.
"""
function pinthreads_distributed(@nospecialize(procs::AbstractVector{<:Integer}))
    if 1 in procs
        pinthreads_auto()
    end

    workerprocs = filter(!isequal(1), procs)
    if !isempty(workerprocs)
        Distributed.remotecall_eval(Main, workerprocs,
            quote
                import ParallelProcessingTools
                ParallelProcessingTools.pinthreads_auto()
            end
        )
    end
end


"""
    ParallelProcessingTools.shutdown_workers_atexit()

Ensure worker processes are shut down when Julia exits.
"""
function shutdown_workers_atexit()
    atexit(() -> Distributed.rmprocs(filter!(!isequal(1), Distributed.workers()), waitfor = 1))
end


"""
    worker_resources

Get the distributed Julia process resources currently available.
"""
function worker_resources()
    resources_ft = Distributed.remotecall.(ParallelProcessingTools._current_process_resources, Distributed.workers())
    resources = fetch.(resources_ft)
    sorted_resources = sort(resources, by = x -> x.workerid)
    sorted_resources
end
export worker_resources


@static if isdefined(ThreadPinning, :getcpuids)
    # Not available on all platforms:
    _getcpuids() = ThreadPinning.getcpuids()
else
    _getcpuids() = missing
end


function _current_process_resources()
    return (
        workerid = Distributed.myid(),
        hostname = Base.gethostname(),
        nthreads = nthreads(),
        blas_nthreads = LinearAlgebra.BLAS.get_num_threads(),
        cpuids = ThreadPinning.getcpuids()
    )
end


"""
    abstract type ParallelProcessingTools.AddProcsMode

Abstract supertype for worker process addition modes.

Subtypes must implement:

* `ParallelProcessingTools.addworkers(mode::SomeAddProcsMode)`
"""
abstract type AddProcsMode end



"""
    addworkers(mode::ParallelProcessingTools.AddProcsMode)

    addworkers(
        mode::ParallelProcessingTools.AddProcsMode,
        pool::Union{AbstractWorkerPool,Nothing}
    )

Add Julia worker processes for LEGEND data processing.

By default ensures that all workers processes use the same Julia project
environment as the current process (requires that file systems paths are
consistenst across compute hosts).

Use [`@always_everywhere`](@ref) to run initialization code on all current
processes and all future processes added via `addworkers`:

```julia
using Distributed, ParallelProcessingTools

@always_everywhere begin
    using SomePackage
    import SomeOtherPackage

    get_global_value() = 42
end

# ... some code ...

addworkers(LocalProcesses(nprocs = 4))

# `get_global_value` is available even though workers were added later:
remotecall_fetch(get_global_value, last(workers()))
```

See also [`worker_resources()`](@ref).
"""
function addworkers end
export addworkers

function addworkers(mode::ParallelProcessingTools.AddProcsMode)
    addworkers(mode, default_flex_worker_pool())
end


"""
    LocalProcesses(;
        nprocs::Integer = 1
    )

Mode to add `nprocs` worker processes on the current host.
"""
@with_kw struct LocalProcesses <: AddProcsMode
    nprocs::Int
end
export LocalProcesses


function addworkers(
    mode::LocalProcesses,
    @nospecialize(pool::Union{AbstractWorkerPool,Nothing})
)
    n_workers = mode.nprocs
    try
        lock(allprocs_management_lock())

        @info "Adding $n_workers Julia processes on current host"

        # Maybe wait for shared/distributed file system to get in sync?
        # sleep(5)

        julia_project = dirname(Pkg.project().path)
        worker_nthreads = nthreads()

        new_workers = Distributed.addprocs(
            n_workers,
            exeflags = `--project=$julia_project --threads=$worker_nthreads`
        )

        _init_new_workers(new_workers, pool)

        @info "Added $(length(new_workers)) Julia worker processes on current host"
    finally
        unlock(allprocs_management_lock())
    end
end


function _init_new_workers(
    new_workers::AbstractVector{<:Integer},
    @nospecialize(pool::Union{AbstractWorkerPool,Nothing})
)
    @info "Sending initialization code to $(length(new_workers)) new worker processes"
    r = ensure_procinit(new_workers)
    wait_for_all(values(r))

    if !isnothing(pool)
        @info "Adding $(length(new_workers)) to worker pool $(getlabel(pool))"
        foreach(Base.Fix1(push!, pool), new_workers)
    end
end


#=
# ToDo: Add SSHWorkers or similar:

@with_kw struct SSHWorkers <: AddProcsMode
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
    ParallelProcessingTools.default_elastic_manager()
    ParallelProcessingTools.default_elastic_manager(manager::ClusterManager)

Get or set the default elastic cluster manager.
"""
function default_elastic_manager end

const _g_elastic_manager = Ref{Union{Nothing,ClusterManager}}(nothing)

function default_elastic_manager()
    if isnothing(_g_elastic_manager[])
        _g_elastic_manager[] = ClusterManagers.ElasticManager(addr=:auto, port=0, topology=:master_worker)
    end
    return _g_elastic_manager[]
end
    
function default_elastic_manager(manager::ClusterManager)
    _g_elastic_manager[] = manager
    return _g_elastic_manager[]
end



"""
    abstract type ParallelProcessingTools.ElasticAddProcsMode <: ParallelProcessingTools.AddProcsMode

Abstract supertype for worker process addition modes that use the
elastic cluster manager.

Subtypes must implement:

* `ParallelProcessingTools.worker_start_command(mode::SomeElasticAddProcsMode, manager::ClusterManager)`
* `ParallelProcessingTools.start_elastic_workers(mode::SomeElasticAddProcsMode, manager::ClusterManager)`

and may want to specialize:

* `ParallelProcessingTools.elastic_addprocs_timeout(mode::SomeElasticAddProcsMode)`
"""
abstract type ElasticAddProcsMode <: AddProcsMode end

"""
    ParallelProcessingTools.worker_start_command(
        mode::ElasticAddProcsMode,
        manager::ClusterManager = ParallelProcessingTools.default_elastic_manager()
    )::Tuple{Cmd,Integer}

Return the system command to start worker processes as well as the number of
workers to start.
"""
function worker_start_command end
worker_start_command(mode::ElasticAddProcsMode) = worker_start_command(mode, default_elastic_manager())


function _elastic_worker_startjl(manager::ClusterManagers.ElasticManager)
    cookie = Distributed.cluster_cookie()
    socket_name = manager.sockname
    address = string(socket_name[1])
    port = convert(Int, socket_name[2])
    """import ClusterManagers; ClusterManagers.elastic_worker("$cookie", "$address", $port)"""
end

const _default_addprocs_params = Distributed.default_addprocs_params()

_default_julia_cmd() = `$(_default_addprocs_params[:exename]) $(_default_addprocs_params[:exeflags])`
_default_julia_flags() = ``
_default_julia_project() = Pkg.project().path


"""
    ParallelProcessingTools.elastic_localworker_startcmd(
        manager::Distributed.ClusterManager;
        julia_cmd::Cmd = _default_julia_cmd(),
        julia_flags::Cmd = _default_julia_flags(),
        julia_project::AbstractString = _default_julia_project()
    )::Cmd

Return the system command required to start a Julia worker process, that will
connect to `manager`, on the current host.
"""
function elastic_localworker_startcmd(
    manager::Distributed.ClusterManager;
    julia_cmd::Cmd = _default_julia_cmd(),
    julia_flags::Cmd = _default_julia_flags(),
    julia_project::AbstractString = _default_julia_project()
)
    julia_code = _elastic_worker_startjl(manager)

    `$julia_cmd --project=$julia_project $julia_flags -e $julia_code`
end



"""
    ParallelProcessingTools.elastic_addprocs_timeout(mode::ElasticAddProcsMode)

Get the timeout in seconds for waiting for worker processes to connect.
"""
function elastic_addprocs_timeout end

elastic_addprocs_timeout(mode::ElasticAddProcsMode) = 60


"""
    ParallelProcessingTools.start_elastic_workers(mode::ElasticAddProcsMode, manager::ClusterManagers.ElasticManager)::Int

Spawn worker processes as specified by `mode` and return a tuple `n, state`.

`n` is the number of expected additional workers.

`state` is be some object that can be monitored, or `missing`. `state` may be
a `Task`, `Process` or any other object that supports
`ParallelProcessingTools.isactive(state)` and
`ParallelProcessingTools.throw_if_failed(state)`
"""
function start_elastic_workers end


function addworkers(
    mode::ElasticAddProcsMode,
    @nospecialize(pool::Union{AbstractWorkerPool,Nothing})
)
    try
        lock(allprocs_management_lock())

        manager = default_elastic_manager()

        old_procs = Distributed.procs()
        n_previous = length(old_procs)
        n_to_add, start_state = start_elastic_workers(mode, manager)

        @info "Waiting for $n_to_add workers to connect..."
    
        sleep(1)

        # ToDo: Add timeout and either prevent workers from connecting after
        # or somehow make sure that init and @always everywhere code is still
        # run on them before user code is executed on them.

        timeout = elastic_addprocs_timeout(mode)

        t_start = time()
        t_waited = zero(t_start)
        n_added_last = 0
        while true
            if !isactive(start_state)
                label = getlabel(start_state)
                if hasfailed(start_state)
                    err = whyfailed(start_state)
                    error("Aborting addworkers, $label failed due to $err")
                else
                    error("Aborting addworkers, $label doesn't seem to have failed but seems to have terminated")
                end
                break
            end

            t_waited = time() - t_start
            if t_waited > timeout
                @error "Timeout after waiting for workers to connect for $t_waited seconds"
                break
            end
            n_added = Distributed.nprocs() - n_previous
            if n_added > n_added_last
                @info "$n_added of $n_to_add additional workers have connected"
            end
            if n_added == n_to_add
                break
            elseif n_added > n_to_add
                @warn "More workers connected than expected: $n_added > $n_to_add"
                break
            end

            n_added_last = n_added
            sleep(1)
        end

        new_workers = setdiff(Distributed.workers(), old_procs)
        n_new = length(new_workers)

        _init_new_workers(new_workers, pool)

        @info "Added $n_new new Julia worker processes"

        if n_new != n_to_add
            throw(ErrorException("Tried to add $n_to_add new workers, but added $n_new"))
        end
    finally
        unlock(allprocs_management_lock())
    end
end


"""
    ParallelProcessingTools.ExternalProcesses(;
        nprocs::Integer = ...
    )

Add worker processes by starting them externally.

Will log (via `@info`) a worker start command and then wait for the workers to
connect. The user is responsible for starting the specified number of workers
externally using that start command.

Example:

```julia
mode = ExternalProcesses(nprocs = 4)
addworkers(mode)
```

The user now has to start 4 Julia worker processes externally using the logged
start command. This start command can also be retrieved via
[`worker_start_command(mode)`](@ref).
"""
@with_kw struct ExternalProcesses <: ElasticAddProcsMode
    nprocs::Int = 1
end
export ExternalProcesses


function worker_start_command(mode::ExternalProcesses, manager::ClusterManagers.ElasticManager)
    worker_nthreads = nthreads()
    julia_flags = `$(_default_julia_flags()) --threads=$worker_nthreads`
    elastic_localworker_startcmd(manager, julia_flags = julia_flags), mode.nprocs
end

function start_elastic_workers(mode::ExternalProcesses, manager::ClusterManagers.ElasticManager)
    start_cmd, n_workers = worker_start_command(mode, manager)
    @info "To add Julia worker processes, run ($n_workers times in parallel, I'll wait for them): $start_cmd"
    return n_workers, missing
end


"""
    always_addworkers(mode::ParallelProcessingTools.AddProcsMode, min_nworkers::Integer)

Continously check if the number of worker processes is less than
`min_nworkers`, and if so, add more worker processes using `mode`.
"""
function always_addworkers end
export always_addworkers

const _g_always_addworkers_taskch = Ref(Channel{Nothing}())
atexit(() -> close(_g_always_addworkers_taskch[]))

function always_addworkers(mode::AddProcsMode, min_nworkers::Integer)
    close(_g_always_addworkers_taskch[])
    _g_always_addworkers_taskch[] = Channel{Nothing}(spawn=true) do ch
        while isopen(ch)
            current_workers = Distributed.workers()
            main_process = Distributed.myid()
            if length(current_workers) < min_nworkers || length(current_workers) == 1 && only(current_workers) == main_process
                addworkers(mode)
            end
            sleep(10)
        end
    end
    return nothing
end
