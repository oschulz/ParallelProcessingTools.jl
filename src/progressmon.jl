# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).


#!!!! Measure time centrally, not locally


#!!!! Allow for multiple ProgressReport channels that may run on processes
# other than number 1, to enable hierarchical data collection schemes
# on large distributed systems.


#!!!! New concept: ProgressTrackers reporting to ProgressCollectors, which
# report to parent ProgressCollectors. Root ProgressCollector(s) produce
# output via various methods.



#=

Example:

ProgressReport(depth = 1, op = bat_sample, alg = MCMCSampling, phase = "init", t_start = ..., t_now = ..., progress = ... )
ProgressReport(depth = 1, op = bat_sample, alg = MCMCSampling, phase = "burn-in", t_start = ..., t_now = ..., progress = ... )
ProgressReport(depth = 1, op = bat_sample, alg = MCMCSampling, phase = "sampling", t_start = ..., t_now = ..., progress = ... )
ProgressReport(depth = 1, op = bat_sample, alg = PartitionedSampling, phase = "sampling", t_start = ..., t_now = ..., progress = ... )

Progress(fraction,1:3, 1)  # Phase of algorithm, like init/burn-in/sampling
Progress(0..1, 0, 1) = Progress(==)

NSteps(n, i)
MaxNSteps(n, i)

Achieve(<|>|<=|>=, threshold, initial, current)
Achieve(in, target_interval, initial, current)

Optimize(minimum, initial, current)

=#


abstract type AbstractProgress end

Base.@kwdef struct NSteps <: AbstractProgress
    steps::Int
    current::Int
end

Base.@kwdef struct MaxNSteps <: AbstractProgress
    maxsteps::Int
    current::Int
end

Base.@kwdef struct Achieve{F<:Function,T<:Real} <: AbstractProgress
    comparison::F
    target::T
    initial::T
    current::T
end

# merge(a::AbstractProgress, b::AbstractProgress)

struct FractionComplete <: AbstractProgress
    complete::Float64
end

struct BestWorstProgress{P<:AbstractProgress} <: AbstractProgress
    best::P
    worst::P
end







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


struct ProgressReport
    id::Int
    progress::Float64
    t_current::UInt64
    done::Bool
end

struct CloseProgressCollector end

const ProgressCollectorMsg = Union{ProgressReport,CloseProgressCollector}


function _progresss_collector_impl(progress_dict::IdDict{Int,ProgressEntry}, ch::Channel{ProgressCollectorMsg})
    @info "DEBUG: ProgressReport channel $ch" isopen(ch)
    while true
        @info "DEBUG: Listening on channel $ch" isopen(ch)
        msg = take!(ch)
        @info "DEBUG: Received state from id $(msg.id)"
        if msg isa CloseProgressCollector
            # empty!(progress_dict) # would this help with GC?
            break
        elseif msg isa ProgressReport
            if msg.done
                # Ignore msg.progress
                delete!(g_progress_states, msg.id)
            else
                entry = g_progress_states[msg.id]
                entry.state = ProgressState(entry.state, msg.progress, msg.t_current)
                _show_progress(g_progress_states)
            end
        end
    end
end


struct ProgressCollector
    parent::Union{ProgressCollector,Nothing}
    channel::Channel{ProgressCollectorMsg}
end
export ProgressCollector

function ProgressCollector(parent::ProgressCollector)
    progress_dict = IdDict{Int,ProgressEntry}()
    channel = Channel{ProgressCollectorMsg}(Base.Fix1(_progresss_collector_impl, progress_dict))
    ProgressCollector(parent, channel)
end


struct ProgressTracker
    parent::ProgressCollector
    channel::Channel{ProgressCollectorMsg}
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
    push!(tracker.channel, ProgressReport(tracker.id, NaN, time_ns(), true))
    @info "DEBUG: Sent to $(tracker.channel)" isopen(tracker.channel)
end

Base.push!(tracker::ProgressTracker, progress::Real) = push!(tracker, Float64(progress))

function Base.push!(tracker::ProgressTracker, progress::Float64)
    @info "DEBUG: Sending to $(tracker.channel)" isopen(tracker.channel)
    push!(tracker.channel, ProgressReport(tracker.id, Float64(progress), time_ns(), false))
    @info "DEBUG: Sent to $(tracker.channel)" isopen(tracker.channel)
end
