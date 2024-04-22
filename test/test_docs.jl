# This file is a part of ParallelProcessingTools.jl, licensed under the MIT License (MIT).

using Test
using ParallelProcessingTools
import Documenter

Documenter.DocMeta.setdocmeta!(
    ParallelProcessingTools,
    :DocTestSetup,
    :(using ParallelProcessingTools);
    recursive=true,
)
Documenter.doctest(ParallelProcessingTools)
