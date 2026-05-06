cd "/home/macierz/s193246/repos/split" || exit 1

echo "Segment 1: resnet152 --it=320 --bs=126"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" \
    -v /home/macierz/s193246/.torch_cache/pip:/root/.cache/pip \
    -v /home/macierz/s193246/.torch_cache/torch:/root/.cache/torch \
    -v /home/macierz/s193246/.torch_cache/inductor:/home_cache/inductor \
    -v /home/macierz/s193246/repos/split/profiling_injection:/injection \
    -v /home/macierz/s193246/repos/split:/kernelcount \
    -v /usr/local/cuda-13.0/targets/x86_64-linux/lib:/cuda13lib:ro \
    -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor \
    -e CUDA_INJECTION64_PATH=/injection/libinjection_2.so \
    -e INJECTION_KERNEL_COUNT=1 \
    -e LD_LIBRARY_PATH=/cuda13lib:/usr/local/cuda/lib64 \
    -w /kernelcount \
    torchbench-suite:1.0.1 -c "python3 /srv/benchmark/run.py resnet152 -d=cuda -t=train --it=10 --bs=32 --precision=fp32"

# ./minibenchmarks/openmp/fft 1024 300