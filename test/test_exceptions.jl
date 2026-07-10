# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed
using ParallelProcessingTools: inner_exception, original_exception, onlyfirst_exception

@testset "exceptions" begin
    err = ErrorException("Some error")

    throw_in_task(e) = try
        wait(Threads.@spawn throw(e))
    catch tfe
        tfe
    end

    tfe = throw_in_task(err)
    nested_tfe = try
        wait(Threads.@spawn wait(Threads.@spawn throw(err)))
    catch e
        e
    end
    re = RemoteException(1, CapturedException(err, []))

    @testset "inner_exception" begin
        @test inner_exception(err) === err
        @test tfe isa TaskFailedException
        @test inner_exception(tfe) === err
        @test inner_exception(re) === err
        ce = inner_exception(CompositeException([tfe, re]))
        @test ce isa CompositeException
        @test all(e -> e === err, ce.exceptions)
        @test inner_exception(nested_tfe) isa TaskFailedException
    end

    @testset "original_exception" begin
        @test original_exception(err) === err
        @test original_exception(tfe) === err
        @test original_exception(re) === err
        @test original_exception(nested_tfe) === err
        ce = original_exception(CompositeException([nested_tfe]))
        @test only(ce.exceptions) === err
    end

    @testset "onlyfirst_exception" begin
        @test onlyfirst_exception(err) === err
        @test onlyfirst_exception(CompositeException([tfe, re])) === tfe
    end

    @testset "macro userfriendly_exceptions" begin
        @test (@userfriendly_exceptions 42) == 42

        caught = try
            @userfriendly_exceptions @sync begin
                Threads.@spawn throw(err)
                Threads.@spawn throw(ErrorException("Some other error"))
            end
        catch e
            e
        end
        @test caught isa ErrorException
    end

    @testset "macro return_exceptions" begin
        @test (@return_exceptions 42) == 42
        @test (@return_exceptions throw(err)) === err
    end
end
