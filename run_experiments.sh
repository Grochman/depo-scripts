#!/bin/bash

# Clean exit on Ctrl+C — also kill any running sudo DEPO child
trap 'echo "Interrupted. Stopping..."; sudo pkill -f DEPO 2>/dev/null; exit 1' INT TERM

# --- CONFIGURATION ---
# Note: 100ms removed - minimum valid msTestPhasePeriod is 200ms
SELECTED_WINDOWS=${WINDOW_FILTER:-"200 400 800 1600 3200 6400 12800"}
SELECTED_PERIODS=${PERIOD_FILTER:-"10 20 40 80 160"}

# Check if WINDOW_FILTER and PERIOD_FILTER are passed (via environment variables)
if [ -n "$WINDOW_FILTER" ] || [ -n "$PERIOD_FILTER" ]; then
    # Behavior should not change - one iteration over the specified range, standard folder name
    NUM_RUNS=1
    MULTI_RUN=false
else
    # No WINDOW_FILTER and no PERIOD_FILTER passed
    # Default to 5 runs, unless specified via NUM_RUNS environment variable
    NUM_RUNS=${NUM_RUNS:-5}
    if ! [[ "$NUM_RUNS" =~ ^[0-9]+$ ]]; then
        echo "Error: NUM_RUNS must be a positive integer."
        exit 1
    fi
    MULTI_RUN=true
fi

# Absolute paths to avoid root/user confusion
USER_HOME="${HOME}"
REPO_DIR="$USER_HOME/repos/split"
TORCHBENCH_DIR="$USER_HOME/repos/torchbench-caise"
CONFIG_FILE="$REPO_DIR/config.yaml"
RESULTS_BASE="$REPO_DIR/results_experiment_$(date +%Y%m%d_%H%M)"
DEPO_BIN="$USER_HOME/local/bin/DEPO"
TEMP_WORKLOAD="$USER_HOME/depo-scripts/current_workload.sh"
NVIDIA_SMI_LOG="$REPO_DIR/nvidia_smi_run_log.txt"

# Docker Cache Configuration
CACHE_FLAGS="--cap-add=SYS_ADMIN \
             -v $USER_HOME/.torch_cache/pip:/root/.cache/pip \
             -v $USER_HOME/.torch_cache/torch:/root/.cache/torch \
             -v $USER_HOME/.torch_cache/inductor:/home_cache/inductor \
             -v $REPO_DIR/profiling_injection:/injection \
             -v /tmp/depo_kernelcount:/kernelcount \
             -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor \
             -e CUDA_INJECTION64_PATH=/injection/libinjection_2.so \
             -e INJECTION_KERNEL_COUNT=1 \
             -w /kernelcount"

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
    
    case $m1 in "resnet152") p1="--it=2500 --bs=32" ;; "opacus_cifar10") p1="--it=1700 --bs=512" ;; "hf_Bert") p1="--it=1000 --bs=16" ;; esac
    case $m2 in "resnet152") p2="--it=2500 --bs=32" ;; "opacus_cifar10") p2="--it=1700 --bs=512" ;; "hf_Bert") p2="--it=1000 --bs=16" ;; esac
    case $m3 in "resnet152") p3="--it=2500 --bs=32" ;; "opacus_cifar10") p3="--it=1700 --bs=512" ;; "hf_Bert") p3="--it=1000 --bs=16" ;; esac

    local wrapper="CUPTI_DIR=\$(find /srv/benchmark/venv/lib /usr/local /usr/lib/x86_64-linux-gnu -name \"libcupti.so*\" 2>/dev/null | grep -v \"nsight\" | head -n 1 | xargs dirname); mkdir -p /tmp/cuda-libs; ln -sf \$CUPTI_DIR/libcupti.so* /tmp/cuda-libs/; ln -sf \$CUPTI_DIR/libnvperf_host.so* /tmp/cuda-libs/; ln -sf libcupti.so /tmp/cuda-libs/libcupti.so.11; ln -sf libcupti.so /tmp/cuda-libs/libcupti.so.12; ln -sf libcupti.so /tmp/cuda-libs/libcupti.so.13; export LD_LIBRARY_PATH=/tmp/cuda-libs:\$LD_LIBRARY_PATH;"

    cat << EOF > "$TEMP_WORKLOAD"
#!/bin/bash
cd "$TORCHBENCH_DIR" || exit 1

echo "Starting Segment 1: $m1"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" $CACHE_FLAGS torchbench-suite:1.0.1 -c '$wrapper python3 /srv/benchmark/run.py $m1 -d=cuda -t=train $p1 --precision=fp32'

echo "Starting Segment 2: $m2"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" $CACHE_FLAGS torchbench-suite:1.0.1 -c '$wrapper python3 /srv/benchmark/run.py $m2 -d=cuda -t=train $p2 --precision=fp32'

echo "Starting Segment 3: $m3"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" $CACHE_FLAGS torchbench-suite:1.0.1 -c '$wrapper python3 /srv/benchmark/run.py $m3 -d=cuda -t=train $p3 --precision=fp32'
EOF
    chmod +x "$TEMP_WORKLOAD"
}

# ==============================================================================
# MAIN LOOP
# ==============================================================================

cd "$REPO_DIR" || exit 1

for RUN in $(seq 1 "$NUM_RUNS"); do
    if [ "$MULTI_RUN" = true ]; then
        echo ">>> STARTING RUN $RUN / $NUM_RUNS"
    fi

    for W in $SELECTED_WINDOWS; do
        for T in $SELECTED_PERIODS; do
            
            echo ">>> STARTING BATCH: Window=${W}ms, TuningPeriod=${T}s"
            update_config "$W" "$T"

            MODELS=("resnet152" "opacus_cifar10" "hf_Bert")

            for i in 0 1 2; do
                for j in 0 1 2; do
                    [[ $j -eq $i ]] && continue
                    for k in 0 1 2; do
                        [[ $k -eq $i || $k -eq $j ]] && continue

                        m1="${MODELS[$i]}"
                        m2="${MODELS[$j]}"
                        m3="${MODELS[$k]}"

                        WORKLOAD_NAME="${m1}_${m2}_${m3}"
                        if [ "$MULTI_RUN" = true ]; then
                            FINAL_NAME="res_W${W}_T${T}_r${RUN}_${WORKLOAD_NAME}"
                        else
                            FINAL_NAME="res_W${W}_T${T}_${WORKLOAD_NAME}"
                        fi
                        FINAL_DEST="$REPO_DIR/$FINAL_NAME"

                        if [ -d "$FINAL_DEST" ]; then
                            echo "Overwriting existing directory $FINAL_NAME"
                            rm -rf "$FINAL_DEST"
                        fi

                        echo "--- Running Workload: $WORKLOAD_NAME"
                        generate_workload_script "$m1" "$m2" "$m3"

                        # Run DEPO as root
                        sudo "$DEPO_BIN" "$TEMP_WORKLOAD"

                        # Log GPU state after each run
                        TS=$(date '+%Y-%m-%d %H:%M:%S')
                        if [ "$MULTI_RUN" = true ]; then
                            echo "=== [$TS] W=${W} T=${T} run=${RUN} ${WORKLOAD_NAME} ==" >> "$NVIDIA_SMI_LOG"
                        else
                            echo "=== [$TS] W=${W} T=${T} ${WORKLOAD_NAME} ==" >> "$NVIDIA_SMI_LOG"
                        fi
                        sudo nvidia-smi >> "$NVIDIA_SMI_LOG" 2>&1
                        echo "" >> "$NVIDIA_SMI_LOG"

                        # Identify and move result
                        NEW_FOLDER=$(ls -td "$REPO_DIR"/gpu_experiment_* 2>/dev/null | head -1)

                        if [ -n "$NEW_FOLDER" ]; then
                            mv "$NEW_FOLDER" "$FINAL_DEST"
                            cp "$CONFIG_FILE" "$FINAL_DEST/config_used.yaml"
                            cp "$NVIDIA_SMI_LOG" "$FINAL_DEST/nvidia_smi_snapshot.txt"
                        else
                            echo "ERROR: DEPO did not produce a folder"
                        fi
                    done
                done
            done
        done
    done
done

