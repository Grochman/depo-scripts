#!/bin/bash

# Define the models you want to run
MODELS=("resnet152" "vgg16" "hf_Bert")

cd ~/repos/torchbench-caise

echo "Starting TorchBench suite for 3 models..."

for MODEL in "${MODELS[@]}"
do
   echo "=========================================="
   echo "STARTING BENCHMARK: $MODEL"
   echo "=========================================="

   docker run --name "torchbench_$MODEL" \
       --rm \
       --entrypoint "/bin/bash" \
       --ipc host \
       --gpus all \
       torchbench-suite:1.0.1 \
       -c "python3 run.py $MODEL -d=cuda -t=train --bs=16 --it=1 --precision=fp32"

   echo "DONE: $MODEL"
   echo ""
done

echo "All scheduled benchmarks are complete."
