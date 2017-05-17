# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

using Base.Threads
using MultiThreadingTools


export ProgressInfo

type ProgressInfo{RangeT<:OrdinalRange}
    range::RangeT
    last_time::Float64
    interval::Float64
    threads::OrdinalRange{Int,Int}

    (::Type{ProgressInfo{RangeT}}){RangeT}(range::RangeT, interval::Real, threads::OrdinalRange) =
        new{RangeT}(range, 0, interval, threads)
end

ProgressInfo{T<:Integer}(range::OrdinalRange{T}, interval::Real = 1, threads::OrdinalRange = 1:1) =
    ProgressInfo{typeof(range)}(range, interval, threads)


function (pinfo::ProgressInfo)(i::Integer)
    range = pinfo.range
    Base.checkbounds_indices(Bool, (range,), (i,)) || throw(ArgumentError("Index out of range"))
    current_time = time()
    tid = threadid()
    if tid in pinfo.threads && current_time - pinfo.last_time > pinfo.interval
        pinfo.last_time = current_time
        n = length(range)
        j = i - first(range) + 1
        percent_done = round(100 * (j - 1)/n, 2)
        threadsafe_info("Thread $tid: Processing element $j of $n, $(percent_done)% done.")
    end
end
