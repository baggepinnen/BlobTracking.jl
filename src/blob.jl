"""
A trace is a Vector{CartesianIndex{2}} and additionally supports `draw!, Matrix`.
"""
const Trace = Vector{CartesianIndex{2}}

"""
    Blob

Represents a blob. Internally stores a Kalman filter, a counter that is incremented when the blob is not assigned a measurement and a trace of all locations and all seen measurements. If no measurement was seen for a particular time step, `OOB = CartesianIndex(0,0)` is recorded.

This type supports `location, trace, tracem, lifetime, draw!`
"""
Base.@kwdef mutable struct Blob
    kf
    counter::Int = 0
    trace::Trace = CartesianIndex{2}[]
    tracem::Trace = CartesianIndex{2}[]
end

Base.Broadcast.broadcastable(b::Blob) = Ref(b)

Blob() = Blob(KalmanParams(1,1), CartesianIndex(1,1))

"""
    trace(b::Blob)

Get the location trace of a blob. Use `tm = Matrix(t::Trace)` to get an N×2 matrix. Use `tm = replace(Float64.(tm), 0=>NaN)` to create a matrix with NaNs where there were missing measurements, this is useful for plotting since it creates a gap where the missing measurement was.
"""
trace(b::Blob) = b.trace

"""
    tracem(b::Blob)

Get the measurement trace of a blob. Use `skipmissing(t::Trace)` to filter out missing measurements. Use `tm = Matrix(t::Trace)` to get an N×2 matrix. Use `tm = replace(Float64.(tm), 0=>NaN)` to create a matrix with NaNs where there were missing measurements, this is useful for plotting since it creates a gap where the missing measurement was.
"""
tracem(b::Blob) = b.tracem
Base.skipmissing(trace::Trace) = filter(!=(OOB), trace)
Base.Matrix(trace::Trace) = [getindex.(trace,1) getindex.(trace,2)]



struct KalmanParams
    σw::Float64
    σe::Float64
end

Base.Broadcast.broadcastable(b::KalmanParams) = Ref(b)

"""
    BlobTracker{T <: AbstractCorrespondence}

Example `bt = BlobTracker(sizes=3:5, σw=2.0, σe = 10.0)`

# Optional Keyword arguments:
- `params::KalmanParams`: Holds the parameters for the kalman filter `σw,σe`
- `amplitude_th = 0.0001`: blobs must be at least this prominent to be considered
- `kill_counter_th::Int = 10`: after this many steps without an assigned measurement a blob will die
- `sizes::AbstractVector`: vector of numbers determining the size scales at which blobs are detected. See docs for [`Images.blob_LoG`](@ref).
- `preprocessor = ((storage, img)->nothing` a function that processes `img` and stores the result in `storage`
- `correspondence::AbstractCorrespondence = HungarianCorrespondence(p=1.0, dist_th=2)`: Determines how blobs are assigned to measurements
- `mask = nothing`: An optional boolean image that is false where you want to ignore blobs and true where you want to track them.
"""
Base.@kwdef mutable struct BlobTracker{T<:AbstractCorrespondence}
    params::KalmanParams
    amplitude_th = 0.0001
    kill_counter_th::Int = 10
    sizes::AbstractVector
    preprocessor = (storage,img)-> (storage .= Gray.(img))
    correspondence::T = HungarianCorrespondence(p=1.0, dist_th=2)
    mask = nothing
end

"""
    BlobTracker(sizes, σw, σe; kwargs...)

Helper constructor that accepts keyword arguments for the `KalmanParams`

#Arguments:
- `σw`: Dynamics standard deviation
- `σe`: Measurement standard deviation
"""
function BlobTracker(sizes, σw, σe; kwargs...)
    BlobTracker(;sizes = sizes, params = KalmanParams(σw, σe), kwargs...)
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

Re(params::KalmanParams) = Re(params.σe)
Rw(params::KalmanParams) = Rw(params.σw)


"""
    Blob(params::KalmanParams, coord::CartesianIndex)

Spawn a blob using settings from `params` at given coordinates.
"""
function Blob(params::KalmanParams,coord::CartesianIndex)
    kf = KalmanFilter(A,B,C,0,Rw(params),Re(params),MvNormal(10Rw(params)))
    kf.x[1] = coord[1]
    kf.x[2] = coord[2]
    Blob(kf=kf, trace=[coord], tracem=[coord])
end

"""
    location(b)

Get the location of a blob as CartesianIndex
"""
Distributions.location(b::Blob) = CartesianIndex(round.(Int,(b.kf.x[1], b.kf.x[2])))
Distributions.location(b) = b.location
Distributions.location(b::Tuple) = CartesianIndex(b)
lifetime(b) = findlast(c->c != OOB, b.tracem)


Base.CartesianIndex(blob::Blob) = CartesianIndex((round.(Int,blob.kf.x[1:2])...,))


function detect_blobs!(ws::Workspace, bt::BlobTracker, img)
    blobs = blob_LoG!(ws.blob_storage,ws.storage,bt.sizes)
    blobs = filter!(x->x.amplitude > bt.amplitude_th, blobs)
    [b.location for b in blobs]
end

"""
    tune_sizes!(ws::Workspace, bt::BlobTracker, img)

Display a small GUI with a slider to help you tune the `sizes`
"""
function tune_sizes!(ws::Workspace, bt::BlobTracker, img)
    prepare_image!(ws, bt, img)
    @manipulate for k = 1:100
        imadjustintensity(imfilter(ws.storage, Kernel.LoG(k)))
    end
end

function prepare_image!(ws::Workspace, bt::BlobTracker, img)
    apply_mask!(ws,bt,img)
    bt.preprocessor(ws.storage, img)
end

function apply_mask!(ws::Workspace,bt::BlobTracker,img)
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
