module ParallelProcessingToolsThreadPinningExt

import ParallelProcessingTools
import LinearAlgebra
import Distributed
import ThreadPinning

using ThreadPinning: ispinned, getaffinity,
    cpuids, node, core, ncores, socket, nsockets, nnuma, numa, ishyperthread, isefficiencycore,
    getcpuids, pinthreads, openblas_getcpuids, openblas_pinthreads

using ThreadPinning.Utility: affinitymask2cpuids

using LinearAlgebra.BLAS: get_num_threads as blas_nthreads
using LinearAlgebra.BLAS: set_num_threads as set_blas_nthreads
using Random



# ThreadPinning.jl does not fully support all operating systems, currently:
const _threadpinning_supported = try
    @assert convert(Int, ThreadPinning.getcpuid()) isa Int
    true
catch err
    false
end


@static if _threadpinning_supported


function _get_core_map()
    core_map = IdDict{Int, Int}()
    for core_id in 1:ncores()
        for cpu_id in core(core_id)
            core_map[cpu_id] = core_id
        end
    end
    return core_map
end


function _maybe_set_blas_nthreads(avail_ncores::Integer = 0)
    if haskey(ENV, "OPENBLAS_NUM_THREADS")
        @info("OPENBLAS_NUM_THREADS set, not changing number of BLAS threads.")
    elseif haskey(ENV, "OMP_NUM_THREADS")
        @info("OMP_NUM_THREADS set, not changing number of BLAS threads.")
    elseif avail_ncores > 0
        @info "Setting number of BLAS threads to $avail_ncores (number of physical CPU cores in affinity mask)"
        set_blas_nthreads(avail_ncores)
    else
        n = Threads.nthreads()
        if blas_nthreads() != n
            @info "Setting number of BLAS threads to $n (same as number of Julia threads)"
            set_blas_nthreads(n)
        end
    end
end


function _pin_threads_to(unsorted_sel_cpus_julia::AbstractVector{Int}, unsorted_sel_cpus_blas::AbstractVector{Int}, pin_blas::Bool)
    sel_cpus_julia = sort(unsorted_sel_cpus_julia)
    sel_cpus_blas = sort(unsorted_sel_cpus_blas)
    if length(sel_cpus_julia) >= Threads.nthreads()
        @info "Pinning Julia threads to CPU IDs $sel_cpus_julia"
        pinthreads(sel_cpus_julia)

        if pin_blas
            if isempty(intersect(sel_cpus_julia, sel_cpus_blas))
                if length(sel_cpus_blas) >= blas_nthreads()
                    @info "Pinning OpenBLAS threads to CPU IDs $sel_cpus_blas"
                    openblas_pinthreads(sel_cpus_blas)
                    # Partial mitigation for ThreadPinning issue #105, ensure
                    # Julia threads are pinned correcty, at least:
                    pinthreads(sel_cpus_julia)
                else
                    @warn "Can't pin $(blas_nthreads()) BLAS threads, found only $(length(sel_cpus_blas)) suitable CPU IDs."
                end
            else
                @warn "Won't pin BLAS threads on same CPU IDs as the Julia threads"
            end
        end    
    else
        @warn "Can't pin $(Threads.nthreads()) Julia threads, found only $(length(sel_cpus_julia)) suitable CPU IDs."
    end
end


function _log_thread_pinning()
    if ispinned()
        julia_cpuids = sort(getcpuids())
        @info "Julia threads pinned to CPU IDs $julia_cpuids"
    else
        @info "Julia threads not pinned."
    end

    try
        blas_cpuids = sort(openblas_getcpuids())
        @info "OpenBLAS threads pinned to CPU IDs $blas_cpuids"
    catch err
        if err isa ErrorException
            if contains(err.msg, "could not load library")
                @warn "Could not get OpenBLAS thread pinning information"
            else
                @info "OpenBLAS threads don't seem to be pinned."
            end
        else
            rethrow()
        end
    end
end


function ThreadPinning.pinthreads(mode::ParallelProcessingTools.AutoThreadPinning)
    pin_blas = mode.blas

    if ispinned()
        @info "Thread pinning already in effect, not changing it."
    elseif any(iszero, getaffinity())
        @info "Thread affinity mask available, using it."

        core_map = _get_core_map()
        # Order Index that has hyperthread CPU IDs last:
        cpuid_order_idx = IdDict(cpu_id => order_idx for (order_idx, cpu_id) in pairs(node()))

        avail_cpuids = sort(affinitymask2cpuids(getaffinity()), by = i -> cpuid_order_idx[i])
        avail_ncores = length(unique([core_map[i] for i in avail_cpuids]))

        _maybe_set_blas_nthreads(avail_ncores)

        sel_cpus_julia = avail_cpuids[begin:begin+Threads.nthreads()-1]
        sel_cpus_blas = avail_cpuids[end-blas_nthreads()+1:end]
        _pin_threads_to(sel_cpus_julia, sel_cpus_blas, pin_blas)
    elseif Threads.nthreads() < 2
        @info "Julia running single-threaded with no thread affinity mask, not pinning threads."
    elseif mode.random
        _maybe_set_blas_nthreads()
        n_julia_rest::Int = Threads.nthreads()
        n_blas_rest::Int = blas_nthreads()
        sel_cpus_julia = Int[]
        sel_cpus_blas = Int[]
        for sid in shuffle(1:nsockets())
            socket_cpus = socket(sid)
            for nid in shuffle(1:nnuma())
                cids = filter(!isefficiencycore, intersect(socket_cpus, numa(nid)))
                if !isempty(cids)
                    mainthreads_here = filter(!ishyperthread, cids)
                    perm = shuffle(eachindex(mainthreads_here))
                    mainthreads_here = mainthreads_here[perm]

                    hyperthreads_here = filter(ishyperthread, cids)
                    if axes(hyperthreads_here) == axes(mainthreads_here)
                        hyperthreads_here = hyperthreads_here[perm]
                    else
                        hyperthreads_here = shuffle(hyperthreads_here)
                    end

                    julia_threadsource = mainthreads_here
                    blas_threadsource = !isempty(hyperthreads_here) ? hyperthreads_here : mainthreads_here
                    if n_julia_rest > 0
                        n_julia_here = min(n_julia_rest, length(julia_threadsource))
                        append!(sel_cpus_julia, julia_threadsource[1:n_julia_here])
                        n_julia_rest -= n_julia_here
                    end
                    if n_blas_rest > 0
                        n_blas_here = min(n_blas_rest, length(blas_threadsource))
                        append!(sel_cpus_blas, blas_threadsource[1:n_blas_here])
                        n_blas_rest -= n_blas_here
                    end
                    !(n_julia_rest > 0) && !(n_blas_rest > 0) && break
                end
            end
            !(n_julia_rest > 0) && !(n_blas_rest > 0) && break
        end

        _pin_threads_to(sel_cpus_julia, sel_cpus_blas, pin_blas)
    else
        _maybe_set_blas_nthreads()
        @info "No thread affinity set and random pinning not enabled, not pinning threads."
    end

    _log_thread_pinning()

    return nothing
end

function ParallelProcessingTools._pinthreads_auto_impl(::Val{true})
    pinthreads(ParallelProcessingTools.AutoThreadPinning())
end

ParallelProcessingTools._getcpuids_impl(::Val{true}) = ThreadPinning.getcpuids()


else #! _threadpinning_supported


ThreadPinning.pinthreads(::ParallelProcessingTools.AutoThreadPinning) = nothing


end # if _threadpinning_supported
    

end # module ChangesOfVariablesInverseFunctionsExt
