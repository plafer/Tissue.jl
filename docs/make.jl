using Documenter
using Tissue

makedocs(
    sitename = "Tissue",
    format = Documenter.HTML(),
    modules = [Tissue],
    pages = [
        "Introduction" => "index.md",
        "Getting Started" => "getting_started.md",
        "API reference" => "api_reference.md",
    ],
)

# TODO: Add sections for
# 1. Main concepts
# 2. Design decisions

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
