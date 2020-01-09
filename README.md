# BlobTracking

[![Build Status](https://travis-ci.org/baggepinnen/BlobTracking.jl.svg?branch=master)](https://travis-ci.org/baggepinnen/BlobTracking.jl)
[![Codecov](https://codecov.io/gh/baggepinnen/BlobTracking.jl/branch/master/graph/badge.svg)](https://codecov.io/gh/baggepinnen/BlobTracking.jl)

*Work in progress*

Detect and track blobs (like birds or bugs) moving around in an image. Blobs are detected using simple [Laplacian-of-Gaussian filtering](https://en.wikipedia.org/wiki/Blob_detection) (from [Images.jl](https://juliaimages.org/latest/function_reference/#Images.blob_LoG)) and tracked using a Kalman filter from [LowLevelParticleFilters.jl](https://github.com/baggepinnen/LowLevelParticleFilters.jl).

This package contains some facilities for the afromentioned detection and tracking, as well as some utilities for background removal etc.
