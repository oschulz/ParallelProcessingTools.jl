# This file is a part of MultiThreadingTools.jl, licensed under the MIT License (MIT).

import Compat.Test
Test.@testset "Package MultiThreadingTools" begin
    include("threadsafe.jl")
    include("threadlocal.jl")        
end
