# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


struct ProgressState
    from::Float64
    to::Float64
    current::Float64
end


mutable struct ProgressEntry
    id::Int
    parent::Int
    description::String
    state::ProgressState
end


#!!!! make const
g_progress_channel_lock = ReentrantLock()

#!!!! use const Ref
g_progress_channel = nothing

#!!!! make const
g_progress_states = IdDict{Int,ProgressEntry}()


function _register_progress_impl(description::AbstractString, state::ProgressState, parent::Union{Int,Nothing})
    try
        lock(g_progress_channel_lock)
        if isnothing(g_progress_channel)
            g_progress_channel = Channel(_progresss_channel_impl, spawn = true)
        end
        g_progress_channel
    finally
        unlock(g_progress_channel_lock)
    end
end


function register_progress(description::AbstractString, state::ProgressState = ProgressState(0, 0, 0) ; parent::Union{Int,Nothing} = nothing)
    id, channel = remotecall_fetch(_register_progress_impl, 1, description, state, parent)
end
