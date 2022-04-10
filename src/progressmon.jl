# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


#!!!! Measure time centrally, not locally


#!!!! Allow for multiple ProgressMessage channels that may run on processes
# other than number 1, to enable hierarchical data collection schemes
# on large distributed systems.


struct ProgressState
    from::Float64
    to::Float64
    progress::Float64
    t_start::UInt64
    t_current::UInt64
end

ProgressState() = ProgressState(0, 1, 0)

function ProgressState(from::Real, to::Real, progress::Real)
    t = time_ns()
    ProgressState(from, to, progress, t, t)
end

ProgressState(old::ProgressState, progress::Real, t_current::UInt64) =
    ProgressState(old.from, old.to, progress, old.t_start, t_current)


mutable struct ProgressEntry
    id::Int
    parent::Union{Int,Nothing}
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
g_progress_nextid = Atomic{Int}(1)


function _individual_progress(state::ProgressState)
    dt = state.t_current - state.t_start
    completion = (state.progress - state.from) / (state.to / state.from)
    return (dt, completion)
end

function _total_progress(d::IdDict{Int,ProgressEntry})
    #!!! How to merge progress from parent and child states?
    ct_sum, t_sum = reduce(values(d); init = (0.0, UInt64(0))) do sums, entry
        ct_sum, t_sum = sums
        dt, completion = _individual_progress(entry.state)
        oftype(ct_sum, ct_sum + dt * completion), oftype(t_sum, t_sum + dt)
    end
    ct_sum/t_sum
end


function _show_progress(d::IdDict{Int,ProgressEntry})
    rel_progress = _total_progress(d)
    @info "Total progress: $(rel_progress * 100)%"
end


struct ProgressMessage
    id::Int
    progress::Float64
    t_current::UInt64
    done::Bool
end


function _progresss_channel_impl(ch::Channel{ProgressMessage})
    @info "DEBUG: ProgressMessage channel $ch" isopen(ch)
    #try
        while true
            sleep(0.1)
            try
                lock(g_progress_lock)
                if isempty(g_progress_states)
                    global g_progress_channel = nothing
                    @info "DEBUG: Closing ProgressMessage channel"
                    break
                end
            finally
                unlock(g_progress_lock)
            end

            @info "DEBUG: Listening on channel $ch" isopen(ch)
            msg = take!(ch)
            @info "DEBUG: Received state from id $(msg.id)"

            try
                lock(g_progress_lock)
                if msg.done
                    # Ignore msg.progress
                    delete!(g_progress_states, msg.id)
                else
                    entry = g_progress_states[msg.id]
                    entry.state = ProgressState(entry.state, msg.progress, msg.t_current)
                    _show_progress(g_progress_states)
                end
            finally
                unlock(g_progress_lock)
            end
        end
    #=!!!!!!!!!!!catch err
        try
            lock(g_progress_lock)
            empty!(g_progress_states)
            global g_progress_channel = nothing
        finally
            unlock(g_progress_lock)
        end
    end=#
end


function _register_progress_impl(description::AbstractString, state::ProgressState, parent::Union{Int,Nothing})
    try
        global g_progress_channel
        lock(g_progress_lock)
        id = atomic_add!(g_progress_nextid, 1)
        entry = ProgressEntry(id, parent, description, state)
        if isnothing(g_progress_channel) || !isopen(g_progress_channel)
            @assert isempty(g_progress_states)
            g_progress_states[id] = entry
            g_progress_channel = Channel{ProgressMessage}(100) #!!!!!!!!!!!!! Channel{ProgressMessage}(_progresss_channel_impl, 1000, spawn = true)
        else
            @assert !haskey(g_progress_states, id)
            g_progress_states[id] = entry
        end
        id, g_progress_channel
    finally
        unlock(g_progress_lock)
    end
end


struct ProgressTracker
    id::Integer
    channel::Channel{ProgressMessage}
end
export ProgressTracker

function ProgressTracker(description::AbstractString, state::ProgressState = ProgressState(); parent::Union{ProgressTracker,Nothing} = nothing)
    @nospecialize
    main_process = 1
    parent_id = isnothing(parent) ? nothing : parent.id
    ###!!!! ToDo: Direct call if running on main_process:
    #!!!id, channel = remotecall_fetch(_register_progress_impl, main_process, String(description), state, parent_id)
    id, channel = _register_progress_impl(String(description), state, parent_id)
    ProgressTracker(id, channel)
end

function Base.close(tracker::ProgressTracker)
    @info "DEBUG: Sending to $(tracker.channel)" isopen(tracker.channel)
    push!(tracker.channel, ProgressMessage(tracker.id, NaN, time_ns(), true))
    @info "DEBUG: Sent to $(tracker.channel)" isopen(tracker.channel)
end

Base.push!(tracker::ProgressTracker, progress::Real) = push!(tracker, Float64(progress))

function Base.push!(tracker::ProgressTracker, progress::Float64)
    @info "DEBUG: Sending to $(tracker.channel)" isopen(tracker.channel)
    push!(tracker.channel, ProgressMessage(tracker.id, Float64(progress), time_ns(), false))
    @info "DEBUG: Sent to $(tracker.channel)" isopen(tracker.channel)
end
