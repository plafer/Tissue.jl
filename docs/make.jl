using Documenter
using Tissue

makedocs(
    sitename = "Tissue",
    format = Documenter.HTML(),
    modules = [Tissue],
)

# Documenter can also automatically deploy documentation to gh-pages.
# See "Hosting Documentation" and deploydocs() in the Documenter manual
# for more information.
#=deploydocs(
    repo = "<repository url>"
)=#
