# Tissue.jl
[![](https://img.shields.io/badge/docs-stable-blue.svg)](https://plafer.github.io/Tissue.jl/stable)
[![](https://img.shields.io/badge/docs-dev-blue.svg)](https://plafer.github.io/Tissue.jl/dev)

In Tissue.jl, computations to be done on an input stream are described by a directed-acyclic graph. Write how each node, called calculators, processes inputs into outputs, link these nodes together in a graph, and Tissue.jl takes care of running the whole thing, with each calculator in its own task. If each node is a biological cell, then a graph would be a tissue, wouldn't it?

# Documentation

Our documentation is hosted [here](https://plafer.github.io/Tissue.jl/stable).

# Contributors
Want to contribute to Tissue.jl? Great! Head over to the Issues tab to get a feel for where the project is headed, or just start hacking right away on whatever you like! Pull Requests will be greatly appreciated.

# Acknowledgements
Tissue.jl was inspired by [MediaPipe](https://arxiv.org/abs/1906.08172).

We adapt code from the [OpenCV contrib](https://github.com/opencv/opencv_contrib) repository to give an example of how to use Tissue.jl in our documentation. The files 

- `docs/src/assets/opencv_face_detector_uint8.pb`
- `docs/src/assets/opencv_face_detector.pbtxt` 

were taken from [this repository](https://github.com/opencv/opencv_extra/tree/master/testdata/dnn).