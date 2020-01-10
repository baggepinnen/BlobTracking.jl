Base.@kwdef mutable struct Blob
    kf
    counter::Int = 0
    trace::Vector{CartesianIndex{2}} = CartesianIndex{2}[]
end

Base.Broadcast.broadcastable(b::Blob) = Ref(b)

Base.@kwdef mutable struct TrackingResult
    blobs::Vector{Blob} = Blob[]
    dead::Vector{Blob} = Blob[]
end


Base.@kwdef mutable struct BlobTracker
    σw = 15.0
    σe = 5.0
    dist_th = 20
    amplitude_th = 0.0001
    kill_counter_th::Int = 10
    sizes
    preprocessor = threshold(0.35)
    distance::Type{<:PreMetric} = Mahalanobis
    mask = nothing
end

Base.Broadcast.broadcastable(b::BlobTracker) = Ref(b)



dt = 1
A = @SMatrix [1. 0 dt 0; 0 1 0 dt; 0 0 1 0; 0 0 0 1] #state update matrice
B = @SVector [(dt^2/2), (dt^2/2), dt, dt]
C = @SMatrix [1. 0 0 0; 0 1 0 0]

Re(σe) = diagm([σe, σe])
Rw(σw) =  [dt^4/4 0 dt^3/2 0;
    0 dt^4/4 0 dt^3/2;
    dt^3/2 0 dt^2 0;
    0 dt^3/2 0 dt^2].*σw^2 + 1e-6I

Re(bt::BlobTracker) = Re(bt.σe)
Rw(bt::BlobTracker) = Rw(bt.σw)



function Blob(bt::BlobTracker,coord::CartesianIndex)
    kf = KalmanFilter(A,B,C,0,Rw(bt),Re(bt),MvNormal(10Rw(bt)))
    kf.x[1] = coord[1]
    kf.x[2] = coord[2]
    Blob(kf=kf, trace=[coord])
end

Distributions.location(b::Blob) = CartesianIndex(round.(Int,(b.kf.x[1], b.kf.x[2])))
Distributions.location(b) = b.location
Distributions.location(b::Tuple) = CartesianIndex(b)

Base.CartesianIndex(blob::Blob) = CartesianIndex((round.(Int,blob.kf.x[1:2])...,))

function dist(bt::BlobTracker, blob, c)
    sqrt((c[1]-blob.kf.x[1])^2 + (c[2]-blob.kf.x[2])^2)
end

too_far(bt,blob,coord) = dist(bt, blob, coord) > bt.dist_th



function detect_blobs!(storage, bt::BlobTracker, img)
    prepare_image!(storage, bt, img)
    blobs = blob_LoG(storage,bt.sizes)
    blobs = filter!(x->x.amplitude > bt.amplitude_th, blobs)
    [b.location for b in blobs]
end

function tune_sizes!(storage, bt::BlobTracker, img)
    prepare_image!(storage, bt, img)
    @manipulate for k = 1:100
        imadjustintensity(imfilter(storage, Kernel.LoG(k)))
    end
end

function prepare_image!(storage, bt, img)
    apply_mask!(storage,bt,img)
    bt.preprocessor(storage, img)
end

function apply_mask!(storage,bt,img)
    bt.mask === nothing && return img
    return storage .= bt.mask .* img
end

for f in (:detect_blobs, :tune_sizes, :prepare_image, :apply_mask)
    fb = Symbol(f, :!)
    @eval $f(bt::BlobTracker, img) = $fb(Gray.(img), bt, img)
end
