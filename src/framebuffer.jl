mutable struct FrameBuffer{T}
    b::Array{T,3}
    c::Int
    full::Bool
    function FrameBuffer(img::Matrix, n)
        new{eltype(img)}(similar(img, size(img)..., n), 0, false)
    end
    function FrameBuffer{T}(w::Int,h::Int,d::Int) where T
        new{T}(Array{T,3}(undef,w,h,d), 0, false)
    end
end


function Base.push!(b::FrameBuffer, img)
    b.c += 1
    if b.c > length(b)
        b.full = true
        b.c = 1
    end
    b.b[:,:,b.c] .= img
end

Base.@propagate_inbounds Base.getindex(b::FrameBuffer, i::Int) = @view b.b[:,:,i]

Base.@propagate_inbounds Base.getindex(b::FrameBuffer, i,j,k) = b.b[i,j,k]

Base.Matrix(b::FrameBuffer) = reshape(b.b, :, length(b))
Base.length(b::FrameBuffer) = size(b.b, 3)
imgsize(b::FrameBuffer) = (size(b.b,1),size(b.b,2))

Base.isready(b::FrameBuffer) = b.c > 0
function Base.iterate(b::FrameBuffer, state=1)
    state > length(b) && return nothing
    (b[state],state+1)
end



for f in (median, mean, sum, std, var, reshape, size)
    m = parentmodule(f)
    fs = nameof(f)
    @eval $m.$fs(b::FrameBuffer, args...) = $fs(b.b, args..., dims=3)
end
