# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

__precompile__(true)

module ParallelProcessingTools

using Base.Threads
using Distributed

import LinearAlgebra
import Pkg

import ClusterManagers
import ThreadPinning

using Parameters: @with_kw

include("threadsafe.jl")
include("threadlocal.jl")
include("onthreads.jl")
include("onprocs.jl")
include("workpartition.jl")
include("addworkers.jl")
include("slurm.jl")
include("deprecated.jl")

end # module
