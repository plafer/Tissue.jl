using Documenter
using Tissue

makedocs(
    sitename = "Tissue",
    format = Documenter.HTML(),
    modules = [Tissue],
    pages = [
        # TODO: Add sections for
        # 1. Main concepts
        # 2. Design decisions
        "Introduction" => "index.md",
        "Getting Started" => "getting_started.md",
        "API reference" => "api_reference.md",
    ],
)


deploydocs(
    repo = "github.com/plafer/Tissue.jl.git",
)
