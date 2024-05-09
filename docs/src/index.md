# ParallelProcessingTools.jl

This Julia package provides some tools to ease multithreaded and distributed programming.


## Compute cluster management

ParallelProcessingTools helps spin-up Julia compute clusters. It currently has support for clusters on localhost and on SLURM (uses `ParallelProcessingTools.CustomClusterManagers.ElasticManager` internally).


```julia
ENV["JULIA_DEBUG"] = "ParallelProcessingTools"

using ParallelProcessingTools, Distributed

@always_everywhere begin
    using ParallelProcessingTools
    using Distributions
    pinthreads_auto()
end

runmode = OnLocalhost(n = 4)
# runmode = SlurmRun(slurm_flags = `--ntasks=4 --cpus-per-task=8 --mem-per-cpu=8G`)

worker_start_command(runmode)

# Add some workers and initialize with all `@always_everywhere` code:
old_nprocs = nprocs()
_, n = runworkers(runmode)
@wait_while nprocs() < old_nprocs + n
ensure_procinit()


# Show worker resources:
display(ppt_worker_pool())
display(worker_resources())

# Confirm that Distributions is loaded on a worker:
worker = last(workers())
@fetchfrom worker Normal()

# Add some more workers, we won't run `ensure_procinit()` manually this time:
old_nprocs = nprocs()
_, n = runworkers(runmode)
@wait_while nprocs() < old_nprocs + n
worker_resources()

# `onworker` uses the default ParallelProcessingTools worker pool that
# handles worker initialization automatically:
onworker(() -> Normal())
```

And we can do SLURM batch scripts like this (e.g. "batchtest.jl"):

```julia
#!/usr/bin/env julia
#SBATCH --ntasks=4 --cpus-per-task=8 --mem-per-cpu=8G --time=00:15:00

using Pkg; pkg"activate @legend-scidev"
#using Pkg; pkg"activate @SOME_JULIA_ENVIRONMENT"

ENV["JULIA_DEBUG"] = "ParallelProcessingTools"

using ParallelProcessingTools, Distributed

@always_everywhere begin
    using ParallelProcessingTools
    pinthreads_auto()
end

_, n = runworkers(SlurmRun())
@wait_while nprocs() < n + 1
ensure_procinit()
resources = worker_resources()
show(stdout, MIME"text/plain"(), resources)
```

This should run with a simple

```shell
sbatch -o out.txt batchtest.jl
```

and "out.txt" should then contain a list of the worker resources.
