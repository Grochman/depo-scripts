#!/bin/bash

# Define models
MODELS=("resnet152" "vgg16" "hf_Bert")

WORKLOADS_FILE="workloads_list.txt"

echo "Generating 27 unique workloads (sequences of 3 models)..."

# Overwrite previous file
> "$WORKLOADS_FILE"

# Generates 3x3x3 permutations
count=1
for m1 in "${MODELS[@]}"; do
    for m2 in "${MODELS[@]}"; do
        for m3 in "${MODELS[@]}"; do
            echo "wl_${count},${m1},${m2},${m3}" >> "$WORKLOADS_FILE"
            ((count++))
        done
    done
done

echo "Successfully generated $((count - 1)) workloads into $WORKLOADS_FILE"
