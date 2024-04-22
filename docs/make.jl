# Use
#
#     DOCUMENTER_DEBUG=true julia --color=yes make.jl local [nonstrict] [fixdoctests]
#
# for local builds.

using Documenter
using ParallelProcessingTools

# Doctest setup
DocMeta.setdocmeta!(
    ParallelProcessingTools,
    :DocTestSetup,
    :(using ParallelProcessingTools);
    recursive=true,
)

makedocs(
    sitename = "ParallelProcessingTools",
    modules = [ParallelProcessingTools],
    format = Documenter.HTML(
        prettyurls = !("local" in ARGS),
        canonical = "https://oschulz.github.io/ParallelProcessingTools.jl/stable/"
    ),
    pages = [
        "Home" => "index.md",
        "API" => "api.md",
        "LICENSE" => "LICENSE.md",
    ],
    doctest = ("fixdoctests" in ARGS) ? :fix : true,
    linkcheck = !("nonstrict" in ARGS),
    warnonly = ("nonstrict" in ARGS),
)

deploydocs(
    repo = "github.com/oschulz/ParallelProcessingTools.jl.git",
    forcepush = true,
    push_preview = true,
)
