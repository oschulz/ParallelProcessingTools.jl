# This file is a part of jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools

using Distributed

using ParallelProcessingTools: allprocs_management_lock, proc_management_lock,
    current_procinit_level, global_procinit_level, get_procinit_code,
    add_procinit_code, ensure_procinit

using ParallelProcessingTools: _global_procinit_level, _current_procinit_level,
    _g_initial_procinit_code, _g_procinit_code, _g_wrapped_procinit_code,
    _store_additional_procinit_code, _execute_procinit_code

include("testtools.jl")

old_julia_debug = get(ENV, "JULIA_DEBUG", "")
ENV["JULIA_DEBUG"] = old_julia_debug * ",ParallelProcessingTools"


@testset "procinit" begin
    @test @inferred(allprocs_management_lock()) isa ReentrantLock
    @test @inferred(proc_management_lock(1)) isa ReentrantLock
    @test @inferred(current_procinit_level()) isa Integer
    @test @inferred(global_procinit_level()) isa Integer

    @test @inferred(get_procinit_code()) isa Expr

    # Test that current procces is sure to get initialized on ensure_procinit
    push!(_g_initial_procinit_code.args, :(_g_inittest1 = 101))
    cinitlvl = current_procinit_level()
    ginitlvl = global_procinit_level()
    @test @inferred(ensure_procinit([myid()])) isa Nothing
    @test global_procinit_level() == ginitlvl
    @test current_procinit_level() == global_procinit_level()
    @test Main._g_inittest1 == 101

    # Reset current process init state for testing:
    _current_procinit_level[] = 0
    
    # Test that current procces is sure to get initialized on ensure_procinit
    push!(_g_initial_procinit_code.args, :(_g_inittest2 = 102))
    cinitlvl = current_procinit_level()
    ginitlvl = global_procinit_level()
    @test add_procinit_code(:(@info "Begin init")) isa Nothing
    @test global_procinit_level() == ginitlvl + 1
    @test current_procinit_level() == global_procinit_level()
    @test Main._g_inittest2 == 102

    # Test that _execute_procinit_code runs cleanly:
    _dummy_initstep_expr = :(_g_inittest3 = 103)
    _global_procinit_level[] = _global_procinit_level[] + 1
    _store_additional_procinit_code(_dummy_initstep_expr, global_procinit_level())
    @info "The following \"Dummy error\" error message is expected"
    @test_throws ErrorException _execute_procinit_code(:(error("Dummy error")), global_procinit_level())
    @test _execute_procinit_code(get_procinit_code(), global_procinit_level()) isa Nothing
    @test current_procinit_level() == global_procinit_level()
    @test Main._g_inittest3 == 103
    @info "The following \"Failed to raise process 1 init level\" error message is expected"
    @test_throws ErrorException _execute_procinit_code(get_procinit_code(), global_procinit_level() + 1)

    # Test that output of _initcode_wrapperexpr runs cleanly:
    _dummy_initstep_expr = :(_g_inittest4 = 104)
    _global_procinit_level[] = _global_procinit_level[] + 1
    _store_additional_procinit_code(_dummy_initstep_expr, global_procinit_level())
    @test Core.eval(Main, _g_wrapped_procinit_code) isa Nothing
    @test current_procinit_level() == global_procinit_level()
    @test Main._g_inittest4 == 104

    add_procinit_code(:(_g_somevar1 = 201))
    @test Main._g_somevar1 == 201

    @always_everywhere begin
        _g_somevar2 = 202
    end
    @test Main._g_somevar2 == 202

    classic_addprocs(2)
    ensure_procinit(workers()[end])

    @test remotecall_fetch(last(workers())) do 
        _g_inittest1 + _g_inittest2 + _g_inittest3 + _g_inittest4 + _g_somevar1 + _g_somevar2
    end == 813

    rmprocs(workers())
end

ENV["JULIA_DEBUG"] = old_julia_debug
