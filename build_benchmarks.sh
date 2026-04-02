#!/bin/bash
set -e # Exit on error

mkdir -p ~/repos
cd ~/repos/

if [ ! -d "torchbench-caise" ]; then
    git clone https://kask.eti.pg.gda.pl/gitlab/grzkoszc/torchbench-caise.git
fi

# THIS IS THE MISSING STEP:
cd torchbench-caise

docker build \
    --build-arg MODELS="resnet152 vgg16 hf_Bert" \
    --tag torchbench-suite:1.0.1 \
    --file ./docker/torchbench-caise.dockerfile . \
    2>&1 | tee docker-build.log