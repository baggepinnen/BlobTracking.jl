# BlobTracking

[![Build Status](https://travis-ci.org/baggepinnen/BlobTracking.jl.svg?branch=master)](https://travis-ci.org/baggepinnen/BlobTracking.jl)
[![Codecov](https://codecov.io/gh/baggepinnen/BlobTracking.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/baggepinnen/BlobTracking.jl)


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

*this package implements an iterator for VideoIO videos. It only iterates black and white images, even if the original video is in color.*

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
For the tracking to work well, it's important that we feed the tracker nice and clean images. An example of a pre-processing function looks like this, it takes a storage array you can operate on in-place and the image to pre-process.
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
bt = BlobTracker(sizes=3:3, mask=mask,
                            preprocessor = preprocessor,
                            amplitude_th = 0.05,
                            dist_th = 2, # Number of sigmas away from a predicted location a measurement is accepted.
                            σw = 2.0, # Dynamics noise std.
                            σe = 10.0)  # Measurement noise std. (pixels)
tune_sizes(bt, img)

result = track_blobs(bt, vid,
                         display = Base.display, # use nothing to omit displaying.
                         recorder = Recorder()) # records result to video on disk
```
To display images in a standalone window with okay performance, consider
```julia
using ImageView
c = imshow(img)
displayfun = img -> imshow!(c["gui"]["canvas"],img);
track_blobs(...; display = displayfun)
```
Blobs are shown in blue, newly spawned blobs are show in green and measurements are shown in red.If everything is working well, most blue dots should have a red dot inside or very nearby. If the blue blobs are lagging behind the red dots, the filter needs tuning by either decreasing the measurement variance or increasing the dynamics variance. If blue dots shoot off rapidly whenever measurements are lost, the dynamics variance should be decreased.


### Visualization etc.

```julia
traces = trace(result, minlife=5) # Filter minimum lifetime of 5
measurement_traces = tracem(result, minlife=5)
drawimg = RGB.(img)
draw!(drawimg, traces, c=RGB(0,0,0.5))
draw!(drawimg, measurement_traces, c=RGB(0.5,0,0))
```
![window](figs/traces.jpg)

## Further documentation
Most functions have docstrings. Docstrings of types hints at what functions you can call on instances of the type. The types present in this package are
- `Blob`
- `BlobTracker`
- `TrackingResult`
- `Trace`
- `Recorder`
- `FrameBuffer`
- `Workspace`
