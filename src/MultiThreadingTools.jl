# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

__precompile__(true)

module MultiThreadingTools

include.([
    "threadsafe.jl",
    "threadlocal.jl",
    "threadedexec.jl",
    "processexec.jl",
    "workpartition.jl",
])

end # module
