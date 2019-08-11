# ParallelProcessingTools.jl

[![Build Status](https://travis-ci.com/oschulz/ParallelProcessingTools.jl.svg?branch=master)](https://travis-ci.com/oschulz/ParallelProcessingTools.jl)
[![Codecov](https://codecov.io/gh/oschulz/ParallelProcessingTools.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/oschulz/ParallelProcessingTools.jl)

This Julia package provides some tools to ease multithreaded and distributed programming, especially for more complex use cases and when using multiple processes with multiple threads on each process.

This package follows the SPMD (Single Program Multiple Data) paradigm (like, e.g MPI, Cuda, OpenCL and
`DistributedArrays.SPMD`): Run the same code on every execution unit (process or thread) and make the code responsible for figuring out which part of the data it should process. This differs from the approach of `Base.Threads.@threads` and `Distributed.@distributed`. SPMD is more appropriate for complex cases that the latter do not handle well (e.g. because some initial setup is required on each execution unit and/or iteration scheme over the data is more complex, control over SIMD processing is required, etc.).

This package also implements thread-local variables and tooling to handle non-thread-safe code.

In addition, the package provides some functions and macros designed to ease the transition to the new multi-threading model introduced in Julia v1.3.

Note: Some features may not work on Windows, currently.


## Work partitions

`workpart` partitions an `AbstractArray` across a a specified set of workers (i.e. processes or threads). E.g.

```julia
A = rand(100)
workpart(A, 4:7, 5) == view(A, 26:50)
```

returns a views into the array that worker `5` out of a set or workers `4:7` will be responsible for. The intended usage is

```julia
using Distributed, Base.Threads
@everywhere data = rand(1000)
@everywhere procsel = workers()
@onprocs procsel begin
    sub_A = workpart(data, procsel, myid())
    threadsel = allthreads()
    @onthreads threadsel begin
        # ... some initialization, create local buffers, etc.
        idxs = workpart(eachindex(sub_A), threadsel, threadid())
        for i in idxs
            # ... A[i] ...
        end
    end
end
```

see below for a full example.

If `data` is a `DistributedArrays.DArray`, then `DistributedArrays.localpart(data)` should be used instead of `workpart(data, workers(), myid())`.


## Thread-safety

Use `@critical` to mark non thread-safe code, e.g. for logging. For example

```julia
@onthreads allthreads() begin
    @critical @info Base.Threads.threadid()
end
```

would crash Julia without `@critical` because `@info` is not thread-safe.

Note: This doesn't always work for multithreaded code on other processes yet.


# Thread-local variables

Thread-local variable can be created and initialized via

```julia
tl = ThreadLocal(0.0)
```

The API is the similar to `Ref`: `tl[]` gets the value of `tl` for the current thread, `tl[] = 4.2` sets the value for the current thread. `getallvalues(tl)` returns the values for all threads as a vector, and can only be called from single-threaded code.


# Multithreaded code execution

The macro `@onthreads threadsel expr` will run the code in `expr` on the threads in `threadsel` (typically a range of thread IDs). For convenience, the package exports `allthreads() = 1:nthreads()`. Here's a simple example on how to use thread-local variables and `@onthreads` to sum up numbers in parallel:

```julia
tlsum = ThreadLocal(0.0)
data = rand(100)
@onthreads allthreads() begin
    tlsum[] = sum(workpart(data, allthreads(), Base.Threads.threadid()))
end
sum(getallvalues(tlsum)) ≈ sum(data)
```

`@onthreads` forwards exceptions thrown by the code in `expr` to the caller (in contrast to, `Base.Threads.@threads`, that will currently print an exception but not forward it, so when using `@threads` program execution simply continues after a failure in multithreaded code).

Note: Julia can currently run only one function on multiple threads at the same time (this restriction is likely to disappear in the the future). So even if `threadsel` does not include all threads, the rest of the threads will be idle but blocked and cannot be used to run other code in parallel. However, the ability to run on a subset of the available threads is still useful to measure the scaling behavior of multithreaded code (without restarting Julia with a different value for `$JULIA_NUM_THREADS`).



# Multiprocess code execution

The macro `@onprocs procsel expr` will run the code in `expr` on the processes in `procsel` (typically an
array of process IDs). `@onprocs` returns a vector with the result of `expr` on each process and
will wait until all the results are available (but may of course be wrapped in `@async`). A
simple example to get the process ID on each worker process:

```julia
using Distributed
addprocs(2)
workers() == @onprocs workers() myid()
```

Note: If the data can be expressed in terms of a `DistributedArrays.DArray`, it may be more appropriate and convenient to use the multiprocess execution tooling available in the package `DistributedArrays` (possibly combined with `ParallelProcessingTools.@onthreads`).


# Creating multithreaded workers

Julia currently doesn't provide an easy way to start multithreaded worker instances. `ParallelProcessingTools` provides a script `mtjulia.sh` (currently Linux-only) that will start Julia with `$JULIA_NUM_THREADS` set to a suitable value for each worker host (currently the number of physical processes on one NUMA node). `mtjulia_exe()` will return the absolute path to `mtjulia.sh`. So multithreaded workers can be spawned (via SSH) like this:

```julia
addprocs([hostname1, ...], exename = mtjulia_exe())
```


### Example use case: 

As a simple real-world use case, let's histogram distributed data on multiple processes and threads:

Set up a cluster of multithreaded workers and load the required packages:

```julia
using Distributed, ParallelProcessingTools
addprocs(["hostname1", ...], exename = mtjulia_exe())
@everywhere using ParallelProcessingTools, Base.Threads,
    DistributedArrays, Statistics, StatsBase
```

Create some distributed data and check how the data is distributed:

```julia
data = drandn(10^8)
procsel = procs(data)
@onprocs procsel size(localpart(data))
```

Check the number of threads on each worker holding a part of the data:

```julia
@onprocs procsel nthreads()
```

Create histograms in parallel on all threads of all workers and merge:

```julia
proc_hists = @onprocs procsel begin
    local_data = localpart(data)
    tl_hist = ThreadLocal(Histogram((-6:0.1:6,), :left))
    @onthreads allthreads() begin
        data_for_this_thread = workpart(local_data, allthreads(), threadid())
        append!(tl_hist[], data_for_this_thread)
    end
    merged_hist = merge(getallvalues(tl_hist)...)
end
final_hist = merge(proc_hists...)
```

Check result:

```
sum(final_hist.weights) ≈ length(data)

using Plots
plot(final_hist)
```

Note: This example is meant to show how to combine the features of this package. The multi-process part of this particular use case can be written in a simpler way using functionality from `DistributedArrays`.
