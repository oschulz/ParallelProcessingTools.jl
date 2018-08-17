# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

__precompile__(true)

module ParallelProcessingTools

using Base.Threads

include("threadsafe.jl")
include("threadlocal.jl")
include("threadexec.jl")
include("workpartition.jl")

end # module
