# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


struct ProgressState
    from::Float64
    to::Float64
    t_start::UInt64
    progress::Float64
    t_current::UInt64
end

ProgressState() = ProgressState(0, 1, time_ns(), 0)

ProgressState(old::ProgressState, progress::Float64, t_current::UInt64) =
    ProgressState(old.from, old.to, old.t_start, progress, t_current)


mutable struct ProgressEntry
    id::Int
    parent::Int
    description::String
    state::ProgressState
end


#!!!! make const
g_progress_lock = ReentrantLock()

#!!!! use const Ref
g_progress_channel = nothing

#!!!! make const
g_progress_states = IdDict{Int,ProgressEntry}()

#!!!! make const
g_progress_nextid = Atomic{Int}(0)


function _progresss_channel_impl(ch::Channel{Tuple{Int,Float64,Bool}})
    while true
        try
            lock(g_progress_lock)
            if isempty(g_progress_states)
                break
            else
                id, progress, done = take!(ch)
                entry = g_progress_states[id]
                ProgressState(entry.state, progress, t_current)
                new_entry = ProgressEntry(entry.from, entry.to, progress)
                g_progress_states[id] = new_entry

                #!!!!! show progress
                @info "Total progress:"
            end
        finally
            unlock(g_progress_lock)
        end
    end
end

function _register_progress_impl(description::AbstractString, state::ProgressState, parent::Union{Int,Nothing})
    try
        lock(g_progress_lock)
        id = atomic_add!(g_progress_nextid, 1)
        entry = ProgressEntry(id, parent, description, state)
        if isnothing(g_progress_channel) || !isopen(g_progress_channel)
            @assert isempty(g_progress_states)
            g_progress_states[id] = entry
            g_progress_channel = Channel(_progresss_channel_impl, 1000, spawn = true)
        else
            @assert !haskey(g_progress_states, id)
            g_progress_states[id] = entry
        end
        id, g_progress_channel
    finally
        unlock(g_progress_lock)
    end
end


function register_progress(description::AbstractString, state::ProgressState = ProgressState() ; parent::Union{Int,Nothing} = nothing)
    id, channel = remotecall_fetch(_register_progress_impl, 1, description, state, parent)
end
