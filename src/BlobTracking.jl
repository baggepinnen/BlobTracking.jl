module BlobTracking

using Statistics, LinearAlgebra
using Images, ImageFiltering, ImageDraw, VideoIO
using LowLevelParticleFilters, Hungarian, StaticArrays, Distributions, Distances, Interact, MultivariateStats

export BlobTracker, Blob, Recorder, track_blobs, showblobs, drawblob!, tune_sizes, FrameBuffer, MedianBackground, PCABackground, update!, TrackingResult, Measurement, location, threshold, invthreshold



include("framebuffer.jl")
include("background.jl")
include("blob.jl")
include("display.jl")

@inline to_static(a::Number) = a
@inline to_static(a::AbstractMatrix) = SMatrix{size(a)...}(a)
@inline to_static(a::AbstractVector) = SVector{length(a)}(a)



function Base.iterate(vid::VideoIO.VideoReader)
    state = read(vid)
    state,state
end
function Base.iterate(vid::VideoIO.VideoReader, state)
    eof(vid) && return nothing
    read!(vid,state)
    state,state
end

threshold(th::Number) =  (storage, img) -> threshold!(storage, img, th)
threshold!(storage, img, th) = storage .= Gray.(Float32.(Gray.(img) .> th))

invthreshold(th::Number) =  (storage, img) -> invthreshold!(storage, img, th)
invthreshold!(storage, img, th) = storage .= Gray.(Float32.(Gray.(img) .< th))

struct Measurement
    coordinates
    assi
end

function assign(bt, blobs, coordinates)
    isempty(blobs) && (return Int[])
    isempty(coordinates) && (return zeros(Int, length(blobs)))
    DM = [dist(bt,b,c) for b in blobs, c in coordinates]
    DM[DM .> bt.dist_th] .= 100000
    assi = hungarian(DM)[1]
end

function Base.filter!(result, bt::BlobTracker, m::Measurement)
    for (bi, ass) in enumerate(m.assi)
        blob = result.blobs[bi]
        if ass == 0 || too_far(bt, blob,m.coordinates[ass]) # penalize not found
            blob.counter += 1
            m.assi[bi] = 0
            continue
        end
    end
    m
end

function LowLevelParticleFilters.predict!(blobs)
    foreach(blob->predict!(blob.kf,0), blobs)
end

function LowLevelParticleFilters.correct!(blobs, measurement::Measurement)
    for (bi, ass) in enumerate(measurement.assi)
        if ass != 0
            ll = correct!(blobs[bi].kf,SVector(measurement.coordinates[ass].I))
            push!(blobs[bi].trace, measurement.coordinates[ass])
        else
            push!(blobs[bi].trace, CartesianIndex(0,0))
        end
    end
end

LowLevelParticleFilters.predict!(result::TrackingResult) = predict!(result.blobs)
LowLevelParticleFilters.correct!(result::TrackingResult, measurement) = correct!(result.blobs, measurement)

function LowLevelParticleFilters.update!(storage, bt, img, result)
    blobs = result.blobs
    prepare_image!(storage,bt,img)
    measurement = measure(storage, bt, img, result)
    predict!(result)
    filter!(result, bt, measurement)
    correct!(result, measurement)
    spawn_blobs!(result, bt, measurement)
    kill_blobs!(result, bt)
    measurement
end

function spawn_blobs!(result, bt, measurement)
    newcoordinds = setdiff(1:length(measurement.coordinates), measurement.assi)
    newblobs = Blob.(bt, measurement.coordinates[newcoordinds])
    append!(result.blobs, newblobs)
end

function kill_blobs!(result, bt)
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

function measure(storage, bt, img, result)
    coordinates = detect_blobs!(storage, bt, img)
    bt.mask === nothing || (coordinates = filter!(c->bt.mask[c] != 0, coordinates))
    assi = assign(bt, result.blobs, coordinates)
    measurement = Measurement(coordinates, assi)
end

function track_blobs(bt::BlobTracker, vid; display=false, recorder=nothing)
    result = TrackingResult()
    img,vid = Iterators.peel(vid)
    storage = Gray.(img)
    prepare_image!(storage,bt,img)
    measurement = measure(storage, bt, img, result)
    spawn_blobs!(result, bt, measurement)
    showblobs(img, result, measurement, recorder = recorder, display=display)

    for (ind,img) in enumerate(vid)
        println("Frame $ind")
        measurement = update!(storage, bt, img, result)
        showblobs(img,result,measurement, rad=6, recorder=recorder, display=display)
    end
    finalize(recorder)
    result
end



end # module
