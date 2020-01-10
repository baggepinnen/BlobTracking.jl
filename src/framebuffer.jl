mutable struct FrameBuffer{T}
    b::Array{T,3}
    c::Int
    full::Bool
    function FrameBuffer(img::Matrix, n)
        fb = new{eltype(img)}(similar(img, size(img)..., n), 0, false)
        push!(fb, img)
        fb
    end
    function FrameBuffer{T}(w::Int,h::Int,d::Int) where T
        new{T}(Array{T,3}(undef,w,h,d), 0, false)
    end
end

capacity(fb::FrameBuffer) = size(fb.b,3)

function Base.push!(b::FrameBuffer, img)
    b.c += 1
    if b.c > capacity(b)
        b.full = true
        b.c = 1
    end
    b.b[:,:,b.c] .= img
end

Base.@propagate_inbounds function Base.getindex(b::FrameBuffer, i::Int)
    Base.@boundscheck if !b.full && i > b.c
        throw(BoundsError(b,i))
    end
    @view b.b[:,:,i]
end

Base.@propagate_inbounds function  Base.getindex(b::FrameBuffer, i,j,k)
    Base.@boundscheck if !b.full && i > b.c
        throw(BoundsError(b,i))
    end
    b.b[i,j,k]
end

Base.Matrix(b::FrameBuffer) = reshape(b.b, :, length(b))
Base.length(b::FrameBuffer) = b.full ? size(b.b, 3) : b.c
imgsize(b::FrameBuffer) = (size(b.b,1),size(b.b,2))

Base.isready(b::FrameBuffer) = b.c > 0
function Base.iterate(b::FrameBuffer, state=1)
    b.full && state > length(b) && return nothing
    !b.full && state > b.c && return nothing
    (b[state],state+1)
end



for f in (median, mean, sum, std, var, reshape, size)
    m = parentmodule(f)
    fs = nameof(f)
    @eval function $m.$fs(b::FrameBuffer{T}, args...)::Matrix{T} where T
        if b.full
            return dropdims($fs(b.b, args..., dims=3), dims=3)
        else
            return dropdims($fs(@view(b.b[:,:,1:b.c]), args..., dims=3), dims=3)
        end
    end
end
