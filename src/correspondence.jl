

"""
    assign(c::AbstractCorrespondence, blobs, coordinates)

Assign measurements to blobs using the `AbstractCorrespondence`

#Arguments:
- `blobs`: A vector of blobs
- `coordinates`: A vector of CartesianIndex
"""
assign


function assign(c::HungarianCorrespondence, blobs, coordinates)
    isempty(blobs) && (return Int[])
    isempty(coordinates) && (return zeros(Int, length(blobs)))
    p = c.p
    DM = [dist(b,c)^p for b in blobs, c in coordinates]
    # DM[DM .> bt.dist_th] .= 100000
    assi = hungarian((DM))[1]
end

function assign(c::NearestNeighborCorrespondence, blobs, coordinates)
    isempty(blobs) && (return Int[])
    isempty(coordinates) && (return zeros(Int, length(blobs)))
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
    assi
end
