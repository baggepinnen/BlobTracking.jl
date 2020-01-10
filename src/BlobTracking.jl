module BlobTracking

using Statistics, LinearAlgebra
using Images, ImageFiltering, ImageDraw, VideoIO
using LowLevelParticleFilters, Hungarian, StaticArrays, Distributions, Distances, Interact, MultivariateStats

export BlobTracker, Blob, Recorder, track_blobs, showblobs, tune_sizes, FrameBuffer, MedianBackground, PCABackground, update!, TrackingResult, Measurement, location, threshold, invthreshold, OOB, lifetime, Trace, trace, allblobs, draw!



include("framebuffer.jl")
include("background.jl")
include("blob.jl")
include("display.jl")


const OOB = CartesianIndex(0,0)
@inline to_static(a::Number) = a
@inline to_static(a::AbstractMatrix) = SMatrix{size(a)...}(a)
@inline to_static(a::AbstractVector) = SVector{length(a)}(a)



function Base.iterate(vid::VideoIO.VideoReader)
    state = read(vid)
    (Gray.(state)),state
end
function Base.iterate(vid::VideoIO.VideoReader, state)
    eof(vid) && return nothing
    read!(vid,state)
    (Gray.(state)),state
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
    assi = hungarian(sqrt.(DM))[1]
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
            push!(blobs[bi].trace, OOB)
        end
    end
end

LowLevelParticleFilters.predict!(result::TrackingResult) = predict!(result.blobs)
LowLevelParticleFilters.correct!(result::TrackingResult, measurement::Measurement) = correct!(result.blobs, measurement)

function LowLevelParticleFilters.update!(blob_storage, storage, bt, img, result)
    blobs = result.blobs
    measurement = Measurement(blob_storage, storage, bt, img, result)
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

function measure(blob_storage,storage, bt::BlobTracker, img)
    prepare_image!(storage,bt,img)
    coordinates = detect_blobs!(blob_storage,storage, bt, img)
    bt.mask === nothing || (coordinates = filter!(c->bt.mask[c] != 0, coordinates))
    coordinates
end

function Measurement(blob_storage,storage, bt::BlobTracker, img::AbstractMatrix, result)
    coordinates = measure(blob_storage,storage, bt, img)
    assi = assign(bt, result.blobs, coordinates)
    measurement = Measurement(coordinates, assi)
end

function Measurement(_,_, bt::BlobTracker, coordinates::Trace, result)
    assi = assign(bt, result.blobs, coordinates)
    measurement = Measurement(coordinates, assi)
end

function track_blobs(bt::BlobTracker, vid; display=false, recorder=nothing)
    result = TrackingResult()
    img,vid = Iterators.peel(vid)
    t1 = Ref{Task}()
    t2 = Ref{Task}()
    vidbuffer = Channel{typeof(img)}(2, spawn=true, taskref=t1) do ch
        for img in vid
            put!(ch,img)
        end
    end
    storage1 = Float32.(Gray.(img))
    storage2 = Float32.(Gray.(img))
    storage = Float32.(Gray.(img))
    blob_storage1 = Array{Float64}(undef, length(bt.sizes), size(img)...)
    blob_storage2 = Array{Float64}(undef, length(bt.sizes), size(img)...)
    blob_storage = Array{Float64}(undef, length(bt.sizes), size(img)...)
    measurement = Measurement(blob_storage1, storage1, bt, img, result)
    spawn_blobs!(result, bt, measurement)
    showblobs(RGB.(Gray.(img)), result, measurement, recorder = recorder, display=display)

    buffer = Channel{Tuple{typeof(img), Trace}}(2, spawn=false, taskref=t2) do ch
        # for img in vidbuffer
        #     coords = measure(storage1, bt, img)
        #     put!(ch, (img, coords))
        # end
        while isready(vidbuffer)
            img1 = take!(vidbuffer)
            m1 = Threads.@spawn measure(blob_storage1, storage1, bt, img1)
            img2 = nothing
            if isready(vidbuffer)
                img2 = take!(vidbuffer)
                m2 = Threads.@spawn measure(blob_storage2, storage2, bt, img2)
            end
            put!(ch,(img1, fetch(m1)))
            if img2 === nothing
                return
            else
                put!(ch,(img2, fetch(m2)))
            end
        end
    end

    try
        for (ind,(img,coords)) in enumerate(buffer)
            println("Frame $ind")
            measurement = update!(blob_storage, storage, bt, coords, result)
            showblobs(RGB.(Gray.(img)),result,measurement, rad=6, recorder=recorder, display=display)
        end
    finally
        finalize(recorder)
    end
    result#, t1,t2
end



end # module
