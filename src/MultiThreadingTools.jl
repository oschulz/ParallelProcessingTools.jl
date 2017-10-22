# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

__precompile__(true)

module MultiThreadingTools

include("threadsafe.jl")
include("threadlocal.jl")
include("threadedexec.jl")
include("processexec.jl")
include("workpartition.jl")
include("reductions.jl")

end # module
