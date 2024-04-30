# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


"""
    isvalid_pid(pid::Int)::Bool

Tests if `pid` is a valid Julia process ID.

Equivalent to `pid in Distributed.procs()`, but faster.
"""
function isvalid_pid end
export isvalid_pid

# Distributed.id_in_procs is not public API, so we need a fallback when using it:
@static if isdefined(Distributed, :id_in_procs)
    isvalid_pid(pid::Int) = Distributed.id_in_procs(pid)
else
    isvalid_pid(pid::Int) = pid in Distributed.procs()
end


"""
    ParallelProcessingTools.allprocs_management_lock()::ReentrantLock

Returns the global process operations lock. This lock is used to protect
operations that concern the management of all processes.
"""
@inline allprocs_management_lock() = _g_allprocsmgmt_lock

const _g_allprocsmgmt_lock = ReentrantLock()


"""
    ParallelProcessingTools.proc_management_lock(pid::Integer)::ReentrantLock

Returns a process-specific lock. This lock is used to protect operations that
concern the management process `pid`.
"""
function proc_management_lock(pid::Integer)
    try
        lock(allprocs_management_lock())
        # Ensure _g_procmgmt_procinfo has an entry for pid:
        get!(_g_procmgmt_initlvl, pid, 0)
        return get!(_g_procmgmt_locks, pid, ReentrantLock())
    finally
        unlock(allprocs_management_lock())
    end
end

const _g_procmgmt_locks = IdDict{Integer, ReentrantLock}()
const _g_procmgmt_initlvl = IdDict{Integer,Integer}()


"""
    ParallelProcessingTools.current_procinit_level()

Return the init level of the current process.

See also [`global_procinit_level`](@ref).
"""
function current_procinit_level()
    try
        lock(allprocs_management_lock())
        return _current_procinit_level[]::Int
    finally
        unlock(allprocs_management_lock())
    end
end

const _current_procinit_level = Ref(0)


"""
    ParallelProcessingTools.global_procinit_level()

Return the global process init level.

Returns, e.g., the number of times [`add_procinit_code`](@ref) resp.
[`@almost_everywhere`](@ref) have been called.

See also [`current_procinit_level`](@ref).
"""
function global_procinit_level()
    try
        lock(allprocs_management_lock())
        return _global_procinit_level[]::Int
    finally
        unlock(allprocs_management_lock())
    end
end

const _global_procinit_level = Ref(1)


"""
    ParallelProcessingTools.get_procinit_code()

Returns the code that should be run on each process to ensure that desired
packages are loaded and global variable are set up as expected.

See also [`ParallelProcessingTools.add_procinit_code`](@ref) and
[`ParallelProcessingTools.ensure_procinit`](@ref).
"""
function get_procinit_code()
    try
        lock(allprocs_management_lock())
        return _g_procinit_code
    finally
        unlock(allprocs_management_lock())
    end
end


const _g_initial_procinit_code = quote
    if !isdefined(Main, :ParallelProcessingTools)
        import ParallelProcessingTools
    end
    ParallelProcessingTools._initial_procinit_done()
end

function _initial_procinit_done()
    try
        lock(ParallelProcessingTools.allprocs_management_lock())
        if ParallelProcessingTools._current_procinit_level[] < 1
            ParallelProcessingTools._current_procinit_level[] = 1
        end
    finally
        unlock(ParallelProcessingTools.allprocs_management_lock())
    end
end

const _g_procinit_code = Expr(:block)

const _g_wrapped_procinit_code = Expr(:block)


function _initial_init_current_process()
    # Need to explicitly run _g_initial_procinit_code explicitly on current process once:
    if _current_procinit_level[] < 1
        @debug "Running initial process initialization code on current process $(myid())"
        Core.eval(Main, _g_initial_procinit_code)
    end
end


"""
    ParallelProcessingTools.add_procinit_code(expr)

Add `expr` to process init code. `expr` is run on the current proccess
immediately, but not automatically on remote processes.

User code should typically not need to call this function, but should use
[`@always_everywhere`](@ref) instead.
    
See also [`ParallelProcessingTools.get_procinit_code`](@ref) and
[`ParallelProcessingTools.ensure_procinit`](@ref).
"""
@noinline function add_procinit_code(init_code)
    try
        lock(allprocs_management_lock())

        next_init_level = _global_procinit_level[] + 1

        _initial_init_current_process()
        Core.eval(Main, init_code)

        _store_additional_procinit_code(init_code, next_init_level)

        _global_procinit_level[] = next_init_level
        _current_procinit_level[] = next_init_level

        return nothing
    finally
        unlock(allprocs_management_lock())
    end
end


function _store_additional_procinit_code(init_code::Expr, init_level::Int)
    push!(_g_procinit_code.args, _initstep_wrapperexpr(init_code, init_level))

    wrapped_init_code = _initcode_wrapperexpr(_g_procinit_code, init_level)
    _g_wrapped_procinit_code.head = wrapped_init_code.head
    _g_wrapped_procinit_code.args = wrapped_init_code.args
end


function _initstep_wrapperexpr(init_step_code::Expr, next_init_level::Int)
    quote
        if ParallelProcessingTools._current_procinit_level[] < $next_init_level
            $init_step_code
            ParallelProcessingTools._current_procinit_level[] = $next_init_level
        end
    end
end


function _initcode_wrapperexpr(init_code::Expr, target_init_level::Int)
    quoted_init_code = Expr(:quote, init_code)

    quote
        $_g_initial_procinit_code

        ParallelProcessingTools._execute_procinit_code(
            $quoted_init_code,
            $target_init_level
        )
    end
end


function _execute_procinit_code(init_code::Expr, target_level::Int)
    current_pid = myid()
    try
        lock(allprocs_management_lock())

        if _global_procinit_level[] < target_level
            _global_procinit_level[] = target_level
        end

        current_level = current_procinit_level()

        if current_level < target_level
            #@debug "Raising process $current_pid init level from $current_level to $target_level"
            Core.eval(Main, init_code)
            if current_procinit_level() != target_level
                error("Failed to raise process $current_pid init level to $target_level, worker on level $current_level")
            end
        elseif current_level == target_level
            #@debug "Process $current_pid init level already at $current_level of $target_level"
        else
            #@debug "Process $current_pid init level $current_level already higher than requested init level $target_level"
        end

        return nothing
    catch err
        @error "Error while running init code on process $current_pid:" err
        rethrow()
    finally
        unlock(allprocs_management_lock())
    end
end



"""
    ParallelProcessingTools.ensure_procinit(pid::Integer)
    ParallelProcessingTools.ensure_procinit(pids::AbstractVector{<:Integer})

Run process initialization code on the given process or processes
necessary.

Initialization of the current process is run immediately.

Initialization of remote processes is run asynchronously. When called with a
single `pid`, returns either a `Task` or `nothing`, depending on whether
initialization was necessary. When called with several `pids`, returns an
`IdDict{Int,Task}` that contains the processes for which initialization was
necessary. The task(s) returned can be awaited to ensure that initialization
of the process(es) is complete.

If you want to ensure no initialization code is added while remote process
initialization is incomplete, you can `lock(allprocs_management_lock())` while
waiting for the initialization task(s). When using an
[`ElasticWorkerPool`](@ref), worker initialization can safely be run in the
background though, as the pool will only let you take workers that have
been fully initialized.

User code should typically not need to call `ensure_procinit` but should use
[`@always_everywhere`](@ref) instead.

See also [`ParallelProcessingTools.get_procinit_code`](@ref)
and [`ParallelProcessingTools.add_procinit_code`](@ref).

See also [`ParallelProcessingTools.get_procinit_code`](@ref),
[`ParallelProcessingTools.ensure_procinit`](@ref),
[`ParallelProcessingTools.global_procinit_level`](@ref) and
[`ParallelProcessingTools.current_procinit_level`](@ref).
"""
function ensure_procinit end

ensure_procinit(pid::Integer) = ensure_procinit(Int(pid))

@noinline function ensure_procinit(pid::Int)
    try
        lock(allprocs_management_lock())

        _initial_init_current_process()

        if pid != myid()
            init_level = global_procinit_level()
            pid_lock = proc_management_lock(pid)
            try
                lock(pid_lock)

                pid_initlvl = _g_procmgmt_initlvl[pid]
                if pid_initlvl < init_level
                    wrapped_init_code = _g_wrapped_procinit_code
                    init_task = _init_single_process(pid, pid_lock, init_level, wrapped_init_code)
                    return init_task::Task
                else
                    return nothing
                end
            finally
                unlock(pid_lock)
            end
        else
            # Current process should always be initialized already
            return nothing
        end
    finally
        unlock(allprocs_management_lock())
    end

    return task
end

@noinline function _init_single_process(pid::Int, pid_lock::ReentrantLock, init_level::Int, wrapped_init_code::Expr)
    task = Threads.@spawn begin
        try
            lock(pid_lock)

            # ToDo: Maybe use fetch with timeout?
            remotecall_fetch(Core.eval, pid, Main, wrapped_init_code)

            _g_procmgmt_initlvl[pid] = init_level
            #@debug "Initialization of process $pid to init level $init_level complete."
        catch err
            orig_err = original_exception(err)
            @error "Error while running init code on process $pid:" orig_err
            throw(err)
        finally
            unlock(pid_lock)
        end
    end
    return task
end


function ensure_procinit(@nospecialize(procs::AbstractVector{<:Integer}))
    try
        lock(allprocs_management_lock())

        init_tasks = IdDict{Int,Task}()
        for pid in procs
            init_task = ensure_procinit(pid)
            if !isnothing(init_task)
                init_tasks[pid] = init_task
            end
        end
        return init_tasks   
    finally
        unlock(allprocs_management_lock())
    end
end


"""
    ParallelProcessingTools.ensure_procinit_or_kill(pid::Int)

Ensure Julia process `pid` is either initialized successfully, or killed and
removed if the initialization fails.

See also [`ParallelProcessingTools.ensure_procinit`](@ref).
"""
function ensure_procinit_or_kill(pid::Int)
    try
        wait_for_all(ensure_procinit(pid))
    catch err
        orig_err = original_exception(err)
        @warn "Error while initializig process $pid, removing it." orig_err
        rmprocs(pid)
    end
    return nothing
end



"""
    @always_everywhere(expr)

Runs `expr` on all current Julia processes, but also all future Julia
processes added via [`addworkers`](@ref)) and/or added to an
[`ElasticWorkerPool`](@ref).

Similar to `Distributed.everywhere`, but also stores `expr` so that
`addworkers` can execute it automatically on new worker processes.

`expr` is run immediately on the current process, but asynchronously on
remote processes. `@always_everywhere` returns a `Task` that can be awaited
to ensure all remote processes have been initialized.

Asynchronous example:

```julia
@always_everywhere begin
    using SomePackage
    using SomeOtherPackage
    
    some_global_variable = 42
end
```

Synchronous example:

```julia
wait(@always_everywhere begin
    using YetAnotherPackage
end)
```

See also [`ParallelProcessingTools.add_procinit_code`](@ref) and
[`ParallelProcessingTools.ensure_procinit`](@ref).
"""
macro always_everywhere(ex)
    # Code partially taken from Distributed.@everywhere
    quote
        let ex = Expr(:toplevel, :(task_local_storage()[:SOURCE_PATH] = $(get(task_local_storage(), :SOURCE_PATH, nothing))), $(esc(Expr(:quote, ex))))
            try
                lock(allprocs_management_lock())
    
                add_procinit_code(ex)
                init_dict = ensure_procinit(Distributed.procs())

                # Wait for initialization of all remote processes

                remote_init_task = let objs_to_wait_for = collect(values(init_dict))
                    Threads.@spawn wait_for_all(objs_to_wait_for)
                end

                remote_init_task
            finally
                unlock(allprocs_management_lock())
            end
        end
    end
end
export @always_everywhere
