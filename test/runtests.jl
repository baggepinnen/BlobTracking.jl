# using Pkg
# pkg"activate /home/fredrikb/.julia/dev/BlobTracking/"
using BlobTracking
using Test, Statistics, ImageDraw, Images

@testset "BlobTracking.jl" begin

    img = Gray.(zeros(100,100))
    locs = [CartesianIndex(10,10), CartesianIndex(30,30)]
    draw!(img,locs[1], c=Gray(1.0))
    draw!(img,locs[2], c=Gray(1.0))

    img2 = Gray.(zeros(100,100))
    locs2 = [CartesianIndex(12,12), CartesianIndex(32,32)]
    draw!(img2,locs2[1], c=Gray(1.0))
    draw!(img2,locs2[2], c=Gray(1.0))

    @testset "FrameBuffer" begin
        @info "Testing FrameBuffer"
        b = FrameBuffer{Float64}(2,2,2)
        push!(b, randn(2,2))
        push!(b, randn(2,2))

        for f in (median, mean, sum, std, var)
            @test f(b) == f(b.b[:,:,1:2], dims=3)[:,:,1]
        end

    end

    @testset "Background extraction" begin
        @info "Testing Background extraction"

        @testset "MedianBackground" begin
            @info "Testing MedianBackground"

            be = MedianBackground(randn(2,2),2)

        end

    end


    @testset "Tracking" begin
        @info "Testing Tracking"
        bt = BlobTracker(sizes=2:2)
        result = TrackingResult()
        ws = BlobTracking.Workspace(img, bt)
        BlobTracking.prepare_image!(ws,bt,img)
        measurement = BlobTracking.Measurement(ws, bt, img, result)
        @test measurement.assi == Int[]
        @test measurement.coordinates == locs
        @test isempty(result.blobs)
        BlobTracking.spawn_blobs!(result, bt, measurement)
        @test length(result.blobs) == 2
        @test isempty(result.dead)
        @test location.(result.blobs) == locs
        @test result.blobs[1].tracem[1] == locs[1]
        @test result.blobs[2].tracem[1] == locs[2]

        blobs = result.blobs
        BlobTracking.prepare_image!(ws,bt,img2)
        measurement = BlobTracking.Measurement(ws, bt, img2, result)
        @test measurement.coordinates == locs2
        @test measurement.assi == 1:2
        BlobTracking.predict!(result)
        @test location.(blobs) == locs
        filter!(result, bt, measurement)
        @test length(measurement.coordinates) == 2
        @test measurement.assi == 1:2
        BlobTracking.correct!(result, measurement)
        @test location.(blobs) == locs2

        @test result.blobs[1].tracem[2] == locs2[1]
        @test result.blobs[2].tracem[2] == locs2[2]

        @test all(>(0), blobs[1].kf.x[3:4]) # Positive velocities
        @test all(>(0), blobs[2].kf.x[3:4])

        @test blobs[1].counter == 0
        @test blobs[2].counter == 0

        measurement = BlobTracking.Measurement(ws, bt, 0*img2, result)
        @test isempty(measurement.coordinates)
        @test all(iszero, measurement.assi)
        filter!(result, bt, measurement)
        @test isempty(measurement.coordinates)
        @test all(iszero, measurement.assi)
        BlobTracking.correct!(result, measurement)
        @test location.(blobs) == locs2

        @test result.blobs[1].tracem[3] == OOB
        @test result.blobs[2].tracem[3] == OOB

        @testset "track_blobs" begin
            @info "Testing track_blobs"
            bt = BlobTracker(sizes=2:2)
            result = track_blobs(bt,[img,img2])

            @test result.blobs[1].tracem[1] == locs[1]
            @test result.blobs[2].tracem[1] == locs[2]
            @test result.blobs[1].tracem[2] == locs2[1]
            @test result.blobs[2].tracem[2] == locs2[2]
        end

    end
end
