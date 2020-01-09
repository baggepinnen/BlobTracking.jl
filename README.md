# BlobTracking

[![Build Status](https://travis-ci.org/baggepinnen/BlobTracking.jl.svg?branch=master)](https://travis-ci.org/baggepinnen/BlobTracking.jl)
[![Codecov](https://codecov.io/gh/baggepinnen/BlobTracking.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/baggepinnen/BlobTracking.jl)

*Work in progress*

Detect and track blobs (like birds or bugs) moving around in an image. Blobs are detected using simple [Laplacian-of-Gaussian filtering](https://en.wikipedia.org/wiki/Blob_detection) (from [Images.jl](https://juliaimages.org/latest/function_reference/#Images.blob_LoG)) and tracked using a Kalman filter from [LowLevelParticleFilters.jl](https://github.com/baggepinnen/LowLevelParticleFilters.jl).

This package contains some facilities for the afromentioned detection and tracking, as well as some utilities for background removal etc.



## Usage
Something like this:
```julia
using BlobTracking, Images, VideoIO
path = "/home/fredrikb/Video/2_small.MP4"
io   = VideoIO.open(path)
vid  = VideoIO.openvideo(io)
img  = first(vid)
fb   = FrameBuffer(Gray.(img), 10)
foreach(1:10) do i
    push!(fb,first(vid))
end
mask = Gray.(median(fb) .> 0.4) |> reduce(∘, fill(erode, 10))

bt = BlobTracker(sizes=2:5, mask=mask)
tune_sizes(bt, img)

@time active, dead = track_blobs(bt, vid, display=true, recorder=Recorder())
```
