cd "/home/macierz/s193246/repos/split" || exit 1

echo "Segment 1: resnet152 --it=320 --bs=126"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" -v /home/macierz/s193246/.torch_cache/pip:/root/.cache/pip              -v /home/macierz/s193246/.torch_cache/torch:/root/.cache/torch              -v /home/macierz/s193246/.torch_cache/inductor:/home_cache/inductor              -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor torchbench-suite:1.0.1 -c "python3 run.py vgg16 -d=cuda -t=train --it=230 --bs=126 --precision=fp32"

# ./minibenchmarks/openmp/fft 1024 300