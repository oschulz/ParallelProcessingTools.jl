# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

__precompile__(true)

module ParallelProcessingTools

using Base.Threads
using Distributed

import LinearAlgebra
import Pkg
import Random # Required by ThreadPinning extention
import Sockets

using Base: Process
using Logging: @logmsg, LogLevel, Info, Debug

using ArgCheck: @argcheck
using Parameters: @with_kw

using ElasticClusterManager: ElasticManager, elastic_worker

# For backward compatibility:
module CustomClusterManagers
    import ElasticClusterManager.ElasticManager
end

include("memory.jl")
include("display.jl")
include("waiting.jl")
include("exceptions.jl")
include("states.jl")
include("fileio.jl")
include("threadsafe.jl")
include("threadlocal.jl")
include("onthreads.jl")
include("onprocs.jl")
include("workpartition.jl")
include("procinit.jl")
include("workerpool.jl")
include("onworkers.jl")
include("runworkers.jl")
include("slurm.jl")
include("htcondor.jl")
include("deprecated.jl")

end # module
