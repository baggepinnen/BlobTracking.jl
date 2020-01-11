# BlobTracking

[![Build Status](https://travis-ci.org/baggepinnen/BlobTracking.jl.svg?branch=master)](https://travis-ci.org/baggepinnen/BlobTracking.jl)
[![Codecov](https://codecov.io/gh/baggepinnen/BlobTracking.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/baggepinnen/BlobTracking.jl)

*Work in progress*

Detect and track blobs (like birds or bugs) moving around in an image. Blobs are detected using simple [Laplacian-of-Gaussian filtering](https://en.wikipedia.org/wiki/Blob_detection) (from [Images.jl](https://juliaimages.org/latest/function_reference/#Images.blob_LoG)) and tracked using a Kalman filter from [LowLevelParticleFilters.jl](https://github.com/baggepinnen/LowLevelParticleFilters.jl).

This package contains some facilities for the afromentioned detection and tracking, as well as some utilities for background removal etc.



## Usage
In the example below, we are tracking birds that fly around a tree.

### Load a video
```julia
using BlobTracking, Images, VideoIO
path = "/home/fredrikb/Video/2_small.MP4"
io   = VideoIO.open(path)
vid  = VideoIO.openvideo(io)
img  = first(vid)
```
![window](figs/img.jpg)

### Create a background image
We create a background image to subtract from each image
```julia
fb   = FrameBuffer(img, 4) # A buffer of 4 frames
foreach(1:3) do i # Populate the buffer
    push!(fb,first(vid))
end
background = median(fb)
```


### Create a mask
If you want to detect birds (blobs) in the entire image, you can skip this step.

A mask is a binary image that is true where you want to be able to detect blobs and false where you want to ignore.
```julia
mask = (median(fb) .> 0.4) |> reduce(∘, fill(erode, 30)) |> reduce(∘, fill(dilate, 20))
mask[:,1190:end] .= 0
mask[end-50:end,:] .= 0
```
![window](figs/mask.png)

### Preprocessing
For the tracking to work well, it's important that we feed the tracker nice and clean images. An example of a pre-processing function looks like this
```julia
function preprocessor(storage, img)
    storage .= Float32.(img)
    storage .= Float32.(abs.(storage .- background) .> 0.3)
end
```
![window](figs/pre.png)
Notice how the tree contours are still present in this image? This is okay since that is behind the mask we created above. The mask was created by dilating the tree slightly so that the mask covers slightly more than the tree. However, in this image you can also see two small spots to the right of the tree, representing birds.

### Run tracking
We now create the `BlobTracker` and run the tracking. If we don't know an appropriate value for the `sizes` vector that determines the size scales of the blobs, we may call the function `tune_sizes` to get a small GUI with a slider to help us out (works in Juno and IJulia). The length of `sizes` has a large impact on the time it takes to process each frame since the majority of the processing time is taken up by the blob detection.
```julia
bt = BlobTracker(sizes=3:3, mask=mask,preprocessor=preprocessor,
                                        amplitude_th = 0.05,
                                        dist_th = 4,
                                        σw = 10.0, # Dynamics noise std.
                                        σe = 5.0)  # Measurement noise std. (pixels)
tune_sizes(bt, img)

result = track_blobs(bt, vid,
                         display = false, # turn on for live display
                         recorder = Recorder()) # records result to video on disk
```

### Visualization etc.

```julia
traces = trace(result, minlife=5) # Filter minimum lifetime of 5
draw!(copy(img), traces)
```
![window](figs/traces.jpg)
