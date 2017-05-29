# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).


"""
    mtrefoldl(f_fold, f_refold, v0, c...)
"""
function mtrefoldl end
export mtrefoldl


"""
    mtmaprefoldl(f_map, f_fold, f_refold, v0, c...)
"""
function mtmaprefoldl end
export mtmaprefoldl


"""
    prefoldl(f_fold, f_refold, v0, c...)
"""
function prefoldl end
export prefoldl


"""
    pmaprefoldl(f_map, f_fold, f_refold, v0, c...)
"""
function pmaprefoldl end
export pmaprefoldl



mtrefoldl(f_fold, f_refold, v0, c) = mtmaprefoldl(identity, f_fold, f_refold, v0, c)


function mtmaprefoldl(f_map, f_fold, f_refold, v0, c)
    tl_v0 = ThreadLocal(v0)

    # Wrapping this in a function results in higher performance
    function _mtmaprefoldl_inner()
        local_v0 = tl_v0[]
        @inbounds for x in threadpartition(c)
            local_v0 = f_fold(local_v0, f_map(x))::typeof(local_v0)
        end
        tl_v0[] = local_v0
    end

    @everythread _mtmaprefoldl_inner()

    foldl(f_refold, v0, all_thread_values(tl_v0))::typeof(v0)
end


function mtmaprefoldl(f_map, f_fold, f_refold, v0, c1, cs...)
    tl_v0 = ThreadLocal(v0)
    @everythread begin
        c_part = map(threadpartition, (c1, cs...))
        local_v0 = tl_v0[]
        @inbounds for x in zip(c_part...)
            local_v0 = f_fold(local_v0, f_map(x...))::typeof(local_v0)
        end
        tl_v0[] = local_v0
    end
    foldl(f_refold, v0, all_thread_values(tl_v0))::typeof(v0)
end



prefoldl(f_fold, f_refold, v0, c...) = pmaprefoldl(identity, f_fold, f_refold, v0, c...)


function pmaprefoldl(f_map, f_fold, f_refold, v0, c...)
    reductions = @everyworker begin
        local_v0 = deepcopy(v0)
        c_part = map(processpartition, c)
        mtmaprefoldl(f_map, f_fold, f_refold, local_v0, c_part...)
    end
    foldl(f_refold, v0, reductions)::typeof(v0)
end
