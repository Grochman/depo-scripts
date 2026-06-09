#!/bin/bash

# Clean exit on Ctrl+C — also kill any running sudo DEPO child
trap 'echo "Interrupted. Stopping..."; sudo pkill -f DEPO 2>/dev/null; exit 1' INT TERM

# --- CONFIGURATION ---
NUM_RUNS=1

USER_HOME="${HOME}"
REPO_DIR="$USER_HOME/repos/split"
TORCHBENCH_DIR="$USER_HOME/repos/torchbench-caise"
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

mkdir -p "$USER_HOME/.torch_cache/pip" "$USER_HOME/.torch_cache/torch" "$USER_HOME/.torch_cache/inductor"

# ==============================================================================
# HELPER FUNCTIONS
# ==============================================================================

generate_workload_script() {
    local m1=$1 m2=$2 m3=$3

    case $m1 in "resnet152") p1="--it=800 --bs=32" ;; "opacus_cifar10") p1="--it=4000 --bs=64" ;; "hf_Bert") p1="--it=600 --bs=16" ;; esac
    case $m2 in "resnet152") p2="--it=800 --bs=32" ;; "opacus_cifar10") p2="--it=4000 --bs=64" ;; "hf_Bert") p2="--it=600 --bs=16" ;; esac
    case $m3 in "resnet152") p3="--it=800 --bs=32" ;; "opacus_cifar10") p3="--it=4000 --bs=64" ;; "hf_Bert") p3="--it=600 --bs=16" ;; esac

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
# MAIN LOOP — 5 no-tuning runs per benchmark sequence (6 permutations)
# ==============================================================================

cd "$REPO_DIR" || exit 1

MODELS=("resnet152" "opacus_cifar10" "hf_Bert")

for RUN in $(seq 1 "$NUM_RUNS"); do
    echo ">>> STARTING RUN $RUN / $NUM_RUNS (no-tuning)"

    for i in 0 1 2; do
        for j in 0 1 2; do
            [[ $j -eq $i ]] && continue
            for k in 0 1 2; do
                [[ $k -eq $i || $k -eq $j ]] && continue

                m1="${MODELS[$i]}"
                m2="${MODELS[$j]}"
                m3="${MODELS[$k]}"

                WORKLOAD_NAME="${m1}_${m2}_${m3}"
                FINAL_NAME="res_noTuning_r${RUN}_${WORKLOAD_NAME}"
                FINAL_DEST="$REPO_DIR/$FINAL_NAME"

                if [ -d "$FINAL_DEST" ]; then
                    echo "Overwriting existing directory $FINAL_NAME"
                    rm -rf "$FINAL_DEST"
                fi

                echo "--- Run $RUN: $WORKLOAD_NAME (no-tuning)"
                generate_workload_script "$m1" "$m2" "$m3"

                sudo "$DEPO_BIN" "$TEMP_WORKLOAD"

                TS=$(date '+%Y-%m-%d %H:%M:%S')
                echo "=== [$TS] run=${RUN} no-tuning ${WORKLOAD_NAME} ==" >> "$NVIDIA_SMI_LOG"
                sudo nvidia-smi >> "$NVIDIA_SMI_LOG" 2>&1
                echo "" >> "$NVIDIA_SMI_LOG"

                NEW_FOLDER=$(ls -td "$REPO_DIR"/gpu_experiment_* 2>/dev/null | head -1)

                if [ -n "$NEW_FOLDER" ]; then
                    mv "$NEW_FOLDER" "$FINAL_DEST"
                    cp "$NVIDIA_SMI_LOG" "$FINAL_DEST/nvidia_smi_snapshot.txt"
                else
                    echo "ERROR: DEPO did not produce a folder for $FINAL_NAME"
                fi
            done
        done
    done
done

echo ">>> Finished: $NUM_RUNS runs × 6 sequences = $((NUM_RUNS * 6)) expected results"
