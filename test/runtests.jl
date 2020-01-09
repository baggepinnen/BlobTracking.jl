using BlobTracking
using Test, Statistics

@testset "BlobTracking.jl" begin

    @testset "FrameBuffer" begin
        @info "Testing FrameBuffer"
        b = FrameBuffer{Float64}(2,2,2)
        push!(b, randn(2,2))

        for f in (median, mean, sum, std, var)
            @test f(b) == f(b.b, dims=3)
        end

    end

    @testset "Background extraction" begin
        @info "Testing Background extraction"

        @testset "MedianBackground" begin
            @info "Testing MedianBackground"

            be = MedianBackground(randn(2,2),2)

        end

    end
end
