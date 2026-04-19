#!/bin/bash

# --- CONFIGURATION ---
# Note: 100ms removed - minimum valid msTestPhasePeriod is 200ms
SELECTED_WINDOWS=${WINDOW_FILTER:-"200 400 800 1600 3200 6400"}
SELECTED_PERIODS=${PERIOD_FILTER:-"10 20 40 80"}

# Absolute paths to avoid root/user confusion
USER_HOME="/home/macierz/s193246"
REPO_DIR="$USER_HOME/repos/split"
TORCHBENCH_DIR="$USER_HOME/repos/torchbench-caise"
CONFIG_FILE="$REPO_DIR/config.yaml"
RESULTS_BASE="$REPO_DIR/results_experiment_$(date +%Y%m%d_%H%M)"
DEPO_BIN="$USER_HOME/local/bin/DEPO"
TEMP_WORKLOAD="$USER_HOME/depo-scripts/current_workload.sh"

# Docker Cache Configuration
CACHE_FLAGS="-v $USER_HOME/.torch_cache/pip:/root/.cache/pip \
             -v $USER_HOME/.torch_cache/torch:/root/.cache/torch \
             -v $USER_HOME/.torch_cache/inductor:/home_cache/inductor \
             -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor"

# Ensure directories exist
mkdir -p "$USER_HOME/.torch_cache/pip" "$USER_HOME/.torch_cache/torch" "$USER_HOME/.torch_cache/inductor"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

update_config() {
    local window=$1
    local period=$2
    # Enforce minimum window of 200ms
    if [ "$window" -lt 200 ]; then
        echo "WARNING: Window ${window}ms is below minimum (200ms). Clamping to 200ms."
        window=200
    fi
    sed -i "s/msTestPhasePeriod: .*/msTestPhasePeriod: $window/" "$CONFIG_FILE"
    sed -i "s/repeatTuningPeriodInSec: .*/repeatTuningPeriodInSec: $period/" "$CONFIG_FILE"
    sed -i "s/doWaitPhase: .*/doWaitPhase: 1/" "$CONFIG_FILE"
    sed -i "s/targetMetric: .*/targetMetric: 1/" "$CONFIG_FILE"
}

generate_workload_script() {
    local m1=$1 m2=$2 m3=$3
    
    # Get params from apl10.txt specifications (per model, not per position)
    case $m1 in "resnet152") p1="--it=160 --bs=126" ;; "vgg16") p1="--it=230 --bs=126" ;; "hf_Bert") p1="--it=25 --bs=126" ;; esac
    case $m2 in "resnet152") p2="--it=160 --bs=126" ;; "vgg16") p2="--it=230 --bs=126" ;; "hf_Bert") p2="--it=25 --bs=126" ;; esac
    case $m3 in "resnet152") p3="--it=160 --bs=126" ;; "vgg16") p3="--it=230 --bs=126" ;; "hf_Bert") p3="--it=25 --bs=126" ;; esac

    cat << EOF > "$TEMP_WORKLOAD"
#!/bin/bash
cd "$TORCHBENCH_DIR" || exit 1

echo "Starting Segment 1: $m1"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" $CACHE_FLAGS torchbench-suite:1.0.1 -c "python3 run.py $m1 -d=cuda -t=train $p1 --precision=fp32"

echo "Starting Segment 2: $m2"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" $CACHE_FLAGS torchbench-suite:1.0.1 -c "python3 run.py $m2 -d=cuda -t=train $p2 --precision=fp32"

echo "Starting Segment 3: $m3"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" $CACHE_FLAGS torchbench-suite:1.0.1 -c "python3 run.py $m3 -d=cuda -t=train $p3 --precision=fp32"
EOF
    chmod +x "$TEMP_WORKLOAD"
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

cd "$REPO_DIR" || exit 1
MODELS=("resnet152" "vgg16" "hf_Bert")

for W in $SELECTED_WINDOWS; do
    for T in $SELECTED_PERIODS; do
        
        echo ">>> STARTING BATCH: Window=${W}ms, TuningPeriod=${T}s"
        update_config "$W" "$T"
        
        for m1 in "${MODELS[@]}"; do
            for m2 in "${MODELS[@]}"; do
                for m3 in "${MODELS[@]}"; do
                    
                    WORKLOAD_NAME="${m1}_${m2}_${m3}"
                    FINAL_NAME="res_W${W}_T${T}_${WORKLOAD_NAME}"
                    FINAL_DEST="$REPO_DIR/$FINAL_NAME"
                    
                    if [ -d "$FINAL_DEST" ]; then
                        echo "Skipping $WORKLOAD_NAME (already exists)"
                        continue
                    fi
                    
                    echo "--- Running Workload: $WORKLOAD_NAME"
                    generate_workload_script "$m1" "$m2" "$m3"
                    
                    # Run DEPO as root
                    sudo "$DEPO_BIN" "$TEMP_WORKLOAD"
                    
                    # Identify and move result
                    NEW_FOLDER=$(ls -td "$REPO_DIR"/gpu_experiment_* 2>/dev/null | head -1)
                    
                    if [ -n "$NEW_FOLDER" ]; then
                        # Rename in place within REPO_DIR — matches run_single.sh approach
                        mv "$NEW_FOLDER" "$FINAL_DEST"
                        cp "$CONFIG_FILE" "$FINAL_DEST/config_used.yaml"
                    else
                        echo "ERROR: DEPO did not produce a folder"
                    fi
                done
            done
        done
    done
done
