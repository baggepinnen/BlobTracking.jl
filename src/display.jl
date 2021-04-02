"""
    Recorder

Struct used to record tracking results to a video.

# Keyword Arguments:
- `filename = "trackingresult.mp4"`
- `framerate = 30`
"""
Base.@kwdef mutable struct Recorder
    filename = "trackingresult.mp4"
    framerate = 30
    encoder = nothing
    index::Int = 1
end

function Recorder(img; kwargs...)
    encoder_options = (crf=22, preset="medium")
    filename = "trackingresult.mp4"
    Recorder(;encoder=open_video_out(filename, img; framerate=framerate, encoder_options=encoder_options), kwargs...)
end


"""
    showblobs(img::AbstractMatrix{T}, result::TrackingResult, m::Measurement; rad=8, recorder=nothing, display=true) where T

Overlay found blobs on `img`

#Arguments:
- `img`: an image
- `result`: a `TrackingResult`
- `m`: a `Measurement`
- `rad`: radius of blobs to draw
- `recorder`: an optional `Recorder`
- `display = Base.display`: function to display image. Use `display=nothing` to not display.
"""
function showblobs(img::AbstractMatrix{T},result,m;rad=8, recorder=nothing, display=Base.display, ignoreempty=false) where T
    # img = copy(img)
    display === nothing && recorder === nothing && return
    if ignoreempty
        isempty(result.blobs) && isempty(m.coordinates) && return
    end
    blobs = result.blobs
    foreach(blobs) do blob
        blobcoord = location(blob)
        c = length(blob.trace) == 1 ? RGB{eltype(T)}(0.,1.,0.) : RGB{eltype(T)}(0.,0.,1.)
        draw!(img, ImageDraw.CirclePointRadius(blobcoord, rad),c)
        mcoord = blob.trace[end]
        mcoord == OOB && return
        draw!(img, ImageDraw.LineSegment(blobcoord, mcoord))
    end
    foreach(enumerate(m.coordinates)) do (ci,coord)
        c = RGB{eltype(T)}(1.,0.,0.) # ci ∈ newcoordinds ? RGB{T}(0,1,0) : RGB{T}(1,0,0)
        draw!(img, ImageDraw.CirclePointRadius(coord, rad/2), c)
    end
    record(img, recorder)
    if display !== nothing
        display(img)
    end
    img
end

record(_, ::Nothing) = nothing

function record(img, recorder)
    r = recorder
    if r.encoder === nothing
        encoder_options = (crf=22, preset="medium")
        r.encoder = open_video_out(recorder.filename, img, framerate=r.framerate, encoder_options=encoder_options)
    end
    VideoIO.write(r.encoder, img, r.index)
    r.index += 1
end

Base.finalize(::Nothing) = nothing
function Base.finalize(r::Recorder)
    close_video_out!(r.encoder)
end

ImageDraw.draw!(img,b::Images.BlobLoG;kwargs...) = draw!(img,location(b);kwargs...)
ImageDraw.draw!(img,coord::CartesianIndex;a=3,c=RGB(1.,0.,0.)) = draw!(img, CirclePointRadius(coord, float(a)), eltype(img)(c))

function ImageDraw.draw!(img, trace::Trace, args...; c=RGB(1,1,1), kwargs...)
    trace = skipmissing(trace)
    draw!(img, trace[1], c=RGB(0,1,0))
    draw!(img, trace[end], c=RGB(1,0,0))
    draw!(img, ImageDraw.Path(trace), eltype(img)(c), args...; kwargs...)
end

function ImageDraw.draw!(img, traces::Vector{Trace}, args...; kwargs...)
    for trace in traces
        ImageDraw.draw!(img, trace, args...; kwargs...)
    end
    img
end
