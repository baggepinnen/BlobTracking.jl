Base.@kwdef mutable struct Recorder
    filename = "trackingresult.mp4"
    framerate = 24
    encoder = nothing
    saveio = Base.open("temp.stream","w")
    index::Int = 1
end

Recorder(img;kwargs...) = Recorder(;encoder=prepareencoder(img, framerate=framerate, AVCodecContextProperties=[:priv_data => ("crf"=>"22","preset"=>"medium")]), kwargs...)



function showblobs(img,blobs,coords,newcoordinds=[0], assi=zeros(length(blobs));rad=8, recorder=nothing, display=true)
    # img = copy(img)
    !display && recorder === nothing && return
    foreach(eachindex(assi)) do bi
        blob = blobs[bi]
        blobcoord = CartesianIndex(blob)
        draw!(img, ImageDraw.CirclePointRadius(blobcoord, rad),RGB(0,0,1))
        a = assi[bi]
        a == 0 && return
        draw!(img, ImageDraw.LineSegment(blobcoord, coords[a]))
    end
    foreach(enumerate(coords)) do (ci,coord)
        c = ci ∈ newcoordinds ? RGB(0,1,0) : RGB(1,0,0)
        draw!(img, ImageDraw.CirclePointRadius(coord, rad/2), c)
    end
    record(img, recorder)
    display && Base.display(img)
    img
end

record(_, ::Nothing) = nothing

function record(img, recorder)
    r = recorder
    if r.encoder === nothing
        r.encoder=prepareencoder(img, framerate=r.framerate, AVCodecContextProperties=[:priv_data => ("crf"=>"22","preset"=>"medium")])
    end
    appendencode!(r.encoder, r.saveio, img, r.index)
    r.index += 1
end

drawblob!(img;a=3,c=RGB(1,0,0)) = draw!(img, CirclePointRadius(b.location, a), c)
