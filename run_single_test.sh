#!/bin/bash
USER_HOME="${HOME}"
if [ -n "$SUDO_USER" ]; then
    USER_HOME=$(getent passwd "$SUDO_USER" | cut -d: -f6)
fi

cd "$USER_HOME/repos/split" || exit 1

echo "Segment 1: resnet152 --it=320 --bs=126"
docker run --rm --ipc host --gpus all --cap-add=SYS_ADMIN --entrypoint "/bin/bash" \
    -v "$USER_HOME/.torch_cache/pip:/root/.cache/pip" \
    -v "$USER_HOME/.torch_cache/torch:/root/.cache/torch" \
    -v "$USER_HOME/.torch_cache/inductor:/home_cache/inductor" \
    -v "$USER_HOME/repos/split/profiling_injection:/injection" \
    -v /tmp/depo_kernelcount:/kernelcount \
    -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor \
    -e CUDA_INJECTION64_PATH=/injection/libinjection_2.so \
    -e INJECTION_KERNEL_COUNT=1 \
    -w /kernelcount \
    torchbench-suite:1.0.1 -c "CUPTI_DIR=\$(find /srv/benchmark/venv/lib /usr/local /usr/lib/x86_64-linux-gnu -name 'libcupti.so*' 2>/dev/null | grep -v 'nsight' | head -n 1 | xargs dirname); mkdir -p /tmp/cuda-libs; ln -sf \$CUPTI_DIR/libcupti.so* /tmp/cuda-libs/; ln -sf \$CUPTI_DIR/libnvperf_host.so* /tmp/cuda-libs/; ln -sf libcupti.so /tmp/cuda-libs/libcupti.so.11; ln -sf libcupti.so /tmp/cuda-libs/libcupti.so.12; ln -sf libcupti.so /tmp/cuda-libs/libcupti.so.13; export LD_LIBRARY_PATH=/tmp/cuda-libs:\$LD_LIBRARY_PATH; python3 /srv/benchmark/run.py resnet152 -d=cuda -t=train --it=1000 --bs=32 --precision=fp32"
