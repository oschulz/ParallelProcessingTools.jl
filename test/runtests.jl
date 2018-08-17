# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

import Test
Test.@testset "Package ParallelProcessingTools" begin
    include("threadsafe.jl")
    include("threadlocal.jl")
    include("workpartition.jl")
end
