module BlobTracking
using Statistics, LinearAlgebra
using Images, ImageFiltering, ImageDraw, VideoIO
using LowLevelParticleFilters, Hungarian, StaticArrays, Distributions, Distances, Interact, NearestNeighbors
using JuliennedArrays # For faster median etc.

export BlobTracker, Blob, Recorder, track_blobs, showblobs, tune_sizes, FrameBuffer, MedianBackground, DiffBackground, background, foreground, update!, TrackingResult, Measurement, location, threshold, invthreshold, OOB, lifetime, Trace, trace, tracem, allblobs, draw!, to_static, get_coordinates

export AbstractCorrespondence, HungarianCorrespondence, NearestNeighborCorrespondence, MCCorrespondence

"""
    Workspace{T1, T2}

Contains buffer arrays that can be resued to minimize allocations
"""
struct Workspace{T1,T2}
    storage::T1
    blob_storage::T2
end

"""
    Workspace(img::AbstractMatrix, n::Int)

Provide example image and length of `bt.sizes`
"""
function Workspace(img::AbstractMatrix, n::Int)
    storage = Gray.(img)
    blob_storage = Array{Float64}(undef, size(img)..., n)
    Workspace(storage,blob_storage)
end

struct Measurement
    coordinates
    assi
end

const OOB = CartesianIndex(0,0)
@inline to_static(a::Number) = a
@inline to_static(a::AbstractMatrix) = SMatrix{size(a)...}(a)
@inline to_static(a::AbstractVector) = SVector{length(a)}(a)
@inline to_static(a::CartesianIndex{2}) = SVector{2}(a.I)



include("correspondence_types.jl")
include("framebuffer.jl")
include("background.jl")
include("blob.jl")
include("trackingresult.jl")
include("correspondence.jl")
include("display.jl")

Workspace(img::AbstractMatrix, bt::BlobTracker) = Workspace(img, length(bt.sizes))

function Base.iterate(vid::VideoIO.VideoReader)
    state = read(vid)
    (Gray.(state)),state
end
function Base.iterate(vid::VideoIO.VideoReader, state)
    eof(vid) && return nothing
    read!(vid,state)
    (Gray.(state)),state
end


function Base.filter!(result::TrackingResult, bt::BlobTracker, m::Measurement, step=1)
    for (bi, ass) in enumerate(m.assi)
        blob = result.blobs[bi]
        if ass == 0 || too_far(bt.correspondence, blob,m.coordinates[ass]) # penalize not found
            blob.counter += step
            m.assi[bi] = 0
        else
            blob.counter = max(0, blob.counter-step) # decrement counter if measurement found
        end
    end
    m
end

function Base.filter!(result::TrackingResult, bt::BlobTracker, measurements::Vector{Measurement})
    N = length(measurements)
    map(measurements) do m
        filter!(result, bt, m, 1/N)
    end
end

"""
    predict!(blobs)

Advance all blobs by predicting their next state
"""
function LowLevelParticleFilters.predict!(blobs)
    foreach(blob->predict!(blob.kf,0), blobs)
end

"""
    correct!(blobs, measurement::Measurement)

Correct the state of the blobs by incorporating the measurement in the Kalman filter
"""
function LowLevelParticleFilters.correct!(blobs::Vector, measurement::Measurement)
    for (bi, ass) in enumerate(measurement.assi)
        if ass != 0
            ll = correct!(blobs[bi].kf,SVector(measurement.coordinates[ass].I))
            push!(blobs[bi].tracem, measurement.coordinates[ass])
        else
            push!(blobs[bi].tracem, OOB)
        end
        push!(blobs[bi].trace, location(blobs[bi]))
    end
end

LowLevelParticleFilters.predict!(result::TrackingResult) = predict!(result.blobs)
LowLevelParticleFilters.correct!(result::TrackingResult, measurement) = correct!(result.blobs, measurement)


function LowLevelParticleFilters.correct!(blobs::Vector, measurements::Vector{Measurement})
    N = length(measurements)
    R2 = copy(blobs[1].kf.R2)
    for measurement in measurements
        for (bi, ass) in enumerate(measurement.assi)
            blob = blobs[bi]
            if ass != 0
                blob.kf.R2 .*= N # QUESTION N or N^2?
                ll = correct!(blob.kf,SVector(measurement.coordinates[ass].I))
                blob.kf.R2 .= R2
                push!(blob.tracem, measurement.coordinates[ass])
            else
                push!(blob.tracem, OOB)
            end
            push!(blob.trace, location(blob))
        end
    end
 end

"""
    update!(ws::Workspace, bt::BlobTracker, coords_or_img, result::TrackingResult)

Perform one iteration of predict and correct

#Arguments:
- `ws`: a Workspace object
- `bt`: the blob tracker
- `coords_or_img`: vector of coordinates or an image
- `result`: a `TrackingResult`
"""
function LowLevelParticleFilters.update!(ws, bt::BlobTracker, coords_or_img, result::TrackingResult)
    blobs = result.blobs
    measurement = Measurement(ws, bt, coords_or_img, result)
    predict!(result)
    filter!(result, bt, measurement)
    correct!(result, measurement)
    spawn_blobs!(result, bt, measurement)
    kill_blobs!(result, bt)
    measurement
end

function spawn_blobs!(result::TrackingResult, bt::BlobTracker, measurement)
    newcoordinds = setdiff(1:length(measurement.coordinates), measurement.assi)
    newblobs = Blob.(bt.params, measurement.coordinates[newcoordinds])
    append!(result.blobs, newblobs)
end

function spawn_blobs!(result::TrackingResult, bt::BlobTracker, measurements::Vector{Measurement})
    for measurement in measurements
        spawn_blobs!(result, bt, measurement)
    end
end

"""
    kill_blobs!(result::TrackingResult, bt::BlobTracker)

Kill all blobs that have not seen a measurement for the duration `bt.kill_counter_th`
"""
function kill_blobs!(result::TrackingResult, bt::BlobTracker)
    blobs,dead = result.blobs, result.dead
    bi = 1
    while bi <= length(blobs)
        if blobs[bi].counter > bt.kill_counter_th
            push!(dead, blobs[bi])
            deleteat!(blobs, bi)
        else
            bi += 1
        end
    end
end

"""
    coordinates = measure(ws::Workspace, bt::BlobTracker, img)

Detect blobs in the image and return the coordinates

#Arguments:
- `ws`: Workspace
- `bt`: BlobTracker
- `img`: image
"""
function measure(ws::Workspace, bt::BlobTracker, img)
    prepare_image!(ws,bt,img)
    coordinates = detect_blobs!(ws, bt, img)
    bt.mask === nothing || (coordinates = filter!(c->bt.mask[c] != 0, coordinates))
    coordinates
end

function Measurement(ws, bt::BlobTracker, img::AbstractMatrix, result)
    coordinates = measure(ws, bt, img)
    if isempty(result.blobs) && bt.correspondence isa MCCorrespondence
        measurement = assign(bt.correspondence.inner, result.blobs, coordinates)
    else
        measurement = assign(bt.correspondence, result.blobs, coordinates)
    end
    log_measurement(result, measurement)
    measurement
end

function Measurement(_, bt::BlobTracker, coordinates::Trace, result)
    if isempty(result.blobs) && bt.correspondence isa MCCorrespondence
        measurement = assign(bt.correspondence.inner, result.blobs, coordinates)
    else
        measurement = assign(bt.correspondence, result.blobs, coordinates)
    end
    log_measurement(result, measurement)
    measurement
end

"""
    track_blobs(bt::BlobTracker, vid; display=false, recorder=nothing, threads=Threads.nthreads() > 1, ignoreempty=false)

Main entry point to tracking blobs

#Arguments:
- `bt`: a BlobTracker
- `vid`: Some iterable thing that iterates images
- `display = Base.display`: function to display images live. Displaying live slows things down a bit. Use `display=nothing` to not display anything. Consider also `c = imshow(img);
displayfun = img -> imshow!(c["gui"]["canvas"],img); `.
- `recorder`: an optional `Recorder` that can record each frame to a video on disk. Recording things does not slow things down much and also does not affect memory usage much.
- `threads`: Use threaded processing of frames? Only useful if Julia is started with multiple threads.
- `ignoreempty=false`: wether or not to ignore display and recording of frames which contains no blobs and no measurements.
"""
function track_blobs(bt::BlobTracker, vid; display=nothing, recorder=nothing, threads=Threads.nthreads()>1, ignoreempty=false)
    result = TrackingResult()
    buffer = threads ? coordinate_iterator(bt, vid) : vid
    img,buffer = Iterators.peel(buffer)
    ws = Workspace(img, length(bt.sizes))
    img, coord_or_img = img isa Tuple ? img : (img,img)
    measurement = Measurement(ws, bt, coord_or_img, result)
    spawn_blobs!(result, bt, measurement)
    showblobs(RGB.(Gray.(img)), result, measurement, recorder = recorder, display=display)

    try
        for (ind,img) in enumerate(buffer)
            println("Frame $ind")
            img, coord_or_img = img isa Tuple ? img : (img,img)
            measurement = update!(ws, bt, coord_or_img , result)
            showblobs(RGB.(Gray.(img)),result,measurement, rad=6, recorder=recorder, display=display, ignoreempty=ignoreempty)
        end
    finally
        finalize(recorder)
    end
    result
end


function track_blobs(bt::BlobTracker, coords::Vector{Trace})
    result = TrackingResult()
    measurement = Measurement(nothing, bt, coords[1], result)
    spawn_blobs!(result, bt, measurement)
    for coord in coords[2:end]
        measurement = update!(nothing, bt, coord , result)
    end
    result
end

function get_coordinates(bt::BlobTracker, vid; threads=Threads.nthreads()>1)
    coords = Trace[]
    if threads
        for (img, coord) in coordinate_iterator(bt, vid)
            push!(coords, coord)
        end
    else
        img,vid = Iterators.peel(vid)
        ws = Workspace(copy(img), length(bt.sizes))
        for img in vid
            coord = measure(ws1, bt, img)
            push!(coords, coord)
        end
    end
    coords
end

function coordinate_iterator(bt, vid)
    img1 = iterate(vid)
    img1 === nothing && return
    img1,state = img1

    ws1 = Workspace(copy(img1), length(bt.sizes))
    ws2 = Workspace(copy(img1), length(bt.sizes))
    m1 = measure(ws1, bt, img1)

    Channel{Tuple{typeof(img1), Trace}}(3, spawn=false) do ch
        put!(ch,(img1, m1))
        while true
            img1 = iterate(vid, state)
            img1 === nothing && return
            img1,state = img1
            m1 = Threads.@spawn measure(ws1, bt, img1)
            img2 = iterate(vid, state)
            if img2 !== nothing
                img2,state = img2
                m2 = Threads.@spawn measure(ws2, bt, img2)
            end
            put!(ch,(img1, fetch(m1)))
            if img2 === nothing
                return
            else
                put!(ch,(img2, fetch(m2)))
            end
        end
    end
end



end # module
