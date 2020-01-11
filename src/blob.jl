const Trace = Vector{CartesianIndex{2}}

Base.@kwdef mutable struct Blob
    kf
    counter::Int = 0
    trace::Trace = CartesianIndex{2}[]
end

Base.Broadcast.broadcastable(b::Blob) = Ref(b)

trace(b::Blob) = b.trace
Base.skipmissing(trace::Trace) = filter(!=(OOB), trace)


Base.@kwdef mutable struct TrackingResult
    blobs::Vector{Blob} = Blob[]
    dead::Vector{Blob} = Blob[]
end

allblobs(tr) = [tr.dead; tr.blobs]

function trace(tr::TrackingResult; minlife=0)
    blobs = allblobs(tr)
    filter!(b->lifetime(b)>=minlife, blobs)
    trace.(blobs)
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

Re(σe) = diagm([σe^2, σe^2])
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
lifetime(b) = findlast(c->c != OOB, b.trace)


Base.CartesianIndex(blob::Blob) = CartesianIndex((round.(Int,blob.kf.x[1:2])...,))

function dist(bt::BlobTracker, blob, c)
    k = blob.kf
    d = Mahalanobis(inv(k.C*covariance(k)*k.C'))
    v1 = SVector(c.I)
    v2 = SVector(k.x[1], k.x[2])
    d(v1,v2)
    # sqrt((c[1]-blob.kf.x[1])^2 + (c[2]-blob.kf.x[2])^2)
end

too_far(bt,blob,coord) = dist(bt, blob, coord) > bt.dist_th



function detect_blobs!(ws, bt::BlobTracker, img)
    blobs = blob_LoG!(ws.blob_storage,ws.storage,bt.sizes)
    blobs = filter!(x->x.amplitude > bt.amplitude_th, blobs)
    [b.location for b in blobs]
end

function tune_sizes!(ws, bt::BlobTracker, img)
    prepare_image!(ws, bt, img)
    @manipulate for k = 1:100
        imadjustintensity(imfilter(ws.storage, Kernel.LoG(k)))
    end
end

function prepare_image!(ws, bt, img)
    apply_mask!(ws,bt,img)
    bt.preprocessor(ws.storage, img)
end

function apply_mask!(ws,bt,img)
    bt.mask === nothing && return img
    return ws.storage .= bt.mask .* img
end

for f in (:detect_blobs, :tune_sizes, :prepare_image, :apply_mask)
    fb = Symbol(f, :!)
    @eval $f(bt::BlobTracker, img) = $fb(Workspace(img,bt), bt, img)
end



function blob_LoG!(img_LoG,img::AbstractArray{T,N}, σscales::Union{AbstractVector,Tuple},
    edges::Tuple{Vararg{Bool}}=(ntuple(d->false, Val(N))..., true), σshape=ntuple(d->1, Val(N))) where {T,N}
    sigmas = sort(σscales)
    colons = ntuple(d->Colon(), Val(N))
    @inbounds for isigma in eachindex(sigmas)
        img_LoG[colons...,isigma] .= (-sigmas[isigma]) .* imfilter!(@view(img_LoG[colons...,isigma]), img, Kernel.LoG(ntuple(i->sigmas[isigma]*σshape[i],Val(N))))
    end
    maxima = Images.findlocalmaxima(img_LoG, 1:ndims(img_LoG), edges)
    [Images.BlobLoG(CartesianIndex(rtailr(x.I)), sigmas[x[ndims(img_LoG)]], img_LoG[x]) for x in maxima]
end

@inline rtailr(x) = reverse(Base.tail(reverse(x)))

# function blob_LoG!(img_LoG,img::AbstractArray{T,N}, σscales::Union{AbstractVector,Tuple},
#     edges::Tuple{Vararg{Bool}}=(true, ntuple(d->false, Val(N))...), σshape=ntuple(d->1, Val(N))) where {T,N}
#     sigmas = sort(σscales)
#     colons = ntuple(d->Colon(), Val(N))
#     @inbounds for isigma in eachindex(sigmas)
#         img_LoG[isigma,colons...] = (-sigmas[isigma]) * imfilter(img, Kernel.LoG(ntuple(i->sigmas[isigma]*σshape[i],Val(N))))
#     end
#     maxima = Images.findlocalmaxima(img_LoG, 1:ndims(img_LoG), edges)
#     [Images.BlobLoG(CartesianIndex(Base.tail(x.I)), sigmas[x[1]], img_LoG[x]) for x in maxima]
# end
