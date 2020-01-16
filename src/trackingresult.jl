"""
    TrackingResult

This type stores a vector of `blobs` that were active when tracking terminated, a vector `dead` of blobs that died during tracking and a vector of all measurements obtained during tracking. This type supports `allblobs, trace`
"""
TrackingResult

Base.@kwdef mutable struct TrackingResult
    blobs::Vector{Blob} = Blob[]
    dead::Vector{Blob} = Blob[]
    coordinates::Vector{Trace} = Trace[]
end

Base.isempty(result::TrackingResult) = isempty(result.blobs) && isempty(result.dead)

"""
    allblobs(tr)

Get all blobs in a tracking result
"""
allblobs(tr::TrackingResult) = [tr.dead; tr.blobs]

"""
    trace(tr::TrackingResult; minlife=0)

Get all traces in a tracking result. Optionally filter based on minimum lifetime of a blob (the blob must have seen this many measurements).
"""
function trace(tr::TrackingResult; minlife=0)
    blobs = allblobs(tr)
    filter!(b->lifetime(b)>=minlife, blobs)
    trace.(blobs)
end

function tracem(tr::TrackingResult; minlife=0)
    blobs = allblobs(tr)
    filter!(b->lifetime(b)>=minlife, blobs)
    tracem.(blobs)
end

log_measurement(result::TrackingResult, m::Measurement) = push!(result.coordinates, m.coordinates)
log_measurement(result::TrackingResult, ms::Vector{Measurement}) = push!(result.coordinates, ms[1].coordinates)
Distributions.location(result::TrackingResult) = result.coordinates
