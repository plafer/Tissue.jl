# Tissue.jl
In Tissue.jl, computations to be done on an input stream are described by a directed-acyclic graph. Write how each node, called calculators, processes inputs into outputs, link these nodes together in a graph, and Tissue.jl takes care of running the whole thing, running each node in its own task. If each node is a biological cell, then a graph would be a tissue, wouldn't it?

# Acknowledgements
Tissue.jl was inspired by [MediaPipe](https://arxiv.org/abs/1906.08172).

We also use [OpenCV contrib](https://github.com/opencv/opencv_contrib) to give an example of how to use Tissue.jl in our documentation. The files `docs/src/assets/opencv_face_detector_uint8.pb` and `docs/src/assets/opencv_face_detector.pbtxt` were taken from [this repository](https://github.com/opencv/opencv_extra/tree/master/testdata/dnn), referred to in this [OpenCV tutorial](https://docs.opencv.org/4.5.2/d8/da4/tutorial_julia.html).