# abstract type BackgroundExtractor end
#
# background(be::BackgroundExtractor, img; normalize=false) = imadjustintensity(background(be, img))
# foreground(be::BackgroundExtractor, img; normalize=false) = imadjustintensity(foreground(be, img))
#
# LowLevelParticleFilters.update!(be::BackgroundExtractor, img) = push!(be.fb, img)
#
# struct MedianBackground{T} <: BackgroundExtractor
#     fb::FrameBuffer{T}
# end
# MedianBackground(args...) = MedianBackground(FrameBuffer(args...))
#
# function background(be::MedianBackground, img)
#     median(be.fb)
# end
#
# function foreground(be::MedianBackground, img)
#     img - background(be, img)
# end
#
#
#
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
