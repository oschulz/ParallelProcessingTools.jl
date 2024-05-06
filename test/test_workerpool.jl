# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed

old_julia_debug = get(ENV, "JULIA_DEBUG", "")
ENV["JULIA_DEBUG"] = old_julia_debug * ",ParallelProcessingTools"

if !isdefined(@__MODULE__, :wp_test_func)
    @always_everywhere begin
        wp_test_func() = 42
    end
end

@testset "workerpool" begin
    @test wp_test_func() == 42

    pool = FlexWorkerPool(withmyid = true, caching = false, label = "mypool", maxoccupancy = 3)
    
    # no workers yet, pool should fall back to using myid():
    @test @inferred(workers(pool)) == [myid()]
    @test @inferred(length(pool)) == length(workers(pool))
    pids = [@inferred(take!(pool)) for _ in 1:3]
    @test remotecall_fetch(() -> wp_test_func(), first(pids)) == 42
    @test @inferred(isready(pool)) == false
    @test sort(pids) == repeat([myid()], 3)
    foreach(pid -> @inferred(put!(pool, pid)), pids)
    @test isready(pool) == true

    # This should be a no-op, as myid() is already in the pool:
    @test push!(pool, myid()) isa FlexWorkerPool

    prev_workers = workers()
    addprocs(2)
    new_workers = setdiff(workers(), prev_workers)

    # pool2 has no fallback to myid() and doesn_t init workers:
    pool2 = FlexWorkerPool{WorkerPool}(new_workers, maxoccupancy = 3, init_workers = false)

    foreach(pid -> push!(pool2, pid), new_workers)
    @test workers(pool2) == new_workers
    @test length(pool2) == length(workers(pool2))
    pids = [take!(pool2) for _ in 1:2*3]
    @test_throws UndefVarError @userfriendly_exceptions remotecall_fetch(() -> wp_test_func(), first(pids))
    @test isready(pool2) == false
    @test sort(pids) == sort(repeat(new_workers, 3))
    foreach(pid -> put!(pool2, pid), pids)
    @test isready(pool2) == true

    # Add new workers to pool:
    foreach(pid -> @inferred(push!(pool, pid)), new_workers)

    @test workers(pool) == new_workers
    @test length(pool) == length(workers(pool))
    pids = [take!(pool) for _ in 1:2*3]
    @test remotecall_fetch(() -> wp_test_func(), first(pids)) == 42
    @test isready(pool) == false
    @test sort(pids) == sort(repeat(new_workers, 3))
    foreach(pid -> put!(pool, pid), pids)
    @test isready(pool) == true

    # This should be a no-op, as the workers are already in the pool:
    @test push!(pool, first(new_workers)) isa FlexWorkerPool
    @test push!(pool2, first(new_workers)) isa FlexWorkerPool

    rmprocs(new_workers)

    # Workers are gone, should show a warning, but not throw an exception
    # (ToDo: Use @test_warn):
    @test push!(pool, first(new_workers)) isa FlexWorkerPool
    @test push!(pool2, first(new_workers)) isa FlexWorkerPool

    # no more workers, pool should fall back to using myid():
    pids = [take!(pool) for _ in 1:3]
    # length should be updated now:
    @test length(pool) == 1
    @test sort(pids) == repeat([myid()], 3)
    foreach(pid -> put!(pool, pid), pids)
 
    # Trigger update of pool2._pool:
    @test_throws ErrorException take!(pool2._pool)
    @test length(pool2) == 0

    # Allow fallback to myid() for pool2:
    push!(pool2, myid())
    @test length(pool2) == 1

    pids = [take!(pool2) for _ in 1:3]
    @test sort(pids) == repeat([myid()], 3)
    foreach(pid -> put!(pool2, pid), pids)

    pool3 = ppt_worker_pool()
    @test pool3 isa FlexWorkerPool
    @test workers(pool3) == [myid()]
end

ENV["JULIA_DEBUG"] = old_julia_debug
