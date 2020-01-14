"""
    abstract type AbstractCorrespondence

Method for determining the correspondence matching between blobs and measurements.

Supports functions `assign(c::AbstractCorrespondence, blobs, coordinates)`, `too_far(c::AbstractCorrespondence, blob, coordinate)`

# Subtypes
- `HungarianCorrespondence`
- `NearestNeighborCorrespondence`
"""
abstract type AbstractCorrespondence end

"""
    HungarianCorrespondence <: AbstractCorrespondence

Use the Hungarian algorithm to assign measuements to blobs. Each measurement is assigned to one blob only.
Parameter `p > 0` influences how eager the assignement is on a spectrum between `p ≈ 0` corresponding to nearest neighbor matching, `p = 1` corresponding to minimizing the earth-movers distance, `p → ∞` corresponding to minimizing the maximum error. The default is `p = 1`.

# Parameters
- `p=1`: the exponent of the cost matrix
- `dist_th=2`: maximum allowed Mahalanobis distance between a blob and a measurement
"""
Base.@kwdef struct HungarianCorrespondence <: AbstractCorrespondence
    p::Float64 = 1
    dist_th::Float64 = 2
end

"""
    NearestNeighborCorrespondence <: AbstractCorrespondence

Assign each blob the measurement that appears closest to the blob. This method can assign the same measurement to multiple blobs.

# Parameters
- `dist_th=2`: maximum allowed Mahalanobis distance between a blob and a measurement
"""
Base.@kwdef struct NearestNeighborCorrespondence <: AbstractCorrespondence
    dist_th::Float64 = 2
end
