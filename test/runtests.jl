# using Pkg
# pkg"activate /home/fredrikb/.julia/dev/BlobTracking/"
using BlobTracking
using Test, Statistics, ImageDraw, Images, VideoIO, StaticArrays
img = Gray.(zeros(100,100))
locs = [CartesianIndex(10,10), CartesianIndex(30,30)]
draw!(img,locs[1], c=Gray(1.0))
draw!(img,locs[2], c=Gray(1.0))

img2 = Gray.(zeros(100,100))
locs2 = [CartesianIndex(15,15), CartesianIndex(35,35)]
draw!(img2,locs2[1], c=Gray(1.0))
draw!(img2,locs2[2], c=Gray(1.0))

img3 = Gray.(zeros(100,100))
locs3 = [CartesianIndex(20,20), CartesianIndex(40,40)]
draw!(img3,locs3[1], c=Gray(1.0))
draw!(img3,locs3[2], c=Gray(1.0))


##
@testset "BlobTracking.jl" begin


    @testset "to_static" begin
        @info "Testing to_static"
        @test to_static(1) == 1
        @test to_static(randn(2,2)) isa SMatrix{2,2}
        @test to_static(randn(2)) isa SVector{2}

    end

    @testset "Blob" begin
        @info "Testing Blob"
        b = Blob()
        blobs = [b]
        corr = HungarianCorrespondence(dist_th = 2)
        measurement = BlobTracking.assign(corr, blobs, locs)
        BlobTracking.correct!(blobs, measurement)
        pos1 = to_static(location(b))
        @test all(to_static(location(b)) .> 0)
        @test all(to_static(location(b)) .< to_static(locs[1]))


        b = Blob()
        blobs = [b]
        corr = MCCorrespondence(HungarianCorrespondence(dist_th = 2), 20)
        measurement = BlobTracking.assign(corr, blobs, locs)
        BlobTracking.correct!(blobs, measurement)
        pos2 = to_static(location(b))
        @test pos1 == pos2

    end

    @testset "Correspondence" begin
        @info "Testing Correspondence"

        @testset "NearestNeighborCorrespondence" begin
            @info "Testing NearestNeighborCorrespondence"
            bt = BlobTracker(2:2, 10, 5.0)
            coordinates = locs
            blobs = Blob.(bt.params, coordinates)
            c = NearestNeighborCorrespondence(dist_th = 2)

            meas = BlobTracking.assign(c, blobs, coordinates)
            @test meas.assi == [1,2]

            meas = BlobTracking.assign(c, blobs, [CartesianIndex(1000,1000); coordinates])
            @test meas.assi == [2,3]

            meas = BlobTracking.assign(c, [blobs; blobs], coordinates)
            @test meas.assi == [1,2,1,2]

        end


        @testset "HungarianCorrespondence" begin
            @info "Testing HungarianCorrespondence"
            bt = BlobTracker(2:2, 10, 5.0)
            coordinates = locs
            blobs = Blob.(bt.params, coordinates)
            c = HungarianCorrespondence(dist_th = 2)

            meas = BlobTracking.assign(c, blobs, coordinates)
            @test meas.assi == [1,2]

            meas = BlobTracking.assign(c, blobs, [CartesianIndex(1000,1000); coordinates])
            @test meas.assi == [2,3]

            meas = BlobTracking.assign(c, [blobs; blobs], coordinates)
            @test meas.assi == [1,2,0,0]

        end

        @testset "MCCorrespondence" begin
            @info "Testing MCCorrespondence"
            bt = BlobTracker(2:2, 10, 5.0)
            coordinates = locs
            blobs = Blob.(bt.params, coordinates)
            c = MCCorrespondence()

            meas = BlobTracking.assign(c, blobs, coordinates)
            @test median(meas[i].assi[1] for i in eachindex(meas)) == 1
            @test median(meas[i].assi[2] for i in eachindex(meas)) == 2

            meas = BlobTracking.assign(c, blobs, [CartesianIndex(1000,1000); coordinates])
            @test median(meas[i].assi[1] for i in eachindex(meas)) == 2
            @test median(meas[i].assi[2] for i in eachindex(meas)) == 3

            meas = BlobTracking.assign(c, [blobs; blobs], coordinates)
            @test median(meas[i].assi[1] for i in eachindex(meas)) <= 1
            @test median(meas[i].assi[2] for i in eachindex(meas)) <= 2

        end

    end



    @testset "FrameBuffer" begin
        @info "Testing FrameBuffer"
        b = FrameBuffer{Float64}(2,2,2)
        @test length(b) == 0
        @test !isready(b)
        @test_throws BoundsError b[1]
        @test_throws BoundsError b[1,1,1]
        b1 = randn(2,2)
        push!(b, b1)
        @test length(b) == 1
        @test isready(b)
        @test b[1] == b1
        @test b[1,1,1] == b1[1,1]
        @test length(collect(b)) == 1
        for f in (median, mean, sum)
            @test f(b) == f(b.b[:,:,1:1], dims=3)[:,:,1]
        end

        push!(b, randn(2,2))

        for f in (median, mean, sum, std, var)
            @test f(b) == f(b.b[:,:,1:2], dims=3)[:,:,1]
        end
        @test b[1] == b1
        @test size(Matrix(b)) == (4,2)
        @test length(b) == 2
        @test length(collect(b)) == 2
        @test BlobTracking.imgsize(b) == (2,2)

        db = diff(b)
        @test length(db) == 1
        @test db.b == diff(b.b, dims=3)

    end

    @testset "Background extraction" begin
        @info "Testing Background extraction"
        @testset "MedianBackground" begin
            @info "Testing MedianBackground"
            be = MedianBackground(img,3)
            update!(be, img2)
            update!(be, img3)
            @test BlobTracking.background(be, img) == 0 .* img
            @test BlobTracking.foreground(be, img) == img
        end

        @testset "DiffBackground" begin
            @info "Testing DiffBackground"
            be = DiffBackground(img)
            update!(be, img2)
            @test imadjustintensity(BlobTracking.background(be, img)) == complement.(img)
            @test imadjustintensity(BlobTracking.foreground(be, img)) == img
        end
    end


    @testset "Tracking" begin
        @info "Testing Tracking"
        bt = BlobTracker(2:2, 10, 5.0)
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
        @test tracem(result.blobs[1])[1] == locs[1]
        @test tracem(result.blobs[2])[1] == locs[2]

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

        @testset "Coordinate iterator" begin
            @info "Testing Coordinate iterator"
            bt = BlobTracker(2:2, 10, 5.0)
            coords = BlobTracking.get_coordinates(bt, [img,img2,img,img2], threads=true)
            @test length(coords) == 4
            @test coords == [locs,locs2,locs,locs2]

            coords = BlobTracking.get_coordinates(bt, [img,img2,img,img2], threads=false)
            @test length(coords) == 4
        end

        @testset "track_blobs" begin
            @info "Testing track_blobs"
            bt = BlobTracker(2:2, 10, 5.0)
            result = track_blobs(bt,[img,img2])

            @test result.blobs[1].tracem[1] == locs[1]
            @test result.blobs[2].tracem[1] == locs[2]
            @test result.blobs[1].tracem[2] == locs2[1]
            @test result.blobs[2].tracem[2] == locs2[2]

            result = track_blobs(bt,[img,img2], threads=false)

            @test result.blobs[1].tracem[1] == locs[1]
            @test result.blobs[2].tracem[1] == locs[2]
            @test result.blobs[1].tracem[2] == locs2[1]
            @test result.blobs[2].tracem[2] == locs2[2]

            bt = BlobTracker(2:2, 10, 5.0, correspondence=MCCorrespondence())
            result = track_blobs(bt,[img,img2])

            @test result.blobs[1].tracem[1] == locs[1]
            @test result.blobs[2].tracem[1] == locs[2]
            @test result.blobs[1].tracem[2] == locs2[1]
            @test result.blobs[2].tracem[2] == locs2[2]

            # @test tracem.(allblobs(result))

            @test location(result) == [locs, locs2]


            bt = BlobTracker(2:2, 10, 5.0)
            coords = BlobTracking.get_coordinates(bt, [img,img2,img,img2], threads=true)
            result = track_blobs(bt,coords)

            @test result.blobs[1].tracem[1] == locs[1]
            @test result.blobs[2].tracem[1] == locs[2]
            @test result.blobs[1].tracem[2] == locs2[1]
            @test result.blobs[2].tracem[2] == locs2[2]
        end
    end
    @testset "display" begin
        @info "Testing display"
        bt = BlobTracker(2:2, 10, 5.0)
        recorder = Recorder()
        result = track_blobs(bt,[N0f8.(Gray.(img)),N0f8.(Gray.(img2)),N0f8.(Gray.(img)),N0f8.(Gray.(img2)),N0f8.(Gray.(img)),N0f8.(Gray.(img2)),N0f8.(Gray.(img)),N0f8.(Gray.(img2)),N0f8.(Gray.(img)),N0f8.(Gray.(img2))], display=img->println("displaying image"), recorder=recorder)
        traces =  trace(result, minlife=2)
        tracems =  tracem(result, minlife=2)

        drawimg = RGB.(img)
        draw!(drawimg, traces, c=RGB(0,0,0.5))
        draw!(drawimg, tracems, c=RGB(0.5,0,0))
        @test isfile(recorder.filename)
        io = VideoIO.open(recorder.filename)
        vid = VideoIO.openvideo(io)
        frame1 = first(vid)
        @test size(frame1) == size(img)

        if isfile(recorder.filename)
            rm(recorder.filename)
        end

        @testset "tune_sizes" begin
            @info "Testing tune_sizes"
            bt = BlobTracker(2:2, 10, 5.0)
            tune_sizes(bt,img)

        end
    end
end
