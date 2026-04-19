#!/bin/bash
cd "/home/macierz/s193246/repos/torchbench-caise" || exit 1

echo "Starting Segment 1: vgg16"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" -v /home/macierz/s193246/.torch_cache/pip:/root/.cache/pip              -v /home/macierz/s193246/.torch_cache/torch:/root/.cache/torch              -v /home/macierz/s193246/.torch_cache/inductor:/home_cache/inductor              -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor torchbench-suite:1.0.1 -c "python3 run.py vgg16 -d=cuda -t=train --it=230 --bs=126 --precision=fp32"

echo "Starting Segment 2: vgg16"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" -v /home/macierz/s193246/.torch_cache/pip:/root/.cache/pip              -v /home/macierz/s193246/.torch_cache/torch:/root/.cache/torch              -v /home/macierz/s193246/.torch_cache/inductor:/home_cache/inductor              -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor torchbench-suite:1.0.1 -c "python3 run.py vgg16 -d=cuda -t=train --it=230 --bs=126 --precision=fp32"

echo "Starting Segment 3: hf_Bert"
docker run --rm --ipc host --gpus all --entrypoint "/bin/bash" -v /home/macierz/s193246/.torch_cache/pip:/root/.cache/pip              -v /home/macierz/s193246/.torch_cache/torch:/root/.cache/torch              -v /home/macierz/s193246/.torch_cache/inductor:/home_cache/inductor              -e TORCHINDUCTOR_CACHE_DIR=/home_cache/inductor torchbench-suite:1.0.1 -c "python3 run.py hf_Bert -d=cuda -t=train --it=25 --bs=126 --precision=fp32"
