Base.@kwdef mutable struct Blob
    kf
    counter::Int = 0
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
end

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
    Blob(kf,0)
end

Base.CartesianIndex(blob::Blob) = CartesianIndex((round.(Int,blob.kf.x[1:2])...,))

function dist(bt::BlobTracker, blob, c)
    sqrt((c[1]-blob.kf.x[1])^2 + (c[2]-blob.kf.x[2])^2)
end

too_far(blob,coord) = dist(blob, coord) > DIST_TH

detect_blobs(bt::BlobTracker, img;kwargs...) = detect_blobs!(Gray.(img), bt::BlobTracker, img)

function detect_blobs!(storage, bt::BlobTracker, img)
    bt.preprocessor(storage, img)
    blobs = blob_LoG(storage,sizes)
    blobs = filter!(x->x.amplitude > amplitude_th, blobs)
    [b.location for b in blobs]
end

function tune_sizes(bt::BlobTracker, img)
    storage = Gray.(img)
    bt.preprocessor(storage, img)
    @manipulate for k = 1:100
        imadjustintensity(imfilter(storage, Kernel.LoG(k)))
    end
end
