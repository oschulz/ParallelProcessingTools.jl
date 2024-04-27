# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed

ENV["JULIA_DEBUG"] = "ParallelProcessingTools"


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

@static if VERSION >= v"1.9"

    @test @inferred(on_free_worker(mytask)) == ()
    @test @inferred(on_free_worker(mytask, 1, "foo")) == ("foo", )
    @test @inferred(on_free_worker(gen_mayfail(0.5), "foo", 42; tries = 20, label = "mayfail")) == ("foo", 42)

    @test_throws ParallelProcessingTools.MaxTriesExceeded on_free_worker(gen_mayfail(1), "bar"; tries = 2, label = "mayfail")
    @test_throws ParallelProcessingTools.MaxTriesExceeded on_free_worker(mytask, 2, "foo", time = 0.5, tries = 2)
    
    addworkers(LocalProcesses(2))
    @test nprocs() == 3
    resources = worker_resources()
    @test length(resources) == 2

    @sync begin
        for i in 1:8
            @async on_free_worker(mytask, 1, i)
        end
    end

    @test @inferred(on_free_worker(mytask)) == ()
    @test @inferred(on_free_worker(mytask, 1, "foo")) == ("foo", )
    @test @inferred(on_free_worker(gen_mayfail(0.5), "foo", 42; tries = 20, label = "mayfail")) == ("foo", 42)

    @test_throws ParallelProcessingTools.MaxTriesExceeded on_free_worker(gen_mayfail(1), "bar"; tries = 2, label = "mayfail")


    #=
    # Run these manually for now. Not sure how to make Test enviroment ignore the
    # EOFError exceptions that originate when we kill workers due to timeouts.

    @test_throws ParallelProcessingTools.MaxTriesExceeded on_free_worker(mytask, 2, "foo", time = 0.5, tries = 2)
    @test nprocs() == 1

    addworkers(LocalProcesses(2))

    @test @inferred(on_free_worker(mytask)) == ()
    @test @inferred(on_free_worker(mytask, 1, "foo")) == ("foo", )
    @test @inferred(on_free_worker(gen_mayfail(0.5), "foo", 42; tries = 20, label = "mayfail")) == ("foo", 42)

    @test_throws ParallelProcessingTools.MaxTriesExceeded on_free_worker(gen_mayfail(1), "bar"; tries = 2, label = "mayfail")
    @test_throws ParallelProcessingTools.MaxTriesExceeded on_free_worker(mytask, 2, "foo", time = 0.5, tries = 2)
    =#

end # Julia >= v1.9

end
