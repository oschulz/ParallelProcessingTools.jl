# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed
using ParallelProcessingTools: isactive

include("testtools.jl")

old_julia_debug = get(ENV, "JULIA_DEBUG", "")
ENV["JULIA_DEBUG"] = old_julia_debug * ",ParallelProcessingTools"
stopworkers()

if !isdefined(@__MODULE__, :mytask)
    @always_everywhere begin
        struct MyExceptionRetry <: Exception
            msg::String
        end
        ParallelProcessingTools._should_retry(::MyExceptionRetry) = true
        
        struct MyExceptionNoRetry <: Exception
            msg::String
        end
        ParallelProcessingTools._should_retry(::MyExceptionNoRetry) = false
    
        using Distributed
        function mytask(runtime::Real = 2, args...)
            sleep(runtime)
            @info "Hello from worker $(myid()), have to do $args."
            return args
        end
    end
    
    function gen_mayfail(failure_probability::Real)
        function failtask(args...)
            @info "Hello from worker $(myid()), have to do $args, but may fail with $(failure_probability)% probably."
            if rand() < failure_probability
                throw(MyExceptionRetry("Predictably failed doing $args"))
            else
                return args
            end
        end
    end
end


@testset "onworkers" begin
    runmode = OnLocalhost(n = 2)

    @testset "runworkers $(nameof(typeof(runmode)))" begin
        test_runprocs(2) do
            runworkers(runmode)[1]
        end
    end

    #=
    # Run manually for now, fails when run during CI tests for some reason:

    if Sys.isunix()
        @testset "write_worker_start_script $(nameof(typeof(runmode)))" begin
            mktempdir(prefix = "ppt-startscript-test") do dir
                test_runprocs(2) do
                    startscript = write_worker_start_script(joinpath(dir, "startjlworkers.sh"), runmode)
                    open(`$startscript`)
                end
            end
        end
    end
    =#

    #=
    # For Debugging:
    try; onworker(() -> error("foo"), label = "myactivity") ; catch err; err; end
    try; onworker(() -> 42, 2, label = "myactivity") ; catch err; err; end
    try; onworker(() -> 42, label = "myactivity") ; catch err; err; end
    try; onworker((x) -> 40 + x, 2, label = "myactivity") ; catch err; err; end
    try; onworker(() -> sleep(5), label = "myactivity", maxtime = 1) ; catch err; err; end
    try; onworker(() -> sleep(5), label = "myactivity", maxtime = 1, tries = 3) ; catch err; err; end
    =#

    @test @inferred(onworker(mytask)) == ()
    @test @inferred(onworker(mytask, 1, "foo")) == ("foo", )
    @test @inferred(onworker(gen_mayfail(0.5), "foo", 42; tries = 20, label = "mayfail")) == ("foo", 42)

    @test_throws ParallelProcessingTools.MaxTriesExceeded onworker(gen_mayfail(1), "bar"; tries = 2, label = "mayfail")
    @test_throws ParallelProcessingTools.MaxTriesExceeded onworker(mytask, 2, "foo", maxtime = 0.5, tries = 2)
    
    runworkers(OnLocalhost(n = 2))

    timer = Timer(30)
    @wait_while nprocs() < 3 && isopen(timer)
    @test nprocs() == 3
    resources = worker_resources()
    @test length(resources) == 2

    @sync begin
        for i in 1:8
            @async onworker(mytask, 1, i)
        end
    end

    @test @inferred(onworker(mytask)) == ()
    @test @inferred(onworker(mytask, 1, "foo")) == ("foo", )
    @test @inferred(onworker(gen_mayfail(0.5), "foo", 42; tries = 20, label = "mayfail")) == ("foo", 42)

    @test_throws ParallelProcessingTools.MaxTriesExceeded onworker(gen_mayfail(1), "bar"; tries = 2, label = "mayfail")


    #=
    # Run these manually for now. Not sure how to make Test enviroment ignore the
    # EOFError exceptions that originate when we kill workers due to timeouts.

    @test_throws ParallelProcessingTools.MaxTriesExceeded onworker(mytask, 2, "foo", time = 0.5, tries = 2)
    @test nprocs() == 1

    addworkers(OnLocalhost(2))

    @test @inferred(onworker(mytask)) == ()
    @test @inferred(onworker(mytask, 1, "foo")) == ("foo", )
    @test @inferred(onworker(gen_mayfail(0.5), "foo", 42; tries = 20, label = "mayfail")) == ("foo", 42)

    @test_throws ParallelProcessingTools.MaxTriesExceeded onworker(gen_mayfail(1), "bar"; tries = 2, label = "mayfail")
    @test_throws ParallelProcessingTools.MaxTriesExceeded onworker(mytask, 2, "foo", time = 0.5, tries = 2)
    =#
end

stopworkers()
ENV["JULIA_DEBUG"] = old_julia_debug
