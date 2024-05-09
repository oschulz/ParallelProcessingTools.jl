# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

import Pkg

if !isdefined(@__MODULE__, :classic_addprocs)

function classic_addprocs(n::Integer)
    if VERSION >= v"1.10"
        addprocs(2)
    else
        # addprocs doesn't set project automatically on some older Julia versions
        addprocs(2; exeflags=`--project=$(Pkg.project().path)`)
    end
end


function test_runprocs(f_runprocs, additional_n)
    old_procs = procs()
    old_n = length(old_procs)
    expected_n = old_n + additional_n
    try
        state = @return_exceptions f_runprocs()
        @test !(state isa Exception)
        if !(state isa Exception)
            @wait_while maxtime=30 timeout_error = true (
                nprocs() < expected_n && (isnothing(state) || isactive(state))
            )
            @test isnothing(state) || isactive(state)
            @test nprocs() == expected_n
            rmprocs(setdiff(procs(), old_procs))
            @test procs() == old_procs
            @wait_while maxtime=10 isactive(state)
            @test !isactive(state)
        end
    finally
        rmprocs(setdiff(procs(), old_procs))
    end
end

end # if not already defined
