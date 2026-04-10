#!/bin/bash
# Input variables passed from main orchestration script
WINDOW=$1
INTERVAL=$2
W_ID=$3
MODEL1=$4
MODEL2=$5
MODEL3=$6

# Argument validation
if [ "$#" -ne 6 ]; then
    echo "Usage: $0 <window_ms> <interval_s> <w_id> <model1> <model2> <model3>"
    exit 1
fi

CONFIG_FILE="config.env"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Default environment configuration $CONFIG_FILE missing. Run 01_calibrate.sh first."
    exit 1
fi

source "$CONFIG_FILE"

echo "=========================================================="
echo " Executing Workload: $W_ID"
echo " Parameters: Window=${WINDOW}ms, Interval=${INTERVAL}s"
echo " Sequence: 1=${MODEL1}, 2=${MODEL2}, 3=${MODEL3}"
echo "=========================================================="

# ------------------------------------------------------------------
#  [1] START MEASUREMENT TOOL
# ------------------------------------------------------------------
echo "[$(date +'%H:%M:%S')] Starting background measurement tool..."
# Ensure you implement appropriate start semantics for the measurement tool here.
# Example: ./measurement_tool --window $WINDOW --interval $INTERVAL > logs_${W_ID}.txt 2>&1 &
# PID_TOOL=$!

# Helper function executing benchmark process
run_model() {
    local M_NAME=$1
    local STAGE=$2
    
    # Mapping names into preset environment variables
    local ENV_PREFIX=$(echo "$M_NAME" | tr '[:lower:]' '[:upper:]')
    local BS_VAR="${ENV_PREFIX}_BS"
    local IT_VAR="${ENV_PREFIX}_IT"
    
    # Resolving references for BS and IT
    local BS_VAL=${!BS_VAR}
    local IT_VAL=${!IT_VAR}
    
    echo "[$(date +'%H:%M:%S')] Starting STAGE $STAGE: model $M_NAME (bs=${BS_VAL:-16}, it=${IT_VAL:-1})"
    
    # Soft safeguard limit set to 85 seconds preventing permanent deadlocks.
    # Calibration should resolve execution lengths natively approximating 80 seconds.
    timeout 85s docker run --name "torchbench_wl_${W_ID}_${STAGE}" \
        --rm \
        --ipc host \
        --gpus all \
        torchbench-suite:1.0.1 \
        -c "python3 run.py $M_NAME -d=cuda -t=train --bs=${BS_VAL:-16} --it=${IT_VAL:-1} --precision=fp32"
        
    echo "[$(date +'%H:%M:%S')] Completed STAGE $STAGE"
}

# ------------------------------------------------------------------
#  [2] WORKLOAD CYCLE EXECUTION
# ------------------------------------------------------------------

cd /home/lepin/repos/torchbench-caise

run_model $MODEL1 1
run_model $MODEL2 2
run_model $MODEL3 3

# ------------------------------------------------------------------
#  [3] TERMINATE MEASUREMENT TOOL
# ------------------------------------------------------------------

echo "[$(date +'%H:%M:%S')] Terminating tool..."
# kill $PID_TOOL

echo "=========================================================="
echo " Workload $W_ID Completed."
echo "=========================================================="
