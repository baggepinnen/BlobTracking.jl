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



function track_blobs(bt::BlobTracker, vid; display=false, recorder=nothing)
    img = first(vid)
    storage = Gray.(img)
    apply_mask!(storage,bt,img)
    coordinates = detect_blobs!(storage, bt, img)
    active = Blob.(coordinates)
    dead = similar(active,0)
    # candidates = similar(active,0)
    showblobs(img,active,coordinates, recorder = recorder, display=display)

    for (ind,img) in enumerate(vid)
        println("Frame $ind")
        apply_mask!(storage,bt,img)
        coordinates = detect_blobs!(storage, bt, img)
        DM = [dist(b,c) for b in active, c in coordinates]
        DM[DM .> DIST_TH] .= 10000
        assi = hungarian(DM)[1]
        # sassi = Set(assi)

        # predict and filter too distant measurements
        for (bi, ass) in enumerate(assi)
            blob = active[bi]
            predict!(blob.kf,0)
            if ass == 0 || too_far(blob,coordinates[ass]) # penalize not found
                blob.counter += 1
                assi[bi] = 0
                continue
            end
        end

        # update active blobs with measurements
        for (bi, ass) in enumerate(assi)
            ass != 0 && update!(active[bi].kf,0,SVector(coordinates[ass].I))
        end

        # add new blobs
        newcoordinds = setdiff(1:length(coordinates), assi)
        newblobs = map(initblob, coordinates[newcoordinds])
        append!(active, newblobs)

        showblobs(img,active,coordinates,newcoordinds, assi, rad=6, recorder=recorder, display=display)

        # remove dead blobs
        bi = 1
        while bi <= length(active)
            if active[bi].counter > KILL_COUNTER_TH
                push!(dead, active[bi])
                deleteat!(active, bi)
            else
                bi += 1
            end
        end

    end
    if recorder  !== nothing
        println("Done")
        r = recorder
        finishencode!(r.encoder, r.saveio)
        close(r.saveio)
        mux("temp.stream",r.filename,r.framerate)
    end
    active, dead
end



end # module
