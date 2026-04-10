#!/bin/bash

# Define models
MODELS=("resnet152" "vgg16" "hf_Bert")

# Environment variables output file
CONFIG_FILE="config.env"

echo "Starting manual calibration for parameters --bs (batch size) and --it (iterations)."
echo "Target: benchmark execution time should be exactly 80 seconds."

# Initialize configuration file
echo "# Generated calibration parameters (target execution time: 80s)" > $CONFIG_FILE

for MODEL in "${MODELS[@]}"; do
    echo "============================================="
    echo "Calibration for model: $MODEL"
    echo "============================================="
    
    # Placeholder for actual parameter discovery mechanism
    echo "Please provide testing parameters for this model."
    
    read -p "Enter Batch Size (--bs) for ${MODEL} [Default: 16]: " bs_val
    read -p "Enter Iterations (--it) for ${MODEL} [Default: 1]: " it_val
    
    # Handle empty/default values
    bs_val=${bs_val:-16}
    it_val=${it_val:-1}

    # Convert model name to format suitable for environment variable suffix
    ENV_PREFIX=$(echo "$MODEL" | tr '[:lower:]' '[:upper:]')
    
    echo "${ENV_PREFIX}_BS=$bs_val" >> $CONFIG_FILE
    echo "${ENV_PREFIX}_IT=$it_val" >> $CONFIG_FILE
    
    echo "Saved $ENV_PREFIX values to $CONFIG_FILE"
    echo ""
done

echo "Configuration file $CONFIG_FILE generated successfully!"
echo "Contents:"
cat $CONFIG_FILE
