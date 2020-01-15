"""
    dist(blob, c)

Measure the distance between a blob and a coordinate `c` using the Mahalanobis distance induced the the blobs measurement covariance
"""
function dist(blob::Blob, c)
    k = blob.kf
    d = Mahalanobis(inv(k.C*covariance(k)*k.C'))
    v1 = SVector(c.I)
    v2 = SVector(k.x[1], k.x[2])
    d(v1,v2)
    # sqrt((c[1]-blob.kf.x[1])^2 + (c[2]-blob.kf.x[2])^2)
end

function dist(sample, c)
    sqrt((c[1]-sample[1])^2 + (c[2]-sample[2])^2)
end

too_far(c::AbstractCorrespondence,blob,coord) = dist(blob, coord) > c.dist_th

"""
    measurement = assign(c::AbstractCorrespondence, blobs, coordinates)

Assign measurements to blobs using the `AbstractCorrespondence`. Returns `m::Measurement`

#Arguments:
- `blobs`: A vector of blobs
- `coordinates`: A vector of CartesianIndex
"""
assign


function assign(c::HungarianCorrespondence, blobs, coordinates)
    isempty(blobs) && (return Measurement(coordinates, Int[]))
    isempty(coordinates) && (return Measurement(coordinates, zeros(Int, length(blobs))))
    p = c.p
    DM = [dist(b,c)^p for b in blobs, c in coordinates]
    # DM[DM .> bt.dist_th] .= 100000
    assi = hungarian((DM))[1]
    measurement = Measurement(coordinates, assi)
end

function assign(c::NearestNeighborCorrespondence, blobs, coordinates)
    isempty(blobs) && (return Measurement(coordinates, Int[]))
    isempty(coordinates) && (return Measurement(coordinates, zeros(Int, length(blobs))))
    assi = zeros(Int, length(blobs))
    # kdtree = KDTree(Float32.(Matrix(location.(blobs))'))
    kdtree = KDTree(Float32.(Matrix(coordinates)'))
    for (bi,blob) in enumerate(blobs)
        I,d = knn(kdtree, to_static(location(blob)), 1)
        if d[] > c.dist_th
            continue
        end
        assi[bi] = I[]
    end
    measurement = Measurement(coordinates, assi)
end


function assign(c::MCCorrespondence, blobs, coordinates)
    isempty(blobs) && (return Measurement(coordinates, Int[]))
    isempty(coordinates) && (return Measurement(coordinates, zeros(Int, length(blobs))))
    measurements = map(1:c.num_samples) do i
        samples = sample_new_locations(blobs)
        measurement = assign(c.inner, samples, coordinates)
    end
end


function sample_new_locations(blobs)
    map(blobs) do blob
        d = MvNormal(blob.kf.x[1:2], covariance(blob.kf)[1:2,1:2])
        sample = rand(d)
    end
end
