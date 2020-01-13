abstract type BackgroundExtractor end

"""
    update!(be::BackgroundExtractor, img)

Update a background model using `img`.
"""
LowLevelParticleFilters.update!(be::BackgroundExtractor, img) = push!(be.fb, img)

"""
    MedianBackground{T} <: BackgroundExtractor

Models the background of a sequence of images as the median over a fixed time window. Supports the same constructors as a `FrameBuffer`

This type supports `background, foreground, update!`
"""
struct MedianBackground{T} <: BackgroundExtractor
    fb::FrameBuffer{T}
end
MedianBackground(args...) = MedianBackground(FrameBuffer(args...))


"""
    background(be::MedianBackground)

Extract the background of `img`.
"""
function background(be::MedianBackground, img=nothing)
    median(be.fb)
end

"""
    foreground(be::MedianBackground, img)

Extract the foreground of `img`.
"""
function foreground(be::MedianBackground, img)
    img - background(be, img)
end






"""
    DiffBackground{T} <: BackgroundExtractor

Models the background of a sequence of images as the diff between two consequtive images.

This type supports `background, foreground, update!`
"""
struct DiffBackground{T} <: BackgroundExtractor
    fb::FrameBuffer{T}
end
DiffBackground(img) = DiffBackground(FrameBuffer(img, 2))


"""
    background(be::DiffBackground, img)

Extract the background of `img`.
"""
function background(be::DiffBackground, img)
    dropdims(diff(be.fb).b, dims=3) .* img
end

"""
    foreground(be::DiffBackground, img)

Extract the foreground of `img`.
"""
function foreground(be::DiffBackground, img)
    dropdims(complement.(diff(be.fb).b), dims=3) .* img
end



# struct PCABackground{T} <: BackgroundExtractor
#     k::Int
#     fb::FrameBuffer{T}
# end
# PCABackground(k::Int, args...) = PCABackground(k, FrameBuffer(args...))
#
# function background(be::PCABackground, img)
#     pca = fit(PCA, Matrix(be.fb)'; maxoutdim=be.k)
#     r = reconstruct(pca, vec(img))
#     reshape(r, imgsize(be.fb))
# end
#
# function foreground(be::PCABackground, img)
#     img - background(be, img)
# end
