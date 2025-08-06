# ParallelProcessingTools.jl

This Julia package provides some tools to ease multithreaded and distributed programming.


## Distributed computing

Julia provides native support for distributed computing on multiple Julia processes that run in parallel on the same or on different machines. ParallelProcessingTools add some machinery to make some aspects of this even easier.

An internal elastic cluster manager ([`ppt_cluster_manager`](@ref), a modified version of `ParallelProcessingTools.ElasticManager`), started on demand, allows for starting ([`runworkers`](@ref)) an stopping ([`stopworkers`](@ref)) worker processes in a dynamic fashion. The worker processes can also be started outside of the Julia session ([`worker_start_command`](@ref) and [`write_worker_start_script`](@ref)), this can be useful to add worker to a running Julia session via manually controlled batch jobs, for example. Workers can be started locally ([`OnLocalhost`](@ref)), via SLURM ([`OnSlurm`](@ref)), or via HTCondor ([`OnHTCondor`](@ref)). Other methods to start workers (e.g. via SSH) may be added in the future (contributions are very welcome).

The elastic cluster manager automatically adds new workers to an automatically created dynamic worker pool ([`ppt_worker_pool`](@ref)) of type [`FlexWorkerPool`](@ref) that optionally supports oversubscription. Users can `take!` workers from the pool and `put!` them back, or use [`onworker`](@ref) to send work to workers in the pool without exceeding their maximum occupancy.

Since workers can appear and disappear dynamically, initializing them (loading packages, etc.) via the standard `Distributed.@everywhere` macro is problematic, as workers added afterwards won't be initialized. Parallel processing tools provides the macro [`@always_everywhere`](@ref) to run code globally on all current processes, but also store the code so it can be run again on future new worker processes. Workers that are part of a [`FlexWorkerPool`](@ref) will be updated automatically on `take!` and `onworker`. You can also use [`ensure_procinit`](@ref) to manually update all workers
to all `@always_everywhere` used so far.

[`AutoThreadPinning`](@ref), in conjunction with the package [`ThreadPinning`](https://github.com/carstenbauer/ThreadPinning.jl/), provides a convenient way to perform automatic thread pinning (e.g. inside of `@always_everywhere`, to apply thead pinning to all processes). Note that `ThreadPinning.pinthreads(AutoThreadPinning())` works on a best-effort basis and that advanced applications may require customized thread pinning for best performance.

Some batch system configurations can result in whole Julia processes, or even a whole batch job, being terminated if a process exceeds its memory limit. In such cases, you can try to gain a softer failure mode by setting a custom (slightly smaller) memory limit using [`memory_limit!`](@ref).

For example:

```julia
ENV["JULIA_DEBUG"] = "ParallelProcessingTools"
ENV["JULIA_WORKER_TIMEOUT"] = "120"

using ParallelProcessingTools, Distributed

@always_everywhere begin
    using ParallelProcessingTools
    using Statistics

    import ThreadPinning
    pinthreads_auto()

    # Optional: Set a custom memory limit for worker processes:
    # myid() != 1 && memory_limit!(8 * 1000^3) # 8 GB
end

runmode = OnLocalhost(n = 4)
# runmode = lkSlurmRun(slurm_flags = `--ntasks=4 --cpus-per-task=8 --mem-per-cpu=8G`)

display(worker_start_command(runmode))

# Add some workers and initialize with all `@always_everywhere` code:
old_nprocs = nprocs()
_, n = runworkers(runmode)
@wait_while nprocs() < old_nprocs + n
ensure_procinit()

# Show worker resources:
pool = ppt_worker_pool()
display(pool)
display(worker_resources())

# Confirm that Distributions is loaded on a worker:
worker = last(workers())
@fetchfrom worker mean(rand(100))

# Some more init code
@always_everywhere begin
    X = rand(100)
end

# Add some more workers, we won't run `ensure_procinit()` manually this time:
old_nprocs = nprocs()
_, n = runworkers(runmode)
@wait_while nprocs() < old_nprocs + n

# Worker hasn't run @always_everywhere code yet, so it doesn't have `mean`:
worker = last(workers())
display(@return_exceptions @userfriendly_exceptions begin
    @fetchfrom worker mean(X)
end)

# Using `take!` on a `FlexWorkerPool` automatically runs init code as necessary:
pid = take!(pool)
try
    remotecall_fetch(() -> mean(X), pid)
finally
    put!(pool, pid)
end

# `onworker` (using the default `FlexWorkerPool` here) does the same:
onworker(mean, X)

# If we don't need workers processes for a while, let's stop them:
stopworkers()
```

We can also use SLURM batch scripts, like this (e.g. "batchtest.jl"):

```julia
#!/usr/bin/env julia
#SBATCH --ntasks=4 --cpus-per-task=8 --mem-per-cpu=8G --time=00:15:00

using Pkg; pkg"activate @SOME_JULIA_ENVIRONMENT"

ENV["JULIA_DEBUG"] = "ParallelProcessingTools"
ENV["JULIA_WORKER_TIMEOUT"] = "120"

using ParallelProcessingTools, Distributed

@always_everywhere begin
    using ParallelProcessingTools
    import ThreadPinning
    pinthreads_auto()
end

_, n = runworkers(OnSlurm(slurm_flags = `--cpu-bind=cores --mem-bind=local`))
@wait_while maxtime=240 nprocs() < n + 1

resources = worker_resources()
display(resources)

stopworkers()
```

This should run with a simple

```shell
sbatch -o out.txt batchtest.jl
```

and "out.txt" should then contain debugging output and a list of the worker
resources.


## Multithreading

To test multithreading performance and help debug and optimize multithreaded
code, ParallelProcessingTools provides the utility macros [`@onthreads`](@ref)
to run code explicitly on the selected Julia threads (all threads can be
listed using [`allthreads`](@ref)).

You can use the macro [`@critical`](@ref) to prevent code that may suffer from race conditions in parallel to other code fenced by `@critical`.

The macro [`@mt_out_of_order`](@ref) is useful to run different code on in parallel on Julia threads.


# Waiting and sleeping

In a parallel computing scenario, on threads, distributed processes or both, or when dealing with I/O operations, code often needs to wait. In addition a timeout mechanism is often necessary. Julia's standard `wait` function can only waits a single object without a timeout. (`waitany`, requires Julia >= v1.12, can be used to wait for multiple tasks).

ParallelProcessingTools provides a very flexible macro [`@wait_while`](@ref) to wait for custom conditions with an optional timeout, as well as the functions [`wait_for_all`](@ref) and [`wait_for_any`](@ref) that can wait for different kinds of objects, also with an optional timeout.

The functions [`sleep_ns`](@ref) and [`idle_sleep`](@ref) can be used to implement custom scenarios that require precise sleeping for both very short and long intervals.


# Exception handling

Exceptions throws during remote code execution can be complex, nested and sometimes hard to understand. You can use the functions [`inner_exception`](@ref), [`onlyfirst_exception`](@ref) and [`original_exception`](@ref) to get to the underlying reason of a failure more easily. The macro [`@userfriendly_exceptions`](@ref) automatizes this to some extent for a given piece of code.

To get an exception "in hand" for further analysis, you can use the macro [`@return_exceptions`](@ref) to make (possibly failing) code return the exceptions instead of throwing it.


# File I/O

File handling can become more challenging when working in a parallel and possibly distributed fashion. Code or whole workers can crash, resulting in corrupt files, or workers may become disconnected, but still write files and clash with restarted code (resulting in race conditions and may also result in corrupt files).

ParallelProcessingTools provides the functions [`write_files`](@ref) and [`read_files`](@ref) to implement atomic file operations, on a best-effort basis (depending on the operating system and underlying file systems).
