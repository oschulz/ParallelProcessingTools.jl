# ParallelProcessingTools.jl

This Julia package provides some tools to ease multithreaded and distributed programming.


## Compute cluster management

ParallelProcessingTools helps spin-up Julia compute clusters. It currently has support for clusters on localhost and on SLURM (uses `ClusterManagers.ElasticManager` internally).

On SLURM, `addworkers` will automatically try to perform a sensible thread-pinning (using the [ThreadPinning](https://github.com/carstenbauer/ThreadPinning.jl) package internally).

```julia
using ParallelProcessingTools, Distributed

@always_everywhere begin
    using Distributions
end

mode = ParallelProcessingTools.SlurmRun(slurm_flags = `--ntasks=4 --cpus-per-task=8 --mem-per-cpu=8G`)
#ParallelProcessingTools.worker_start_command(mode)

# Add some workers:
addworkers(mode)

# List resources:
ParallelProcessingTools.worker_resources()

# Confirm that Distributions is loaded on workers:
worker = last(workers())
@fetchfrom worker Normal()

# Add some more workers:
addworkers(mode)
Table(ParallelProcessingTools.worker_resources())

# Add even more workers:
addworkers(mode)
Table(ParallelProcessingTools.worker_resources())
```

And we can do SLURM batch scripts like this (e.g. "batchtest.jl"):

```julia
#!/usr/bin/env -S julia --project=@SOME_JULIA_ENVIRONMENT --threads=8
#SBATCH --ntasks=4 --cpus-per-task=8 --mem-per-cpu=8G

using ParallelProcessingTools, Distributed

@always_everywhere begin
    using ParallelProcessingTools
end

addworkers(SlurmRun())
resources = ParallelProcessingTools.worker_resources()
show(stdout, MIME"text/plain"(), ParallelProcessingTools.worker_resources())
```

This should run with a simple

```shell
sbatch -o out.txt batchtest.jl
```

and "out.txt" should then contain a list of the worker resources.
