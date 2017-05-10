# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

__precompile__(true)

module MultiThreadingTools

include.([
    "workerfraction.jl",
    "threadsafe.jl",
    "threadlocal.jl",
    "threadedexec.jl",
])

end # module
