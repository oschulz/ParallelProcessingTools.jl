# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

import Test
import Aqua
import ParallelProcessingTools

Test.@testset "Package ambiguities" begin
    Test.@test isempty(Test.detect_ambiguities(ParallelProcessingTools))
end # testset

Test.@testset "Aqua tests" begin
    Aqua.test_all(
        ParallelProcessingTools,
        ambiguities = true
    )
end # testset
