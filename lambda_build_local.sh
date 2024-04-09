#!/bin/bash

# Set common variables
goArch='amd64'
goOs='linux'
outputBinary='main'

# Build and zip for replay_duration_lambda_pkg
sourceDir1='replay_duration_lambda_pkg'
zipFile1='package.zip'

cd "$sourceDir1"
go mod tidy
env GOARCH=$goArch GOOS=$goOs go build -o $outputBinary
zip $zipFile1 $outputBinary
cd -

# Build and zip for connector_status_lambda_pkg
sourceDir2='connector_status_lambda_pkg'
zipFile2='connector_package.zip'

cd "$sourceDir2"
go mod tidy
env GOARCH=$goArch GOOS=$goOs go build -o $outputBinary
zip $zipFile2 $outputBinary
cd -