#!/bin/bash
export LD_LIBRARY_PATH="/home/macierz/s193246/local/lib"
exec "/home/macierz/s193246/repos/split/build/apps/DEPO/DEPO" --gss --eds --gpu 0 "$@"