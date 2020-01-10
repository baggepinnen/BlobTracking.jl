module BlobTracking

using Statistics, LinearAlgebra
using Images, ImageFiltering, ImageDraw, VideoIO
using LowLevelParticleFilters, Hungarian, StaticArrays, Distributions, Distances, Interact, MultivariateStats

export BlobTracker, Blob, Recorder, track_blobs, showblobs, drawblob!, tune_sizes, FrameBuffer, MedianBackground, PCABackground, update!



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
threshold!(storage, img, th) = storage .= Gray.(Gray.(img) .< th)

struct Measurement
    coordinates
    assi
end

function assign(blobs, coordinates)
    isempty(blobs) && (return 1:length(coordinates))
    DM = [dist(b,c) for b in blobs, c in coordinates]
    DM[DM .> DIST_TH] .= 10000
    assi = hungarian(DM)[1]
end

function filter!(bt, m)
    for (bi, ass) in enumerate(m.assi)
        blob = blobs[bi]
        if ass == 0 || too_far(blob,coordinates[ass]) # penalize not found
            blob.counter += 1
            assi[bi] = 0
            continue
        end
    end
end

function LowLevelParticleFilters.predict!(blobs)
    foreach(blob->predict!(blob.kf,0), blobs)
end

function LowLevelParticleFilters.correct!(blobs, measurement)
    for (bi, ass) in enumerate(measurement.assi)
        if ass != 0
            ll = correct!(blobs[bi].kf,0,SVector(measurement.coordinates[ass].I))
        end
    end
end

LowLevelParticleFilters.predict!(result::TrackingResult) = predict!(result.blobs)
LowLevelParticleFilters.correct!(result::TrackingResult, measurement) = correct!(result.blobs, measurement)

function LowLevelParticleFilters.update!(storage, bt, img, result)
    blobs,dead = result.blobs, result.dead
    prepare_image!(storage,bt,img)
    coordinates = detect_blobs!(storage, bt, img)
    assi = assign(blobs, coordinates)
    measurement = Measurement(coordinates, assi)
    predict!(result)
    filter!(bt, measurement)
    correct!(result, measurement)
    spawn_blobs!(result, bt, measurement)
    showblobs(img,blobs,coordinates,newcoordinds, assi, rad=6, recorder=recorder, display=display)
    kill_blobs!(result, bt)
end

function spawn_blobs!(result, bt, measurement)
    newcoordinds = setdiff(1:length(measurement.coordinates), measurement.assi)
    newblobs = Blob.(bt, coordinates[newcoordinds])
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
    assi = assign(result.blobs, coordinates)
    measurement = Measurement(coordinates, assi)
end

function track_blobs(bt::BlobTracker, vid; display=false, recorder=nothing)
    result = TrackingResult()
    img = first(vid)
    storage = Gray.(img)
    prepare_image!(storage,bt,img)
    measurement = measure(storage, bt, img, result)
    spawn_blobs!(result, bt, measurement)
    showblobs(img, result.blobs, coordinates, recorder = recorder, display=display)

    for (ind,img) in enumerate(vid)
        println("Frame $ind")
        update!(storage, bt, img, result)
    end
    finalize(recorder)
    result
end



end # module
